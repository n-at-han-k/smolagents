# frozen_string_literal: true

module Smolagents
  # Base class for agent-related exceptions
  #
  # All agent errors inherit from this class and automatically log
  # the error message when created
  class AgentError < StandardError
    attr_reader :original_message

    # @param message [String] Error message
    # @param logger [AgentLogger] Logger to log the error
    def initialize(message, logger: nil)
      @original_message = message
      logger&.log_error(message)
      super(message)
    end

    # Convert to hash representation
    # @return [Hash] Hash with error type and message
    def to_h
      {
        type: self.class.name.split("::").last,
        message: @original_message
      }
    end

    alias to_hash to_h
  end
end
