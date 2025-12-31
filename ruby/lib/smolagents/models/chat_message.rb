# frozen_string_literal: true

require "json"
require_relative "message_role"
require_relative "chat_message_tool_call"

module Smolagents
  # A chat message in a conversation
  class ChatMessage
    attr_accessor :role, :content, :tool_calls, :raw, :token_usage

    # @param role [String] Message role (user, assistant, system, tool-call, tool-response)
    # @param content [String, Array<Hash>, nil] Message content
    # @param tool_calls [Array<ChatMessageToolCall>, nil] Tool calls in this message
    # @param raw [Object, nil] Raw API response
    # @param token_usage [TokenUsage, nil] Token usage for this message
    def initialize(role:, content: nil, tool_calls: nil, raw: nil, token_usage: nil)
      @role = role
      @content = content
      @tool_calls = tool_calls&.map { |tc| coerce_tool_call(tc) }
      @raw = raw
      @token_usage = token_usage
    end

    # Convert to hash representation
    # @return [Hash]
    def to_h
      {
        role: @role,
        content: @content,
        tool_calls: @tool_calls&.map(&:to_h),
        token_usage: @token_usage&.to_h
      }.compact
    end

    alias to_hash to_h

    # Convert to JSON string
    # @return [String]
    def to_json(*args)
      to_h.to_json(*args)
    end

    # Create a user message
    # @param content [String] Message content
    # @return [ChatMessage]
    def self.user(content)
      new(role: MessageRole::USER, content: [{ type: "text", text: content }])
    end

    # Create an assistant message
    # @param content [String] Message content
    # @return [ChatMessage]
    def self.assistant(content)
      new(role: MessageRole::ASSISTANT, content: [{ type: "text", text: content }])
    end

    # Create a system message
    # @param content [String] Message content
    # @return [ChatMessage]
    def self.system(content)
      new(role: MessageRole::SYSTEM, content: [{ type: "text", text: content }])
    end

    private

    def coerce_tool_call(tc)
      return tc if tc.is_a?(ChatMessageToolCall)

      ChatMessageToolCall.new(
        function: tc[:function] || tc["function"],
        id: tc[:id] || tc["id"],
        type: tc[:type] || tc["type"] || "function"
      )
    end
  end
end
