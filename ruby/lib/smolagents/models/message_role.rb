# frozen_string_literal: true

module Smolagents
  # Message roles for chat interactions
  module MessageRole
    USER = "user"
    ASSISTANT = "assistant"
    SYSTEM = "system"
    TOOL_CALL = "tool-call"
    TOOL_RESPONSE = "tool-response"

    # Get all available roles
    # @return [Array<String>]
    def self.roles
      [USER, ASSISTANT, SYSTEM, TOOL_CALL, TOOL_RESPONSE]
    end

    # Check if a role is valid
    # @param role [String] Role to check
    # @return [Boolean]
    def self.valid?(role)
      roles.include?(role)
    end
  end
end
