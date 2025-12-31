# frozen_string_literal: true

require_relative "memory_step"

module Smolagents
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
end
