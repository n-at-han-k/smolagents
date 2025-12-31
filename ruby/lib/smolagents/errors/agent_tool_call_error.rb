# frozen_string_literal: true

require_relative "agent_execution_error"

module Smolagents
  # Exception raised when incorrect arguments are passed to a tool
  class AgentToolCallError < AgentExecutionError; end
end
