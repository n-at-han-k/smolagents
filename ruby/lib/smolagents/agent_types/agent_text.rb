# frozen_string_literal: true

require_relative "agent_type"

module Smolagents
  # Text type returned by the agent. Behaves as a string.
  #
  # @example
  #   text = AgentText.new("Hello, world!")
  #   puts text         # => "Hello, world!"
  #   text.upcase       # => "HELLO, WORLD!"
  class AgentText < AgentType
    include Comparable

    # Delegate string methods to the underlying value
    def method_missing(method, *args, &block)
      if @value.respond_to?(method)
        @value.public_send(method, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      @value.respond_to?(method, include_private) || super
    end

    # Get the raw string value
    # @return [String]
    def to_raw
      @value
    end

    # Get the string representation
    # @return [String]
    def to_string
      @value.to_s
    end

    # Compare with other strings
    def <=>(other)
      to_s <=> other.to_s
    end

    # String concatenation
    def +(other)
      to_s + other.to_s
    end

    # Check equality
    def ==(other)
      to_s == other.to_s
    end

    alias eql? ==

    def hash
      to_s.hash
    end

    # Get string length
    def length
      @value.length
    end

    alias size length
  end
end
