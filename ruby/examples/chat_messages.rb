#!/usr/bin/env ruby
# frozen_string_literal: true

# Chat Messages Example
#
# This example demonstrates the chat message types used for
# communication between agents and LLMs, including tool calls.

require_relative "../lib/smolagents"
require "json"

# Add a simple truncate helper (Rails' truncate isn't available in plain Ruby)
class String
  def truncate(length, omission: "...")
    return self if self.length <= length
    self[0, length - omission.length] + omission
  end
end

include Smolagents

puts "=== Basic Chat Messages ==="
puts

# Create messages using factory methods
system_msg = ChatMessage.system("You are a helpful AI assistant.")
user_msg = ChatMessage.user("What's the weather like in Paris?")
assistant_msg = ChatMessage.assistant("I'll check the weather for you.")

puts "System message:"
puts JSON.pretty_generate(system_msg.to_h)
puts

puts "User message:"
puts JSON.pretty_generate(user_msg.to_h)
puts

puts "Assistant message:"
puts JSON.pretty_generate(assistant_msg.to_h)
puts

puts "=== Message Roles ==="
puts

puts "Available roles:"
MessageRole.roles.each do |role|
  puts "  - #{role}"
end
puts

puts "Is 'user' valid? #{MessageRole.valid?('user')}"
puts "Is 'robot' valid? #{MessageRole.valid?('robot')}"

puts
puts "=== Tool Calls ==="
puts

# Create a tool call function
function = ChatMessageToolCallFunction.new(
  name: "get_weather",
  arguments: { location: "Paris", celsius: true }.to_json,
  description: "Get weather information"
)

puts "Function: #{function}"
puts

# Create a complete tool call
tool_call = ChatMessageToolCall.new(
  function: function,
  id: "call_abc123",
  type: "function"
)

puts "Tool call: #{tool_call}"
puts JSON.pretty_generate(tool_call.to_h)
puts

# Create an assistant message with tool calls
assistant_with_tools = ChatMessage.new(
  role: MessageRole::ASSISTANT,
  content: [{ type: "text", text: "I'll check the weather now." }],
  tool_calls: [tool_call]
)

puts "Assistant message with tool call:"
puts JSON.pretty_generate(assistant_with_tools.to_h)
puts

puts "=== Tool Response ==="
puts

# Simulate a tool response
tool_response = ChatMessage.new(
  role: MessageRole::TOOL_RESPONSE,
  content: [{
    type: "text",
    text: "Call id: call_abc123\nObservation: The weather in Paris is sunny, 22°C"
  }]
)

puts "Tool response:"
puts JSON.pretty_generate(tool_response.to_h)
puts

puts "=== Streaming with Deltas ==="
puts

# Simulate streaming response
deltas = [
  ChatMessageStreamDelta.new(content: "The "),
  ChatMessageStreamDelta.new(content: "weather "),
  ChatMessageStreamDelta.new(content: "in Paris "),
  ChatMessageStreamDelta.new(content: "is sunny."),
  ChatMessageStreamDelta.new(
    token_usage: TokenUsage.new(input_tokens: 50, output_tokens: 10)
  )
]

puts "Received #{deltas.length} stream deltas"

# Agglomerate into a single message
final_message = Smolagents.agglomerate_stream_deltas(deltas)
puts "Agglomerated message:"
puts JSON.pretty_generate(final_message.to_h)
puts

puts "=== Streaming Tool Calls ==="
puts

# Simulate streaming tool call (arrives in pieces)
tool_call_deltas = [
  ChatMessageStreamDelta.new(
    tool_calls: [
      ChatMessageToolCallStreamDelta.new(
        index: 0,
        id: "call_xyz789",
        type: "function",
        function: ChatMessageToolCallFunction.new(name: "search_", arguments: "")
      )
    ]
  ),
  ChatMessageStreamDelta.new(
    tool_calls: [
      ChatMessageToolCallStreamDelta.new(
        index: 0,
        function: ChatMessageToolCallFunction.new(name: "wikipedia", arguments: '{"query":')
      )
    ]
  ),
  ChatMessageStreamDelta.new(
    tool_calls: [
      ChatMessageToolCallStreamDelta.new(
        index: 0,
        function: ChatMessageToolCallFunction.new(name: "", arguments: '"Ruby"}')
      )
    ]
  ),
  ChatMessageStreamDelta.new(
    token_usage: TokenUsage.new(input_tokens: 100, output_tokens: 25)
  )
]

puts "Streaming tool call deltas..."
message_with_tool = Smolagents.agglomerate_stream_deltas(tool_call_deltas)
puts "Agglomerated tool call message:"
puts JSON.pretty_generate(message_with_tool.to_h)
puts

puts "=== Building a Conversation ==="
puts

# Build a complete conversation
conversation = [
  ChatMessage.system("You are a helpful assistant with access to weather and search tools."),
  ChatMessage.user("What's the weather in Tokyo?"),
  ChatMessage.new(
    role: MessageRole::ASSISTANT,
    content: [{ type: "text", text: "I'll check the weather in Tokyo for you." }],
    tool_calls: [
      ChatMessageToolCall.new(
        function: ChatMessageToolCallFunction.new(
          name: "get_weather",
          arguments: '{"location": "Tokyo", "celsius": true}'
        ),
        id: "call_weather_1"
      )
    ]
  ),
  ChatMessage.new(
    role: MessageRole::TOOL_RESPONSE,
    content: [{
      type: "text",
      text: "Call id: call_weather_1\nThe weather in Tokyo is cloudy, 18°C"
    }]
  ),
  ChatMessage.assistant("The current weather in Tokyo is cloudy with a temperature of 18°C.")
]

puts "Full conversation (#{conversation.length} messages):"
conversation.each_with_index do |msg, i|
  role = msg.role.upcase
  content = msg.content&.first&.dig(:text) || msg.content&.first&.dig("text") || "(tool calls)"
  puts "#{i + 1}. [#{role}] #{content.to_s.truncate(60)}"
end

puts
puts "=== Utility: get_dict_from_nested_dataclasses ==="
puts

# Convert complex nested objects to plain hashes
nested_message = ChatMessage.new(
  role: MessageRole::ASSISTANT,
  content: [{ type: "text", text: "Hello" }],
  tool_calls: [tool_call],
  token_usage: TokenUsage.new(input_tokens: 10, output_tokens: 5)
)

plain_dict = Smolagents.get_dict_from_nested_dataclasses(nested_message)
puts "Converted to plain hash:"
puts JSON.pretty_generate(plain_dict)
