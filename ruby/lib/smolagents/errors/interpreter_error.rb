# frozen_string_literal: true

require_relative "agent_error"

module Smolagents
  # Exception raised when the Ruby interpreter encounters an error
  class InterpreterError < AgentError; end
end
