#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Building messages (like the Mail gem)

require_relative "../lib/ai"

# Simple text message
msg1 = AI::Message.new do |m|
  m.text "Hello, how are you?"
end

puts "Message 1: #{msg1}"

# Message with image
msg2 = AI::Message.new do |m|
  m.text "What's in this image?"
  m.image "https://example.com/photo.jpg"
end

puts "Message 2: #{msg2.to_h}"

# Message with attachment and schema
msg3 = AI::Message.new do |m|
  m.text "Extract the data from this document"
  m.attachment "/path/to/doc.pdf"
  m.response_schema({
    type: "object",
    properties: {
      title: { type: "string" },
      date: { type: "string" }
    }
  })
end

puts "Message 3: #{msg3.to_h}"

# Chainable syntax
msg4 = AI::Message.new
  .text("First part")
  .text("Second part")
  .meta(:priority, :high)

puts "Message 4: #{msg4.to_h}"
