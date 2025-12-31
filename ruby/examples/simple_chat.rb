#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Simple chat session (like using Faraday for API calls)

require_relative "../lib/ai"

# Create a session with a client
session = AI::session(
  name: "my_chat",
  provider: :openai,
  model: "gpt-4o"
)

# Simple string input
response = session.chat("What is 2 + 2?")
puts response

# Using Message builder
message = AI::Message.new do |m|
  m.text "Explain this briefly"
  m.text "What is the Ruby programming language?"
end

response = session.chat(message)
puts response

# Session keeps history
puts "\nHistory: #{session.history.length} messages"
