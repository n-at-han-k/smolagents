# frozen_string_literal: true

require_relative "models/message_role"
require_relative "models/chat_message_tool_call_function"
require_relative "models/chat_message_tool_call"
require_relative "models/chat_message"
require_relative "models/chat_message_tool_call_stream_delta"
require_relative "models/chat_message_stream_delta"

module Smolagents
  module_function

  # Agglomerate a list of stream deltas into a single chat message
  #
  # @param stream_deltas [Array<ChatMessageStreamDelta>] Stream deltas to combine
  # @param role [String] Role for the resulting message
  # @return [ChatMessage] Combined message
  def agglomerate_stream_deltas(stream_deltas, role: MessageRole::ASSISTANT)
    accumulated_tool_calls = {}
    accumulated_content = ""
    total_input_tokens = 0
    total_output_tokens = 0

    stream_deltas.each do |delta|
      if delta.token_usage
        total_input_tokens += delta.token_usage.input_tokens
        total_output_tokens += delta.token_usage.output_tokens
      end

      accumulated_content += delta.content if delta.content

      delta.tool_calls&.each do |tc|
        next unless tc.index

        if accumulated_tool_calls[tc.index]
          existing = accumulated_tool_calls[tc.index]
          existing.id ||= tc.id
          existing.type ||= tc.type
          if tc.function
            existing.function ||= ChatMessageToolCallFunction.new(name: "", arguments: "")
            existing.function.name += tc.function.name.to_s
            existing.function.arguments += tc.function.arguments.to_s
          end
        else
          accumulated_tool_calls[tc.index] = tc.dup
        end
      end
    end

    tool_calls = accumulated_tool_calls.values.map do |tc|
      ChatMessageToolCall.new(
        function: tc.function,
        id: tc.id || "",
        type: tc.type || "function"
      )
    end

    token_usage = TokenUsage.new(
      input_tokens: total_input_tokens,
      output_tokens: total_output_tokens
    ) if total_input_tokens.positive? || total_output_tokens.positive?

    ChatMessage.new(
      role: role,
      content: accumulated_content.empty? ? nil : [{ type: "text", text: accumulated_content }],
      tool_calls: tool_calls.empty? ? nil : tool_calls,
      token_usage: token_usage
    )
  end

  # Convert nested data structures to plain hashes
  #
  # @param obj [Object] Object to convert
  # @param ignore_key [String, nil] Key to ignore in conversion
  # @return [Object] Converted object
  def get_dict_from_nested_dataclasses(obj, ignore_key: nil)
    case obj
    when Hash
      obj.transform_keys(&:to_s)
         .reject { |k, _| k == ignore_key }
         .transform_values { |v| get_dict_from_nested_dataclasses(v, ignore_key: ignore_key) }
    when Array
      obj.map { |item| get_dict_from_nested_dataclasses(item, ignore_key: ignore_key) }
    else
      obj.respond_to?(:to_h) ? get_dict_from_nested_dataclasses(obj.to_h, ignore_key: ignore_key) : obj
    end
  end
end
