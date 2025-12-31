# frozen_string_literal: true

module Smolagents
  # Represents the output from a tool execution.
  #
  # @attr id [String] The tool call ID
  # @attr output [Object] The output of the tool
  # @attr is_final_answer [Boolean] Whether this is the final answer
  # @attr observation [String] The observation/result description
  # @attr tool_call [ToolCall] The original tool call
  class ToolOutput
    # @return [String] The tool call ID
    attr_accessor :id

    # @return [Object] The output of the tool
    attr_accessor :output

    # @return [Boolean] Whether this is the final answer
    attr_accessor :is_final_answer

    # @return [String] The observation/result description
    attr_accessor :observation

    # @return [ToolCall] The original tool call
    attr_accessor :tool_call

    # Create a new ToolOutput
    #
    # @param id [String] The tool call ID
    # @param output [Object] The output of the tool
    # @param is_final_answer [Boolean] Whether this is the final answer
    # @param observation [String] The observation/result description
    # @param tool_call [ToolCall] The original tool call
    def initialize(id:, output:, is_final_answer:, observation:, tool_call:)
      @id = id
      @output = output
      @is_final_answer = is_final_answer
      @observation = observation
      @tool_call = tool_call
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
        id: @id,
        output: @output,
        is_final_answer: @is_final_answer,
        observation: @observation,
        tool_call: @tool_call&.to_h
      }
    end
  end
end
