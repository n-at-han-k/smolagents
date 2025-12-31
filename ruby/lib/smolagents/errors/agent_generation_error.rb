# frozen_string_literal: true

require_relative "agent_error"

module Smolagents
  # Exception raised for errors in LLM generation
  class AgentGenerationError < AgentError; end
end
