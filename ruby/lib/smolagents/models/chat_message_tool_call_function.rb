# frozen_string_literal: true

module Smolagents
  # Function information for a tool call
  class ChatMessageToolCallFunction
    attr_accessor :name, :arguments, :description

    # @param name [String] Function name
    # @param arguments [Object] Function arguments
    # @param description [String, nil] Optional description
    def initialize(name:, arguments:, description: nil)
      @name = name
      @arguments = arguments
      @description = description
    end

    # Convert to hash representation
    # @return [Hash]
    def to_h
      {
        name: @name,
        arguments: @arguments,
        description: @description
      }.compact
    end

    alias to_hash to_h

    def to_s
      "#{@name}(#{@arguments})"
    end
  end
end
