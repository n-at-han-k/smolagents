# frozen_string_literal: true

require_relative "agent_error"

module Smolagents
  # Exception raised when agent exceeds maximum steps
  class AgentMaxStepsError < AgentError; end
end
