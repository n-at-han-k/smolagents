# frozen_string_literal: true

# Copyright 2024 HuggingFace Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "json"
require "logger"

module Smolagents
  # Represents a single tool call with its name, arguments, and ID
  class ToolCall
    attr_accessor :name, :arguments, :id

    # @param name [String] Tool name
    # @param arguments [Object] Tool arguments
    # @param id [String] Unique identifier
    def initialize(name:, arguments:, id:)
      @name = name
      @arguments = arguments
      @id = id
    end

    # Convert to hash representation
    # @return [Hash]
    def to_h
      {
        id: @id,
        type: "function",
        function: {
          name: @name,
          arguments: Utils.make_json_serializable(@arguments)
        }
      }
    end

    alias to_hash to_h

    def to_s
      "ToolCall(#{@name}, id=#{@id})"
    end
  end

  # Abstract base class for memory steps
  #
  # @abstract Subclass and implement {#to_messages}
  class MemoryStep
    # Convert to hash representation
    # @return [Hash]
    def to_h
      instance_variables.each_with_object({}) do |var, hash|
        key = var.to_s.delete("@").to_sym
        value = instance_variable_get(var)
        hash[key] = value.respond_to?(:to_h) ? value.to_h : value
      end
    end

    alias to_hash to_h

    # Convert step to chat messages
    # @param summary_mode [Boolean] Whether to use summary mode
    # @return [Array<ChatMessage>]
    def to_messages(summary_mode: false)
      raise NotImplementedError, "Subclasses must implement #to_messages"
    end
  end

  # Represents an action step in the agent's execution
  class ActionStep < MemoryStep
    attr_accessor :step_number, :timing, :model_input_messages, :tool_calls,
                  :error, :model_output_message, :model_output, :code_action,
                  :observations, :observations_images, :action_output,
                  :token_usage, :is_final_answer

    # @param step_number [Integer] Step number in the execution
    # @param timing [Timing] Timing information
    # @param model_input_messages [Array<ChatMessage>, nil] Input messages to the model
    # @param tool_calls [Array<ToolCall>, nil] Tool calls made
    # @param error [AgentError, nil] Error if any occurred
    # @param model_output_message [ChatMessage, nil] Output message from model
    # @param model_output [String, Array<Hash>, nil] Raw model output
    # @param code_action [String, nil] Code that was executed
    # @param observations [String, nil] Observations from execution
    # @param observations_images [Array, nil] Images from observations
    # @param action_output [Object, nil] Output from the action
    # @param token_usage [TokenUsage, nil] Token usage for this step
    # @param is_final_answer [Boolean] Whether this is the final answer
    def initialize(
      step_number:,
      timing:,
      model_input_messages: nil,
      tool_calls: nil,
      error: nil,
      model_output_message: nil,
      model_output: nil,
      code_action: nil,
      observations: nil,
      observations_images: nil,
      action_output: nil,
      token_usage: nil,
      is_final_answer: false
    )
      @step_number = step_number
      @timing = timing
      @model_input_messages = model_input_messages
      @tool_calls = tool_calls
      @error = error
      @model_output_message = model_output_message
      @model_output = model_output
      @code_action = code_action
      @observations = observations
      @observations_images = observations_images
      @action_output = action_output
      @token_usage = token_usage
      @is_final_answer = is_final_answer
    end

    # Convert to hash representation
    # @return [Hash]
    def to_h
      {
        step_number: @step_number,
        timing: @timing.to_h,
        model_input_messages: @model_input_messages&.map { |m| Utils.make_json_serializable(Smolagents.get_dict_from_nested_dataclasses(m)) },
        tool_calls: @tool_calls&.map(&:to_h) || [],
        error: @error&.to_h,
        model_output_message: @model_output_message ? Utils.make_json_serializable(Smolagents.get_dict_from_nested_dataclasses(@model_output_message)) : nil,
        model_output: @model_output,
        code_action: @code_action,
        observations: @observations,
        observations_images: @observations_images&.map(&:to_s),
        action_output: Utils.make_json_serializable(@action_output),
        token_usage: @token_usage&.to_h,
        is_final_answer: @is_final_answer
      }
    end

    # Convert step to chat messages
    # @param summary_mode [Boolean] Whether to use summary mode
    # @return [Array<ChatMessage>]
    def to_messages(summary_mode: false)
      messages = []

      if @model_output && !summary_mode
        messages << ChatMessage.new(
          role: MessageRole::ASSISTANT,
          content: [{ type: "text", text: @model_output.to_s.strip }]
        )
      end

      if @tool_calls
        messages << ChatMessage.new(
          role: MessageRole::TOOL_CALL,
          content: [
            {
              type: "text",
              text: "Calling tools:\n#{@tool_calls.map(&:to_h)}"
            }
          ]
        )
      end

      if @observations_images&.any?
        messages << ChatMessage.new(
          role: MessageRole::USER,
          content: @observations_images.map { |image| { type: "image", image: image } }
        )
      end

      if @observations
        messages << ChatMessage.new(
          role: MessageRole::TOOL_RESPONSE,
          content: [{ type: "text", text: "Observation:\n#{@observations}" }]
        )
      end

      if @error
        error_message = "Error:\n#{@error}\n" \
                        "Now let's retry: take care not to repeat previous errors! " \
                        "If you have retried several times, try a completely different approach.\n"
        message_content = @tool_calls&.first ? "Call id: #{@tool_calls.first.id}\n" : ""
        message_content += error_message

        messages << ChatMessage.new(
          role: MessageRole::TOOL_RESPONSE,
          content: [{ type: "text", text: message_content }]
        )
      end

      messages
    end
  end

  # Represents a planning step in the agent's execution
  class PlanningStep < MemoryStep
    attr_accessor :model_input_messages, :model_output_message, :plan, :timing, :token_usage

    # @param model_input_messages [Array<ChatMessage>] Input messages
    # @param model_output_message [ChatMessage] Output message
    # @param plan [String] The plan content
    # @param timing [Timing] Timing information
    # @param token_usage [TokenUsage, nil] Token usage
    def initialize(model_input_messages:, model_output_message:, plan:, timing:, token_usage: nil)
      @model_input_messages = model_input_messages
      @model_output_message = model_output_message
      @plan = plan
      @timing = timing
      @token_usage = token_usage
    end

    # Convert to hash representation
    # @return [Hash]
    def to_h
      {
        model_input_messages: @model_input_messages.map { |m| Utils.make_json_serializable(Smolagents.get_dict_from_nested_dataclasses(m)) },
        model_output_message: Utils.make_json_serializable(Smolagents.get_dict_from_nested_dataclasses(@model_output_message)),
        plan: @plan,
        timing: @timing.to_h,
        token_usage: @token_usage&.to_h
      }
    end

    # Convert step to chat messages
    # @param summary_mode [Boolean] Whether to use summary mode
    # @return [Array<ChatMessage>]
    def to_messages(summary_mode: false)
      return [] if summary_mode

      [
        ChatMessage.new(
          role: MessageRole::ASSISTANT,
          content: [{ type: "text", text: @plan.strip }]
        ),
        ChatMessage.new(
          role: MessageRole::USER,
          content: [{ type: "text", text: "Now proceed and carry out this plan." }]
        )
      ]
    end
  end

  # Represents a task step (new task assignment)
  class TaskStep < MemoryStep
    attr_accessor :task, :task_images

    # @param task [String] The task description
    # @param task_images [Array, nil] Images associated with the task
    def initialize(task:, task_images: nil)
      @task = task
      @task_images = task_images
    end

    # Convert step to chat messages
    # @param summary_mode [Boolean] Whether to use summary mode
    # @return [Array<ChatMessage>]
    def to_messages(summary_mode: false)
      content = [{ type: "text", text: "New task:\n#{@task}" }]

      if @task_images&.any?
        @task_images.each do |image|
          content << { type: "image", image: image }
        end
      end

      [ChatMessage.new(role: MessageRole::USER, content: content)]
    end
  end

  # Represents the system prompt step
  class SystemPromptStep < MemoryStep
    attr_accessor :system_prompt

    # @param system_prompt [String] The system prompt
    def initialize(system_prompt:)
      @system_prompt = system_prompt
    end

    # Convert step to chat messages
    # @param summary_mode [Boolean] Whether to use summary mode
    # @return [Array<ChatMessage>]
    def to_messages(summary_mode: false)
      return [] if summary_mode

      [ChatMessage.new(role: MessageRole::SYSTEM, content: [{ type: "text", text: @system_prompt }])]
    end
  end

  # Represents the final answer step
  class FinalAnswerStep < MemoryStep
    attr_accessor :output

    # @param output [Object] The final output
    def initialize(output:)
      @output = output
    end

    # Convert step to chat messages
    # @param summary_mode [Boolean] Whether to use summary mode
    # @return [Array<ChatMessage>]
    def to_messages(summary_mode: false)
      []
    end
  end

  # Memory for the agent, containing the system prompt and all steps taken
  #
  # This class stores the agent's steps, including tasks, actions, and planning steps.
  # It allows for resetting the memory, retrieving step information, and replaying execution.
  #
  # @example
  #   memory = AgentMemory.new(system_prompt: "You are a helpful assistant.")
  #   memory.steps << TaskStep.new(task: "Help me with coding")
  #   memory.steps << ActionStep.new(step_number: 1, timing: Timing.start_now)
  class AgentMemory
    attr_accessor :system_prompt, :steps

    # @param system_prompt [String] System prompt for the agent
    def initialize(system_prompt:)
      @system_prompt = SystemPromptStep.new(system_prompt: system_prompt)
      @steps = []
    end

    # Reset the agent's memory, clearing all steps
    # @return [void]
    def reset
      @steps = []
    end

    # Return a succinct representation of steps (excluding model input messages)
    # @return [Array<Hash>]
    def succinct_steps
      @steps.map do |step|
        step.to_h.reject { |k, _| k == :model_input_messages }
      end
    end

    # Return full representation of all steps
    # @return [Array<Hash>]
    def full_steps
      return [] if @steps.empty?

      @steps.map(&:to_h)
    end

    # Print a pretty replay of the agent's steps
    #
    # @param logger [AgentLogger] Logger to print replay logs to
    # @param detailed [Boolean] If true, also displays memory at each step
    # @return [void]
    def replay(logger:, detailed: false)
      logger.console.puts("Replaying the agent's steps:")
      logger.log_markdown(title: "System prompt", content: @system_prompt.system_prompt, level: LogLevel::ERROR)

      @steps.each do |step|
        case step
        when TaskStep
          logger.log_task(content: step.task, subtitle: "", level: LogLevel::ERROR)
        when ActionStep
          logger.log_rule("Step #{step.step_number}", level: LogLevel::ERROR)
          if detailed && step.model_input_messages
            logger.log_messages(step.model_input_messages, level: LogLevel::ERROR)
          end
          if step.model_output
            logger.log_markdown(title: "Agent output:", content: step.model_output.to_s, level: LogLevel::ERROR)
          end
        when PlanningStep
          logger.log_rule("Planning step", level: LogLevel::ERROR)
          if detailed && step.model_input_messages
            logger.log_messages(step.model_input_messages, level: LogLevel::ERROR)
          end
          logger.log_markdown(title: "Agent output:", content: step.plan, level: LogLevel::ERROR)
        end
      end
    end

    # Returns all code actions from the agent's steps as a single script
    # @return [String]
    def full_code
      @steps
        .select { |step| step.is_a?(ActionStep) && step.code_action }
        .map(&:code_action)
        .join("\n\n")
    end
  end

  # Registry for callbacks that are called at each step of the agent's execution
  #
  # Callbacks are registered by passing a step class and a callback function.
  #
  # @example
  #   registry = CallbackRegistry.new
  #   registry.register(ActionStep) { |step| puts "Action: #{step.step_number}" }
  class CallbackRegistry
    def initialize
      @callbacks = {}
    end

    # Register a callback for a step class
    #
    # @param step_class [Class] Step class to register the callback for
    # @param callback [Proc] Callback to register
    # @yield [MemoryStep] Block to use as callback
    # @return [void]
    def register(step_class, callback = nil, &block)
      callback ||= block
      raise ArgumentError, "Callback required" unless callback

      @callbacks[step_class] ||= []
      @callbacks[step_class] << callback
    end

    # Call callbacks registered for a step type
    #
    # @param memory_step [MemoryStep] Step to call callbacks for
    # @param kwargs [Hash] Additional arguments to pass to callbacks
    # @return [void]
    def callback(memory_step, **kwargs)
      # Walk up the class hierarchy to find registered callbacks
      memory_step.class.ancestors.each do |ancestor_class|
        @callbacks[ancestor_class]&.each do |cb|
          if cb.arity == 1 || cb.parameters.count { |type, _| %i[req opt].include?(type) } == 1
            cb.call(memory_step)
          else
            cb.call(memory_step, **kwargs)
          end
        end
      end
    end

    # Check if any callbacks are registered
    # @return [Boolean]
    def empty?
      @callbacks.empty? || @callbacks.values.all?(&:empty?)
    end

    # Get the number of registered callbacks
    # @return [Integer]
    def size
      @callbacks.values.sum(&:size)
    end
  end
end
