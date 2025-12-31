# frozen_string_literal: true

module Smolagents
  # Represents a streaming delta for tool calls
  class ChatMessageToolCallStreamDelta
    attr_accessor :index, :id, :type, :function

    # @param index [Integer, nil] Index in the tool calls array
    # @param id [String, nil] Tool call ID
    # @param type [String, nil] Tool call type
    # @param function [ChatMessageToolCallFunction, nil] Function details
    def initialize(index: nil, id: nil, type: nil, function: nil)
      @index = index
      @id = id
      @type = type
      @function = function
    end
  end
end
