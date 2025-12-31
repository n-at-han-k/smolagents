# frozen_string_literal: true

require_relative "memory_step"

module Smolagents
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
end
