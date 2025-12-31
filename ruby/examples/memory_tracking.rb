#!/usr/bin/env ruby
# frozen_string_literal: true

# Memory Tracking Example
#
# This example demonstrates how to use the AgentMemory class to track
# agent execution steps, similar to the Python library's memory system.

require_relative "../lib/smolagents"

# Add a simple truncate helper (Rails' truncate isn't available in plain Ruby)
class String
  def truncate(length, omission: "...")
    return self if self.length <= length
    self[0, length - omission.length] + omission
  end
end

include Smolagents

# Create a new agent memory with a system prompt
memory = AgentMemory.new(
  system_prompt: <<~PROMPT
    You are a helpful assistant that can answer questions and perform tasks.
    Always think step by step before providing an answer.
  PROMPT
)

puts "=== Agent Memory Demo ==="
puts

# Add a task step (user's request)
memory.steps << TaskStep.new(
  task: "What is the capital of France and what's the weather like there?"
)

# Simulate an action step (agent's first action)
timing1 = Timing.start_now
sleep(0.1) # Simulate some processing time
timing1.stop!

memory.steps << ActionStep.new(
  step_number: 1,
  timing: timing1,
  model_output: "I need to first identify the capital of France, then check the weather.",
  code_action: <<~RUBY,
    capital = "Paris"
    weather = get_weather(location: capital)
  RUBY
  observations: "Capital identified as Paris. Weather tool called.",
  token_usage: TokenUsage.new(input_tokens: 150, output_tokens: 45)
)

# Simulate a second action step
timing2 = Timing.start_now
sleep(0.05)
timing2.stop!

memory.steps << ActionStep.new(
  step_number: 2,
  timing: timing2,
  model_output: "Now I have all the information to answer the user.",
  observations: "Weather data received: Sunny, 22°C",
  action_output: "The capital of France is Paris. The weather there is sunny with 22°C.",
  token_usage: TokenUsage.new(input_tokens: 200, output_tokens: 30),
  is_final_answer: true
)

# Display the memory contents
puts "System Prompt:"
puts "-" * 40
puts memory.system_prompt.system_prompt
puts

puts "Steps Summary:"
puts "-" * 40
memory.steps.each_with_index do |step, idx|
  case step
  when TaskStep
    puts "#{idx + 1}. [Task] #{step.task}"
  when ActionStep
    puts "#{idx + 1}. [Action #{step.step_number}] Duration: #{step.timing.duration&.round(3)}s"
    puts "   Output: #{step.model_output&.truncate(60)}"
    if step.token_usage
      puts "   Tokens: #{step.token_usage.input_tokens} in / #{step.token_usage.output_tokens} out"
    end
  end
end

puts
puts "Full Code (all actions combined):"
puts "-" * 40
puts memory.full_code

# Create a logger and replay the execution
puts
puts "=== Replay with Logger ==="
logger = AgentLogger.new(level: LogLevel::INFO)
memory.replay(logger: logger)

# Export steps as JSON-serializable data
puts
puts "=== Exported Steps (JSON) ==="
require "json"
puts JSON.pretty_generate(memory.succinct_steps)
