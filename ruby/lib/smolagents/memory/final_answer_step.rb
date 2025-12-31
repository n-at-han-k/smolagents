# frozen_string_literal: true

require_relative "memory_step"

module Smolagents
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
end
