# frozen_string_literal: true

require_relative "agent_execution_error"

module Smolagents
  # Exception raised when executing a tool fails
  class AgentToolExecutionError < AgentExecutionError; end
end
