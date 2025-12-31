# frozen_string_literal: true

module Smolagents
  # An agent that uses JSON-like tool calls, leveraging the LLM's tool calling capabilities.
  #
  # This agent uses the model's `get_tool_call` method to parse and execute tool calls.
  #
  # @example
  #   agent = ToolCallingAgent.new(
  #     tools: [GetWeatherTool.new, SearchTool.new],
  #     model: some_model
  #   )
  #   result = agent.run(task: "What's the weather in Paris?")
  #
  class ToolCallingAgent < MultiStepAgent
    # @return [Integer, nil] Maximum threads for parallel tool calls
    attr_accessor :max_tool_threads

    # Create a new ToolCallingAgent
    #
    # @param tools [Array<Tool>] Tools the agent can use
    # @param model [Object] Model for generating actions
    # @param prompt_templates [PromptTemplates, nil] Prompt templates
    # @param planning_interval [Integer, nil] Planning interval
    # @param stream_outputs [Boolean] Whether to stream outputs
    # @param max_tool_threads [Integer, nil] Max threads for parallel tool calls
    # @param kwargs [Hash] Additional arguments for parent class
    def initialize(
      tools:,
      model:,
      prompt_templates: nil,
      planning_interval: nil,
      stream_outputs: false,
      max_tool_threads: nil,
      **kwargs
    )
      prompt_templates ||= default_tool_calling_prompts

      super(
        tools: tools,
        model: model,
        prompt_templates: prompt_templates,
        planning_interval: planning_interval,
        **kwargs
      )

      @stream_outputs = stream_outputs
      if @stream_outputs && !@model.respond_to?(:generate_stream)
        raise ArgumentError, "`stream_outputs` is set to True, but the model has no `generate_stream` method."
      end

      @max_tool_threads = max_tool_threads
    end

    # Get combined list of tools and managed agents
    # @return [Array<Tool, MultiStepAgent>]
    def tools_and_managed_agents
      @tools.values + @managed_agents.values
    end

    # Initialize the system prompt
    # @return [String]
    def initialize_system_prompt
      populate_template(
        @prompt_templates[:system_prompt],
        tools: @tools,
        managed_agents: @managed_agents,
        custom_instructions: @instructions
      )
    end

    # Perform one step with streaming
    # @param memory_step [ActionStep] The memory step to populate
    # @return [Enumerator] Stream of step events
    def step_stream(memory_step)
      Enumerator.new do |yielder|
        memory_messages = write_memory_to_messages
        input_messages = memory_messages.dup
        memory_step.model_input_messages = input_messages

        begin
          chat_message = if @stream_outputs && @model.respond_to?(:generate_stream)
                           stream_model_output(input_messages, yielder)
                         else
                           generate_model_output(input_messages)
                         end

          memory_step.model_output_message = chat_message
          memory_step.model_output = chat_message.content
          memory_step.token_usage = chat_message.token_usage
        rescue StandardError => e
          raise AgentGenerationError.new("Error while generating output:\n#{e}", @logger)
        end

        # Parse tool calls if needed
        if chat_message.tool_calls.nil? || chat_message.tool_calls.empty?
          if @model.respond_to?(:parse_tool_calls)
            begin
              chat_message = @model.parse_tool_calls(chat_message)
            rescue StandardError => e
              raise AgentParsingError.new("Error while parsing tool call from model output: #{e}", @logger)
            end
          end
        else
          chat_message.tool_calls.each do |tool_call|
            tool_call.function.arguments = parse_json_if_needed(tool_call.function.arguments)
          end
        end

        # Process tool calls
        final_answer = nil
        got_final_answer = false

        process_tool_calls(chat_message, memory_step).each do |output|
          yielder << output

          if output.is_a?(ToolOutput)
            if output.final_answer?
              if chat_message.tool_calls && chat_message.tool_calls.length > 1
                raise AgentExecutionError.new(
                  "If you want to return an answer, please do not perform any other tool calls!",
                  @logger
                )
              end
              if got_final_answer
                raise AgentToolExecutionError.new(
                  "You returned multiple final answers. Please return only one!",
                  @logger
                )
              end
              final_answer = output.output
              got_final_answer = true

              # Handle state variables
              if final_answer.is_a?(String) && @state.key?(final_answer)
                final_answer = @state[final_answer]
              end
            end
          end
        end

        yielder << ActionOutput.new(output: final_answer, is_final_answer: got_final_answer)
      end
    end

    # Process tool calls from the model output
    # @param chat_message [ChatMessage] The message with tool calls
    # @param memory_step [ActionStep] The memory step
    # @return [Enumerator] Stream of tool calls and outputs
    def process_tool_calls(chat_message, memory_step)
      Enumerator.new do |yielder|
        return if chat_message.tool_calls.nil?

        parallel_calls = {}
        chat_message.tool_calls.each do |chat_tool_call|
          tool_call = ToolCall.new(
            name: chat_tool_call.function.name,
            arguments: chat_tool_call.function.arguments,
            id: chat_tool_call.id
          )
          yielder << tool_call
          parallel_calls[tool_call.id] = tool_call
        end

        # Process tool calls (sequentially for now, could be parallelized)
        outputs = {}
        parallel_calls.each_value do |tool_call|
          tool_output = process_single_tool_call(tool_call)
          outputs[tool_output.id] = tool_output
          yielder << tool_output
        end

        # Update memory step
        memory_step.tool_calls = parallel_calls.keys.sort.map { |k| parallel_calls[k] }
        memory_step.observations ||= ""
        outputs.keys.sort.each do |k|
          memory_step.observations += "#{outputs[k].observation}\n"
        end
        memory_step.observations = memory_step.observations.rstrip
      end
    end

    # Execute a tool call
    # @param tool_name [String] Name of the tool
    # @param arguments [Hash, String] Tool arguments
    # @return [Object] Tool result
    def execute_tool_call(tool_name, arguments)
      available_tools = @tools.merge(@managed_agents)

      unless available_tools.key?(tool_name)
        raise AgentToolExecutionError.new(
          "Unknown tool #{tool_name}, should be one of: #{available_tools.keys.join(', ')}.",
          @logger
        )
      end

      tool = available_tools[tool_name]
      arguments = substitute_state_variables(arguments)
      is_managed_agent = @managed_agents.key?(tool_name)

      begin
        Smolagents.validate_tool_arguments(tool, arguments)
      rescue ArgumentError, TypeError => e
        raise AgentToolCallError.new(e.message, @logger)
      rescue StandardError => e
        raise AgentToolExecutionError.new(
          "Error executing tool '#{tool_name}' with arguments #{arguments}: #{e.class}: #{e}",
          @logger
        )
      end

      begin
        if arguments.is_a?(Hash)
          if is_managed_agent
            tool.call(arguments[:task], **arguments.except(:task))
          else
            tool.call(**arguments, sanitize_inputs_outputs: true)
          end
        else
          if is_managed_agent
            tool.call(arguments)
          else
            tool.call(arguments, sanitize_inputs_outputs: true)
          end
        end
      rescue StandardError => e
        if is_managed_agent
          error_msg = "Error executing request to team member '#{tool_name}' with arguments #{arguments}: #{e}\n" \
                      "Please try again or request to another team member"
        else
          error_msg = "Error executing tool '#{tool_name}' with arguments #{arguments}: #{e.class}: #{e}\n" \
                      "Please try again or use another tool"
        end
        raise AgentToolExecutionError.new(error_msg, @logger)
      end
    end

    private

    def default_tool_calling_prompts
      PromptTemplates.new(
        system_prompt: <<~PROMPT,
          You are a helpful assistant that can use tools to help answer questions.

          Available tools:
          {{tools}}

          {{custom_instructions}}
        PROMPT
        planning: PlanningPromptTemplate.new(
          initial_plan: "Create a plan to solve: {{task}}",
          update_plan_pre_messages: "Review the task: {{task}}",
          update_plan_post_messages: "Update your plan with {{remaining_steps}} steps remaining."
        ),
        managed_agent: ManagedAgentPromptTemplate.new(
          task: "You are {{name}}. Complete this task: {{task}}",
          report: "Agent {{name}} completed with result: {{final_answer}}"
        ),
        final_answer: FinalAnswerPromptTemplate.new(
          pre_messages: "Based on your work, provide a final answer.",
          post_messages: "Provide the final answer for: {{task}}"
        )
      )
    end

    def stream_model_output(input_messages, yielder)
      deltas = []
      @model.generate_stream(
        input_messages,
        stop_sequences: ["Observation:", "Calling tools:"],
        tools_to_call_from: tools_and_managed_agents
      ).each do |event|
        deltas << event
        yielder << event
      end
      agglomerate_stream_deltas(deltas)
    end

    def generate_model_output(input_messages)
      @model.generate(
        input_messages,
        stop_sequences: ["Observation:", "Calling tools:"],
        tools_to_call_from: tools_and_managed_agents
      )
    end

    def process_single_tool_call(tool_call)
      tool_name = tool_call.name
      tool_arguments = tool_call.arguments || {}

      @logger.log("Calling tool: '#{tool_name}' with arguments: #{tool_arguments}", level: LogLevel::INFO)

      tool_call_result = execute_tool_call(tool_name, tool_arguments)
      result_type = tool_call_result.class

      if result_type == AgentImage
        observation_name = "image.png"
        @state[observation_name] = tool_call_result
        observation = "Stored '#{observation_name}' in memory."
      elsif result_type == AgentAudio
        observation_name = "audio.mp3"
        @state[observation_name] = tool_call_result
        observation = "Stored '#{observation_name}' in memory."
      else
        observation = tool_call_result.to_s.strip
      end

      @logger.log("Observations: #{observation}", level: LogLevel::INFO)

      ToolOutput.new(
        id: tool_call.id,
        output: tool_call_result,
        is_final_answer: tool_name == "final_answer",
        observation: observation,
        tool_call: tool_call
      )
    end

    def substitute_state_variables(arguments)
      if arguments.is_a?(Hash)
        arguments.transform_values do |value|
          value.is_a?(String) && @state.key?(value) ? @state[value] : value
        end
      else
        arguments
      end
    end

    def parse_json_if_needed(value)
      return value unless value.is_a?(String)

      begin
        require "json"
        JSON.parse(value)
      rescue JSON::ParserError
        value
      end
    end

    def populate_template(template, **variables)
      return template if template.nil? || template.empty?

      result = template.dup
      variables.each do |key, value|
        result.gsub!(/\{\{\s*#{key}\s*\}\}/, value.to_s)
      end
      result
    end

    def agglomerate_stream_deltas(deltas)
      # Combine stream deltas into a single message
      # This is a simplified version
      content = ""
      tool_calls = []
      token_usage = nil

      deltas.each do |delta|
        content += delta.content.to_s if delta.respond_to?(:content) && delta.content
        if delta.respond_to?(:tool_calls) && delta.tool_calls
          tool_calls.concat(delta.tool_calls)
        end
        token_usage = delta.token_usage if delta.respond_to?(:token_usage) && delta.token_usage
      end

      ChatMessage.new(
        role: MessageRole::ASSISTANT,
        content: content.empty? ? nil : content,
        tool_calls: tool_calls.empty? ? nil : tool_calls,
        token_usage: token_usage
      )
    end
  end
end
