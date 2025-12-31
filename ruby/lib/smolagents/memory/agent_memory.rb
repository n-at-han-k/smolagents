# frozen_string_literal: true

require_relative "system_prompt_step"
require_relative "task_step"
require_relative "action_step"
require_relative "planning_step"

module Smolagents
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
end
