# frozen_string_literal: true

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
end
