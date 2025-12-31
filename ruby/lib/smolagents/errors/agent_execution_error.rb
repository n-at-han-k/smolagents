# frozen_string_literal: true

require_relative "agent_error"

module Smolagents
  # Exception raised for errors in agent execution
  class AgentExecutionError < AgentError; end
end
