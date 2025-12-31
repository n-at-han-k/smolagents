# frozen_string_literal: true

module Smolagents
  # Represents the output from an agent action step.
  #
  # @attr output [Object] The output of the action
  # @attr is_final_answer [Boolean] Whether this is the final answer
  class ActionOutput
    # @return [Object] The output of the action
    attr_accessor :output

    # @return [Boolean] Whether this is the final answer
    attr_accessor :is_final_answer

    # Create a new ActionOutput
    #
    # @param output [Object] The output of the action
    # @param is_final_answer [Boolean] Whether this is the final answer
    def initialize(output:, is_final_answer:)
      @output = output
      @is_final_answer = is_final_answer
    end

    # Check if this is a final answer
    # @return [Boolean]
    def final_answer?
      @is_final_answer
    end

    # Convert to hash
    # @return [Hash]
    def to_h
      {
        output: @output,
        is_final_answer: @is_final_answer
      }
    end
  end
end
