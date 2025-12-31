# frozen_string_literal: true

require_relative "chat_message_tool_call_function"

module Smolagents
  # Represents a tool call in a chat message
  class ChatMessageToolCall
    attr_accessor :function, :id, :type

    # @param function [ChatMessageToolCallFunction, Hash] The function being called
    # @param id [String] Unique identifier for the call
    # @param type [String] Type of tool call (default: "function")
    def initialize(function:, id:, type: "function")
      @function = function.is_a?(Hash) ? ChatMessageToolCallFunction.new(**function) : function
      @id = id
      @type = type
    end

    # Convert to hash representation
    # @return [Hash]
    def to_h
      {
        function: @function.to_h,
        id: @id,
        type: @type
      }
    end

    alias to_hash to_h

    def to_s
      "Call: #{@id}: Calling #{@function.name} with arguments: #{@function.arguments}"
    end
  end
end
