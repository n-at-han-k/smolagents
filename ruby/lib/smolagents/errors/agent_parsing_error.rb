# frozen_string_literal: true

require_relative "agent_error"

module Smolagents
  # Exception raised for errors in parsing agent output
  class AgentParsingError < AgentError; end
end
