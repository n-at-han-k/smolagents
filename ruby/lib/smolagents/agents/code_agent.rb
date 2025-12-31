# frozen_string_literal: true

module Smolagents
  # An agent that generates and executes code to solve tasks.
  #
  # In this agent, tool calls are formulated by the LLM as code,
  # which is then parsed and executed.
  #
  # @example
  #   agent = CodeAgent.new(
  #     tools: [GetWeatherTool.new],
  #     model: some_model
  #   )
  #   result = agent.run(task: "Calculate 2^3.7384")
  #
  class CodeAgent < MultiStepAgent
    # @return [Array<String>] Additional authorized imports
    attr_accessor :additional_authorized_imports

    # @return [Array<String>] All authorized imports
    attr_accessor :authorized_imports

    # @return [Integer, nil] Maximum print output length
    attr_accessor :max_print_outputs_length

    # @return [String] Executor type ("local", "docker", etc.)
    attr_accessor :executor_type

    # @return [Hash] Executor configuration
    attr_accessor :executor_kwargs

    # @return [Object] The Ruby/Python executor
    attr_accessor :ruby_executor

    # @return [Array<String>] Code block opening and closing tags
    attr_accessor :code_block_tags

    # @return [Boolean] Whether to use structured outputs internally
    attr_accessor :use_structured_outputs_internally

    # Base builtin modules that are always allowed
    BASE_BUILTIN_MODULES = %w[
      base64 json time date datetime math random re
      collections itertools functools operator string
    ].freeze

    # Create a new CodeAgent
    #
    # @param tools [Array<Tool>] Tools the agent can use
    # @param model [Object] Model for generating actions
    # @param prompt_templates [PromptTemplates, nil] Prompt templates
    # @param additional_authorized_imports [Array<String>, nil] Extra allowed imports
    # @param planning_interval [Integer, nil] Planning interval
    # @param executor [Object, nil] Custom code executor
    # @param executor_type [String] Type of executor ("local", "docker", etc.)
    # @param executor_kwargs [Hash, nil] Executor configuration
    # @param max_print_outputs_length [Integer, nil] Max print output length
    # @param stream_outputs [Boolean] Whether to stream outputs
    # @param use_structured_outputs_internally [Boolean] Use structured outputs
    # @param code_block_tags [Array<String>, String, nil] Code block tags
    # @param kwargs [Hash] Additional arguments for parent class
    def initialize(
      tools:,
      model:,
      prompt_templates: nil,
      additional_authorized_imports: nil,
      planning_interval: nil,
      executor: nil,
      executor_type: "local",
      executor_kwargs: nil,
      max_print_outputs_length: nil,
      stream_outputs: false,
      use_structured_outputs_internally: false,
      code_block_tags: nil,
      **kwargs
    )
      @additional_authorized_imports = additional_authorized_imports || []
      @authorized_imports = (BASE_BUILTIN_MODULES + @additional_authorized_imports).sort.uniq
      @max_print_outputs_length = max_print_outputs_length
      @use_structured_outputs_internally = use_structured_outputs_internally

      prompt_templates ||= default_code_agent_prompts

      if code_block_tags.is_a?(String) && code_block_tags != "markdown"
        raise ArgumentError, "Only 'markdown' is supported for a string argument to `code_block_tags`."
      end

      @code_block_tags = case code_block_tags
                         when Array then code_block_tags
                         when "markdown" then ["```ruby", "```"]
                         else ["<code>", "</code>"]
                         end

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

      if @additional_authorized_imports.include?("*")
        @logger.log(
          "Caution: you authorized all imports, meaning the agent can import any package.",
          level: LogLevel::INFO
        )
      end

      @executor_type = executor_type
      @executor_kwargs = executor_kwargs || {}
      @ruby_executor = executor || create_ruby_executor
    end

    # Initialize the system prompt
    # @return [String]
    def initialize_system_prompt
      imports_text = if @authorized_imports.include?("*")
                       "You can require any gem you want."
                     else
                       @authorized_imports.to_s
                     end

      populate_template(
        @prompt_templates[:system_prompt],
        tools: @tools,
        managed_agents: @managed_agents,
        authorized_imports: imports_text,
        custom_instructions: @instructions,
        code_block_opening_tag: @code_block_tags[0],
        code_block_closing_tag: @code_block_tags[1]
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

        stop_sequences = ["Observation:", "Calling tools:"]
        unless @code_block_tags[1].include?(@code_block_tags[0])
          stop_sequences << @code_block_tags[1]
        end

        begin
          chat_message = if @stream_outputs && @model.respond_to?(:generate_stream)
                           stream_model_output(input_messages, stop_sequences, yielder)
                         else
                           generate_model_output(input_messages, stop_sequences)
                         end

          output_text = chat_message.content

          # Ensure code block is properly closed
          unless @use_structured_outputs_internally
            if output_text && !output_text.strip.end_with?(@code_block_tags[1])
              output_text += @code_block_tags[1]
              chat_message.content = output_text
            end
          end

          memory_step.model_output_message = chat_message
          memory_step.token_usage = chat_message.token_usage
          memory_step.model_output = output_text
        rescue StandardError => e
          raise AgentGenerationError.new("Error in generating model output:\n#{e}", @logger)
        end

        # Parse code from output
        begin
          code_action = if @use_structured_outputs_internally
                          require "json"
                          parsed = JSON.parse(output_text)
                          extract_code_from_text(parsed["code"], @code_block_tags) || parsed["code"]
                        else
                          parse_code_blobs(output_text, @code_block_tags)
                        end

          code_action = fix_final_answer_code(code_action)
          memory_step.code_action = code_action
        rescue StandardError => e
          raise AgentParsingError.new(
            "Error in code parsing:\n#{e}\nMake sure to provide correct code blocks.",
            @logger
          )
        end

        tool_call = ToolCall.new(
          name: "ruby_interpreter",
          arguments: code_action,
          id: "call_#{@memory.steps.length}"
        )
        yielder << tool_call
        memory_step.tool_calls = [tool_call]

        # Execute code
        @logger.log("Executing parsed code:\n#{code_action}", level: LogLevel::INFO)

        begin
          code_output = @ruby_executor.call(code_action)
          observation = "Execution logs:\n#{code_output.logs}"
        rescue StandardError => e
          error_msg = e.message
          if error_msg.include?("require") && error_msg.include?("not allowed")
            @logger.log(
              "Warning: Code execution failed due to unauthorized require - " \
              "Consider adding to `additional_authorized_imports`.",
              level: LogLevel::INFO
            )
          end
          raise AgentExecutionError.new(error_msg, @logger)
        end

        truncated_output = truncate_content(code_output.output.to_s)
        observation += "\nLast output from code snippet:\n#{truncated_output}"
        memory_step.observations = observation

        unless code_output.is_final_answer
          @logger.log("Out: #{truncated_output}", level: LogLevel::INFO)
        end

        memory_step.action_output = code_output.output
        yielder << ActionOutput.new(output: code_output.output, is_final_answer: code_output.is_final_answer)
      end
    end

    # Convert agent to hash representation
    # @return [Hash]
    def to_h
      agent_dict = super
      agent_dict[:authorized_imports] = @authorized_imports
      agent_dict[:executor_type] = @executor_type
      agent_dict[:executor_kwargs] = @executor_kwargs
      agent_dict[:max_print_outputs_length] = @max_print_outputs_length
      agent_dict
    end

    # Clean up resources
    def cleanup
      @ruby_executor.cleanup if @ruby_executor.respond_to?(:cleanup)
    end

    private

    def default_code_agent_prompts
      PromptTemplates.new(
        system_prompt: <<~PROMPT,
          You are a helpful assistant that solves tasks by writing and executing Ruby code.

          Available tools (call them as methods):
          {{tools}}

          You can use these imports: {{authorized_imports}}

          Write your code between {{code_block_opening_tag}} and {{code_block_closing_tag}} tags.

          To provide a final answer, call: final_answer(your_result)

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

    def create_ruby_executor
      case @executor_type
      when "local"
        LocalRubyExecutor.new(
          @additional_authorized_imports,
          max_print_outputs_length: @max_print_outputs_length,
          **@executor_kwargs
        )
      else
        raise ArgumentError, "Unsupported executor type: #{@executor_type}. Only 'local' is currently supported."
      end
    end

    def stream_model_output(input_messages, stop_sequences, yielder)
      deltas = []
      @model.generate_stream(input_messages, stop_sequences: stop_sequences).each do |event|
        deltas << event
        yielder << event
      end
      agglomerate_stream_deltas(deltas)
    end

    def generate_model_output(input_messages, stop_sequences)
      @model.generate(input_messages, stop_sequences: stop_sequences)
    end

    def parse_code_blobs(text, tags)
      opening_tag, closing_tag = tags

      # Find code between tags
      if text.include?(opening_tag)
        start_idx = text.index(opening_tag) + opening_tag.length
        end_idx = text.rindex(closing_tag) || text.length
        text[start_idx...end_idx].strip
      else
        # Try to find code blocks with regex
        match = text.match(/#{Regexp.escape(opening_tag)}(.*?)#{Regexp.escape(closing_tag)}/m)
        match ? match[1].strip : text.strip
      end
    end

    def extract_code_from_text(text, tags)
      return nil if text.nil?

      parse_code_blobs(text, tags)
    rescue StandardError
      nil
    end

    def fix_final_answer_code(code)
      # Ensure final_answer is properly called
      code
    end

    def truncate_content(content, max_length: 1000)
      return content if content.length <= max_length

      "#{content[0, max_length]}... (truncated)"
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
      content = ""
      token_usage = nil

      deltas.each do |delta|
        content += delta.content.to_s if delta.respond_to?(:content) && delta.content
        token_usage = delta.token_usage if delta.respond_to?(:token_usage) && delta.token_usage
      end

      ChatMessage.new(
        role: MessageRole::ASSISTANT,
        content: content.empty? ? nil : content,
        token_usage: token_usage
      )
    end
  end

  # Simple local Ruby executor for CodeAgent
  class LocalRubyExecutor
    # Result of code execution
    CodeOutput = Struct.new(:output, :logs, :is_final_answer, keyword_init: true)

    # @return [Array<String>] Authorized imports
    attr_reader :authorized_imports

    # @return [Integer, nil] Max print output length
    attr_reader :max_print_outputs_length

    # @return [Hash] Execution state
    attr_reader :state

    # @return [Hash<String, Tool>] Available tools
    attr_reader :tools

    def initialize(additional_imports = [], max_print_outputs_length: nil, **kwargs)
      @authorized_imports = CodeAgent::BASE_BUILTIN_MODULES + additional_imports
      @max_print_outputs_length = max_print_outputs_length
      @state = {}
      @tools = {}
      @print_outputs = []
    end

    # Send variables to the executor
    # @param variables [Hash] Variables to make available
    def send_variables(variables:)
      @state.merge!(variables)
    end

    # Send tools to the executor
    # @param tools [Hash<String, Tool>] Tools to make available
    def send_tools(tools)
      @tools = tools
    end

    # Execute Ruby code
    # @param code [String] The code to execute
    # @return [CodeOutput] Execution result
    def call(code)
      @print_outputs = []
      final_answer_value = nil
      is_final = false

      # Create a binding with tools and state
      sandbox = create_sandbox

      begin
        # Capture output
        output = nil
        logs = capture_output do
          output = sandbox.eval(code)
        end

        # Check for final_answer
        if sandbox.local_variables.include?(:_final_answer_result)
          final_answer_value = sandbox.local_variable_get(:_final_answer_result)
          is_final = true
        end

        CodeOutput.new(
          output: is_final ? final_answer_value : output,
          logs: logs,
          is_final_answer: is_final
        )
      rescue StandardError => e
        CodeOutput.new(
          output: nil,
          logs: "Error: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}",
          is_final_answer: false
        )
      end
    end

    # Clean up resources
    def cleanup
      @state.clear
      @tools.clear
    end

    private

    def create_sandbox
      sandbox = binding

      # Add final_answer method
      final_answer_proc = proc do |value|
        sandbox.local_variable_set(:_final_answer_result, value)
        value
      end
      sandbox.local_variable_set(:final_answer, final_answer_proc)

      # Add tools as callable methods
      @tools.each do |name, tool|
        tool_proc = proc { |**args| tool.call(**args) }
        sandbox.local_variable_set(name.to_sym, tool_proc)
      end

      # Add state variables
      @state.each do |key, value|
        sandbox.local_variable_set(key.to_sym, value) if key.to_s.match?(/\A[a-z_][a-zA-Z0-9_]*\z/)
      end

      sandbox
    end

    def capture_output
      old_stdout = $stdout
      $stdout = StringIO.new
      yield
      output = $stdout.string
      output = output[0, @max_print_outputs_length] if @max_print_outputs_length && output.length > @max_print_outputs_length
      output
    ensure
      $stdout = old_stdout
    end
  end
end
