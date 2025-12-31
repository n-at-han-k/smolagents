# frozen_string_literal: true

# Copyright 2024 HuggingFace Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "json"

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

  # Function information for a tool call
  class ChatMessageToolCallFunction
    attr_accessor :name, :arguments, :description

    # @param name [String] Function name
    # @param arguments [Object] Function arguments
    # @param description [String, nil] Optional description
    def initialize(name:, arguments:, description: nil)
      @name = name
      @arguments = arguments
      @description = description
    end

    # Convert to hash representation
    # @return [Hash]
    def to_h
      {
        name: @name,
        arguments: @arguments,
        description: @description
      }.compact
    end

    alias to_hash to_h

    def to_s
      "#{@name}(#{@arguments})"
    end
  end

  # Represents a tool call in a chat message
  class ChatMessageToolCall
    attr_accessor :function, :id, :type

    # @param function [ChatMessageToolCallFunction, Hash] The function being called
    # @param id [String] Unique identifier for the call
    # @param type [String] Type of tool call (default: "function")
    def initialize(function:, id:, type: "function")
      @function = function.is_a?(Hash) ? ChatMessageToolCallFunction.new(**function) : function
      @id = id
      @type = type
    end

    # Convert to hash representation
    # @return [Hash]
    def to_h
      {
        function: @function.to_h,
        id: @id,
        type: @type
      }
    end

    alias to_hash to_h

    def to_s
      "Call: #{@id}: Calling #{@function.name} with arguments: #{@function.arguments}"
    end
  end

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

  # Represents a streaming delta for tool calls
  class ChatMessageToolCallStreamDelta
    attr_accessor :index, :id, :type, :function

    # @param index [Integer, nil] Index in the tool calls array
    # @param id [String, nil] Tool call ID
    # @param type [String, nil] Tool call type
    # @param function [ChatMessageToolCallFunction, nil] Function details
    def initialize(index: nil, id: nil, type: nil, function: nil)
      @index = index
      @id = id
      @type = type
      @function = function
    end
  end

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
