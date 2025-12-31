# frozen_string_literal: true

module Smolagents
  # Contains token usage information for a given step or run
  #
  # @attr_reader input_tokens [Integer] Number of input tokens
  # @attr_reader output_tokens [Integer] Number of output tokens
  # @attr_reader total_tokens [Integer] Total number of tokens (computed)
  class TokenUsage
    attr_reader :input_tokens, :output_tokens, :total_tokens

    # @param input_tokens [Integer] Number of input tokens
    # @param output_tokens [Integer] Number of output tokens
    def initialize(input_tokens:, output_tokens:)
      @input_tokens = input_tokens
      @output_tokens = output_tokens
      @total_tokens = input_tokens + output_tokens
    end

    # Convert to hash representation
    # @return [Hash] Hash with token counts
    def to_h
      {
        input_tokens: @input_tokens,
        output_tokens: @output_tokens,
        total_tokens: @total_tokens
      }
    end

    alias to_hash to_h

    # Add token usage from another instance
    # @param other [TokenUsage] Other token usage to add
    # @return [TokenUsage] New combined token usage
    def +(other)
      TokenUsage.new(
        input_tokens: @input_tokens + other.input_tokens,
        output_tokens: @output_tokens + other.output_tokens
      )
    end

    def to_s
      "TokenUsage(input: #{@input_tokens}, output: #{@output_tokens}, total: #{@total_tokens})"
    end

    def inspect
      "#<#{self.class} #{to_s}>"
    end
  end
end
