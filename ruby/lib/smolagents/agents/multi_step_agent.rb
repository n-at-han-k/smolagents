# frozen_string_literal: true

require "erb"

module Smolagents
  # Abstract base class for multi-step agents that solve tasks using the ReAct framework.
  #
  # The agent performs cycles of action (from the LLM) and observation (from tools)
  # until the objective is reached.
  #
  # @abstract Subclass and implement {#initialize_system_prompt} and {#step_stream}
  class MultiStepAgent
    # @return [String] The agent's name (for managed agents)
    attr_accessor :name

    # @return [String] The agent's description (for managed agents)
    attr_accessor :description

    # @return [Object] The model used for generation
    attr_accessor :model

    # @return [Hash<String, Tool>] Tools available to the agent
    attr_accessor :tools

    # @return [Hash<String, MultiStepAgent>] Managed sub-agents
    attr_accessor :managed_agents

    # @return [PromptTemplates] Prompt templates
    attr_accessor :prompt_templates

    # @return [String, nil] Custom instructions
    attr_accessor :instructions

    # @return [Integer] Maximum number of steps
    attr_accessor :max_steps

    # @return [Integer] Current step number
    attr_accessor :step_number

    # @return [Integer, nil] Planning interval
    attr_accessor :planning_interval

    # @return [AgentMemory] Agent memory
    attr_accessor :memory

    # @return [AgentLogger] Logger
    attr_accessor :logger

    # @return [Monitor] Metrics monitor
    attr_accessor :monitor

    # @return [CallbackRegistry] Step callbacks
    attr_accessor :step_callbacks

    # @return [Hash] Agent state
    attr_accessor :state

    # @return [String, nil] Current task
    attr_accessor :task

    # @return [Boolean] Whether to return full RunResult
    attr_accessor :return_full_result

    # @return [Boolean] Whether agent is interrupted
    attr_accessor :interrupt_switch

    # @return [Boolean] Whether to stream outputs
    attr_accessor :stream_outputs

    # @return [Array<Proc>] Final answer validation checks
    attr_accessor :final_answer_checks

    # @return [Boolean] Whether to provide run summary for managed agents
    attr_accessor :provide_run_summary

    # Create a new MultiStepAgent
    #
    # @param tools [Array<Tool>] Tools the agent can use
    # @param model [Object] Model for generating actions
    # @param prompt_templates [PromptTemplates, nil] Prompt templates
    # @param instructions [String, nil] Custom instructions
    # @param max_steps [Integer] Maximum steps (default: 20)
    # @param add_base_tools [Boolean] Whether to add base tools
    # @param verbosity_level [Integer] Log verbosity level
    # @param managed_agents [Array<MultiStepAgent>, nil] Sub-agents
    # @param step_callbacks [Array<Proc>, Hash, nil] Step callbacks
    # @param planning_interval [Integer, nil] Planning interval
    # @param name [String, nil] Agent name
    # @param description [String, nil] Agent description
    # @param provide_run_summary [Boolean] Provide run summary when managed
    # @param final_answer_checks [Array<Proc>, nil] Answer validation checks
    # @param return_full_result [Boolean] Return RunResult vs just output
    # @param logger [AgentLogger, nil] Custom logger
    def initialize(
      tools:,
      model:,
      prompt_templates: nil,
      instructions: nil,
      max_steps: 20,
      add_base_tools: false,
      verbosity_level: LogLevel::INFO,
      managed_agents: nil,
      step_callbacks: nil,
      planning_interval: nil,
      name: nil,
      description: nil,
      provide_run_summary: false,
      final_answer_checks: nil,
      return_full_result: false,
      logger: nil
    )
      @agent_name = self.class.name
      @model = model
      @prompt_templates = prompt_templates || EMPTY_PROMPT_TEMPLATES
      validate_prompt_templates(@prompt_templates) if prompt_templates

      @max_steps = max_steps
      @step_number = 0
      @planning_interval = planning_interval
      @state = {}
      @name = validate_agent_name(name)
      @description = description
      @provide_run_summary = provide_run_summary
      @final_answer_checks = final_answer_checks || []
      @return_full_result = return_full_result
      @instructions = instructions

      setup_managed_agents(managed_agents)
      setup_tools(tools, add_base_tools)
      validate_tools_and_managed_agents(tools, managed_agents)

      @task = nil
      @memory = AgentMemory.new(system_prompt: system_prompt)

      @logger = logger || AgentLogger.new(level: verbosity_level)
      @monitor = Monitor.new
      setup_step_callbacks(step_callbacks)
      @stream_outputs = false
    end

    # Get the system prompt
    # @return [String]
    def system_prompt
      initialize_system_prompt
    end

    # Initialize the system prompt - must be implemented by subclasses
    # @abstract
    # @return [String]
    def initialize_system_prompt
      raise NotImplementedError, "Subclasses must implement #initialize_system_prompt"
    end

    # Run the agent for the given task
    #
    # @param task [String] Task to perform
    # @param stream [Boolean] Whether to stream outputs
    # @param reset [Boolean] Whether to reset memory
    # @param images [Array, nil] Image objects
    # @param additional_args [Hash, nil] Additional arguments
    # @param max_steps [Integer, nil] Override max steps
    # @param return_full_result [Boolean, nil] Override return_full_result
    # @return [Object, RunResult] Final answer or full result
    def run(task:, stream: false, reset: true, images: nil, additional_args: nil, max_steps: nil, return_full_result: nil)
      max_steps ||= @max_steps
      @task = task
      @interrupt_switch = false

      if additional_args
        @state.merge!(additional_args)
        @task += "\nYou have been provided with these additional arguments, " \
                 "that you can access directly using the keys as variables:\n#{additional_args}"
      end

      @memory.system_prompt = SystemPromptStep.new(system_prompt: system_prompt)
      if reset
        @memory.reset
        @monitor.reset
      end

      @logger.log("Task: #{@task.strip}", level: LogLevel::INFO)
      @memory.steps << TaskStep.new(task: @task, task_images: images)

      if stream
        # Return generator for streaming
        return run_stream(task: @task, max_steps: max_steps, images: images)
      end

      run_start_time = Time.now

      # Collect all steps
      steps = run_stream(task: @task, max_steps: max_steps, images: images).to_a

      # Get output from last step
      final_step = steps.last
      output = final_step.respond_to?(:output) ? final_step.output : nil

      should_return_full = return_full_result.nil? ? @return_full_result : return_full_result
      if should_return_full
        token_usage = calculate_total_token_usage
        state = determine_final_state

        RunResult.new(
          output: output,
          token_usage: token_usage,
          steps: @memory.get_full_steps,
          timing: Timing.new(start_time: run_start_time, end_time: Time.now),
          state: state
        )
      else
        output
      end
    end

    # Interrupt the agent execution
    def interrupt
      @interrupt_switch = true
    end

    # Perform one step (non-streaming)
    # @param memory_step [ActionStep] The memory step to populate
    # @return [Object] The step result
    def step(memory_step)
      step_stream(memory_step).to_a.last
    end

    # Perform one step with streaming - must be implemented by subclasses
    # @abstract
    # @param memory_step [ActionStep] The memory step to populate
    # @return [Enumerator] Stream of step events
    def step_stream(memory_step)
      raise NotImplementedError, "Subclasses must implement #step_stream"
    end

    # Visualize the agent structure
    def visualize
      @logger.visualize_agent_tree(self)
    end

    # Replay agent steps
    # @param detailed [Boolean] Show detailed memory at each step
    def replay(detailed: false)
      @memory.replay(logger: @logger, detailed: detailed)
    end

    # Write memory to messages for LLM input
    # @param summary_mode [Boolean] Whether to use summary mode
    # @return [Array<ChatMessage>]
    def write_memory_to_messages(summary_mode: false)
      messages = @memory.system_prompt.to_messages(summary_mode: summary_mode)
      @memory.steps.each do |memory_step|
        messages.concat(memory_step.to_messages(summary_mode: summary_mode))
      end
      messages
    end

    # Extract action from model output
    # @param model_output [String] The model's output
    # @param split_token [String] The separator token
    # @return [Array<String>] [rationale, action]
    def extract_action(model_output, split_token)
      parts = model_output.split(split_token)
      if parts.length < 2
        raise AgentParsingError.new(
          "No '#{split_token}' token provided in your output.\n" \
          "Your output:\n#{model_output}\n" \
          "Be sure to include an action, prefaced with '#{split_token}'!",
          @logger
        )
      end
      [parts[-2].strip, parts[-1].strip]
    end

    # Provide final answer when max steps reached
    # @param task [String] The task
    # @return [ChatMessage]
    def provide_final_answer(task)
      messages = [
        ChatMessage.new(
          role: MessageRole::SYSTEM,
          content: [{ type: "text", text: @prompt_templates[:final_answer].pre_messages }]
        )
      ]
      messages.concat(write_memory_to_messages[1..])
      messages << ChatMessage.new(
        role: MessageRole::USER,
        content: [{
          type: "text",
          text: populate_template(@prompt_templates[:final_answer].post_messages, task: task)
        }]
      )

      begin
        @model.generate(messages)
      rescue StandardError => e
        ChatMessage.new(
          role: MessageRole::ASSISTANT,
          content: [{ type: "text", text: "Error in generating final LLM output: #{e}" }]
        )
      end
    end

    # Call the agent (for managed agent usage)
    # @param task [String] The task
    # @param kwargs [Hash] Additional arguments
    # @return [String]
    def call(task, **kwargs)
      full_task = populate_template(
        @prompt_templates[:managed_agent].task,
        name: @name,
        task: task
      )
      result = run(task: full_task, **kwargs)
      report = result.is_a?(RunResult) ? result.output : result

      answer = populate_template(
        @prompt_templates[:managed_agent].report,
        name: @name,
        final_answer: report
      )

      if @provide_run_summary
        answer += "\n\nFor more detail, find below a summary of this agent's work:\n<summary_of_work>\n"
        write_memory_to_messages(summary_mode: true).each do |message|
          answer += "\n#{truncate_content(message.content.to_s)}\n---"
        end
        answer += "\n</summary_of_work>"
      end

      answer
    end

    # Convert agent to hash representation
    # @return [Hash]
    def to_h
      tool_dicts = @tools.values.map(&:to_h)
      tool_requirements = @tools.values.flat_map { |t| t.to_h[:requirements] || [] }.to_set
      managed_agent_requirements = @managed_agents.values.flat_map { |a| a.to_h[:requirements] || [] }.to_set
      requirements = (tool_requirements | managed_agent_requirements).to_a.sort

      {
        class: self.class.name.split("::").last,
        tools: tool_dicts,
        model: {
          class: @model.class.name.split("::").last,
          data: @model.respond_to?(:to_h) ? @model.to_h : {}
        },
        managed_agents: @managed_agents.values.map(&:to_h),
        prompt_templates: @prompt_templates.to_h,
        max_steps: @max_steps,
        verbosity_level: @logger.level,
        planning_interval: @planning_interval,
        name: @name,
        description: @description,
        requirements: requirements
      }
    end

    alias to_hash to_h

    private

    def validate_agent_name(name)
      return nil if name.nil?

      unless valid_name?(name)
        raise ArgumentError, "Agent name '#{name}' must be a valid identifier and not a reserved keyword."
      end

      name
    end

    def valid_name?(name)
      return false if name.nil? || name.empty?
      return false unless name.match?(/\A[a-z_][a-zA-Z0-9_]*\z/)

      reserved = %w[
        BEGIN END alias and begin break case class def defined? do else elsif end
        ensure false for if in module next nil not or redo rescue retry return self
        super then true undef unless until when while yield
      ]
      !reserved.include?(name)
    end

    def validate_prompt_templates(templates)
      required_keys = %i[system_prompt planning managed_agent final_answer]
      missing = required_keys - templates.keys
      unless missing.empty?
        raise ArgumentError, "Missing prompt templates: #{missing.join(', ')}"
      end
    end

    def setup_managed_agents(managed_agents)
      @managed_agents = {}
      return unless managed_agents

      managed_agents.each do |agent|
        unless agent.name && agent.description
          raise ArgumentError, "All managed agents need both a name and a description!"
        end
        @managed_agents[agent.name] = agent
        # Set inputs and output_type for tool-like behavior
        agent.define_singleton_method(:inputs) do
          {
            task: { type: "string", description: "Long detailed description of the task." },
            additional_args: {
              type: "object",
              description: "Dictionary of extra inputs to pass to the managed agent.",
              nullable: true
            }
          }
        end
        agent.define_singleton_method(:output_type) { "string" }
      end
    end

    def setup_tools(tools, add_base_tools)
      tools.each do |tool|
        unless tool.is_a?(BaseTool)
          raise ArgumentError, "All elements must be instances of BaseTool (or a subclass)"
        end
      end

      @tools = tools.each_with_object({}) { |tool, h| h[tool.name] = tool }

      if add_base_tools
        # Add default tools if available
        if defined?(TOOL_MAPPING)
          TOOL_MAPPING.each do |name, klass|
            next if name == "python_interpreter" && self.class.name != "ToolCallingAgent"
            @tools[name] ||= klass.new
          end
        end
      end

      # Always ensure final_answer tool exists
      @tools["final_answer"] ||= FinalAnswerTool.new if defined?(FinalAnswerTool)
    end

    def validate_tools_and_managed_agents(tools, managed_agents)
      names = tools.map(&:name)
      names += managed_agents.map(&:name) if managed_agents
      names << @name if @name

      duplicates = names.select { |n| names.count(n) > 1 }.uniq
      unless duplicates.empty?
        raise ArgumentError, "Each tool or managed_agent should have a unique name! Duplicates: #{duplicates}"
      end
    end

    def setup_step_callbacks(step_callbacks)
      @step_callbacks = CallbackRegistry.new

      case step_callbacks
      when Array
        step_callbacks.each { |cb| @step_callbacks.register(ActionStep, cb) }
      when Hash
        step_callbacks.each do |step_cls, callbacks|
          Array(callbacks).each { |cb| @step_callbacks.register(step_cls, cb) }
        end
      when nil
        # No callbacks
      else
        raise ArgumentError, "step_callbacks must be an Array or Hash"
      end

      # Register monitor update
      @step_callbacks.register(ActionStep, ->(step, **_) { @monitor.update_metrics(step) })
    end

    def run_stream(task:, max_steps:, images: nil)
      Enumerator.new do |yielder|
        @step_number = 1
        returned_final_answer = false
        final_answer = nil

        while !returned_final_answer && @step_number <= max_steps
          raise AgentError.new("Agent interrupted.", @logger) if @interrupt_switch

          # Run planning step if scheduled
          if @planning_interval && (@step_number == 1 || (@step_number - 1) % @planning_interval == 0)
            planning_start = Time.now
            planning_step = nil

            generate_planning_step(task, is_first_step: @memory.steps.length == 1, step: @step_number).each do |element|
              yielder << element
              planning_step = element
            end

            if planning_step.is_a?(PlanningStep)
              planning_step.timing = Timing.new(start_time: planning_start, end_time: Time.now)
              finalize_step(planning_step)
              @memory.steps << planning_step
            end
          end

          # Action step
          action_start = Time.now
          action_step = ActionStep.new(
            step_number: @step_number,
            timing: Timing.new(start_time: action_start),
            observations_images: images
          )

          @logger.log("Step #{@step_number}", level: LogLevel::INFO)

          begin
            step_stream(action_step).each do |output|
              yielder << output

              if output.is_a?(ActionOutput) && output.final_answer?
                final_answer = output.output
                @logger.log("Final answer: #{final_answer}", level: LogLevel::INFO)

                validate_final_answer(final_answer) if @final_answer_checks.any?
                returned_final_answer = true
                action_step.is_final_answer = true
              end
            end
          rescue AgentGenerationError
            raise
          rescue AgentError => e
            action_step.error = e
          ensure
            finalize_step(action_step)
            @memory.steps << action_step
            yielder << action_step
            @step_number += 1
          end
        end

        # Handle max steps reached
        if !returned_final_answer && @step_number == max_steps + 1
          final_answer = handle_max_steps_reached(task)
        end

        final_answer_step = FinalAnswerStep.new(output: handle_agent_output_types(final_answer))
        finalize_step(final_answer_step)
        yielder << final_answer_step
      end
    end

    def generate_planning_step(task, is_first_step:, step:)
      Enumerator.new do |yielder|
        start_time = Time.now

        if is_first_step
          input_messages = [
            ChatMessage.new(
              role: MessageRole::USER,
              content: [{
                type: "text",
                text: populate_template(
                  @prompt_templates[:planning].initial_plan,
                  task: task,
                  tools: @tools,
                  managed_agents: @managed_agents
                )
              }]
            )
          ]

          plan_message = @model.generate(input_messages, stop_sequences: ["<end_plan>"])
          plan_content = plan_message.content
          token_usage = plan_message.token_usage

          plan = "Here are the facts I know and the plan of action that I will follow:\n```\n#{plan_content}\n```"
        else
          memory_messages = write_memory_to_messages(summary_mode: true)
          plan_update_pre = ChatMessage.new(
            role: MessageRole::SYSTEM,
            content: [{
              type: "text",
              text: populate_template(@prompt_templates[:planning].update_plan_pre_messages, task: task)
            }]
          )
          plan_update_post = ChatMessage.new(
            role: MessageRole::USER,
            content: [{
              type: "text",
              text: populate_template(
                @prompt_templates[:planning].update_plan_post_messages,
                task: task,
                tools: @tools,
                managed_agents: @managed_agents,
                remaining_steps: @max_steps - step
              )
            }]
          )

          input_messages = [plan_update_pre] + memory_messages + [plan_update_post]
          plan_message = @model.generate(input_messages, stop_sequences: ["<end_plan>"])
          plan_content = plan_message.content
          token_usage = plan_message.token_usage

          plan = "I still need to solve the task:\n```\n#{@task}\n```\n\n" \
                 "Here are my updated facts and plan:\n```\n#{plan_content}\n```"
        end

        log_headline = is_first_step ? "Initial plan" : "Updated plan"
        @logger.log("#{log_headline}: #{plan}", level: LogLevel::INFO)

        yielder << PlanningStep.new(
          model_input_messages: input_messages,
          plan: plan,
          model_output_message: ChatMessage.new(role: MessageRole::ASSISTANT, content: plan_content),
          token_usage: token_usage,
          timing: Timing.new(start_time: start_time, end_time: Time.now)
        )
      end
    end

    def validate_final_answer(final_answer)
      @final_answer_checks.each do |check_function|
        result = check_function.call(final_answer, @memory, agent: self)
        unless result
          raise AgentError.new("Final answer check failed", @logger)
        end
      rescue StandardError => e
        raise AgentError.new("Check failed with error: #{e}", @logger)
      end
    end

    def finalize_step(memory_step)
      memory_step.timing.end_time = Time.now unless memory_step.is_a?(FinalAnswerStep)
      @step_callbacks.callback(memory_step, agent: self)
    end

    def handle_max_steps_reached(task)
      action_start = Time.now
      final_answer = provide_final_answer(task)
      final_step = ActionStep.new(
        step_number: @step_number,
        error: AgentMaxStepsError.new("Reached max steps.", @logger),
        timing: Timing.new(start_time: action_start, end_time: Time.now),
        token_usage: final_answer.token_usage
      )
      final_step.action_output = final_answer.content
      finalize_step(final_step)
      @memory.steps << final_step
      final_answer.content
    end

    def calculate_total_token_usage
      total_input = 0
      total_output = 0
      valid = true

      @memory.steps.each do |step|
        next unless step.is_a?(ActionStep) || step.is_a?(PlanningStep)

        if step.token_usage.nil?
          valid = false
          break
        end
        total_input += step.token_usage.input_tokens
        total_output += step.token_usage.output_tokens
      end

      valid ? TokenUsage.new(input_tokens: total_input, output_tokens: total_output) : nil
    end

    def determine_final_state
      if @memory.steps.any? && @memory.steps.last.respond_to?(:error) &&
         @memory.steps.last.error.is_a?(AgentMaxStepsError)
        "max_steps_error"
      else
        "success"
      end
    end

    def populate_template(template, **variables)
      return template if template.nil? || template.empty?

      # Simple variable substitution using ERB-style or mustache-style
      result = template.dup
      variables.each do |key, value|
        result.gsub!(/\{\{\s*#{key}\s*\}\}/, value.to_s)
        result.gsub!(/\{%\s*#{key}\s*%\}/, value.to_s)
        result.gsub!(/<%= #{key} %>/, value.to_s)
      end
      result
    end

    def truncate_content(content, max_length: 1000)
      return content if content.length <= max_length

      "#{content[0, max_length]}... (truncated)"
    end

    def handle_agent_output_types(output)
      # Convert output to appropriate AgentType if needed
      output
    end
  end
end
