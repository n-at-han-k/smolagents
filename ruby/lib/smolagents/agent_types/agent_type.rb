# frozen_string_literal: true

require "logger"

module Smolagents
  # Abstract class for types that can be returned by agents.
  #
  # These objects serve three purposes:
  # - They behave as the type they're meant to be (string for text, image for images)
  # - They can be stringified via to_s
  # - They provide consistent interfaces for raw and string representations
  #
  # @abstract Subclass and override {#to_raw} and {#to_string}
  class AgentType
    attr_reader :value

    # @param value [Object] The wrapped value
    def initialize(value)
      @value = value
      @logger = Logger.new($stderr)
    end

    # Convert to string representation
    # @return [String]
    def to_s
      to_string
    end

    # Get the raw underlying value
    # @return [Object]
    def to_raw
      @logger.error("This is a raw AgentType of unknown type. Display and string conversion will be unreliable")
      @value
    end

    # Get string representation for serialization
    # @return [String]
    def to_string
      @logger.error("This is a raw AgentType of unknown type. Display and string conversion will be unreliable")
      @value.to_s
    end
  end
end
