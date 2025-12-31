# frozen_string_literal: true

module Smolagents
  # Represents a streaming delta for chat messages
  class ChatMessageStreamDelta
    attr_accessor :content, :tool_calls, :token_usage

    # @param content [String, nil] Content delta
    # @param tool_calls [Array<ChatMessageToolCallStreamDelta>, nil] Tool call deltas
    # @param token_usage [TokenUsage, nil] Token usage update
    def initialize(content: nil, tool_calls: nil, token_usage: nil)
      @content = content
      @tool_calls = tool_calls
      @token_usage = token_usage
    end
  end
end
