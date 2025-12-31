#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: The loop is external and visible - YOU control it

require_relative "../lib/ai"

# Define a simple calculator tool
class Calculator < AI::Tool
  def initialize
    super(
      name: "calculate",
      description: "Evaluate a math expression",
      inputs: { expression: { type: "string" } }
    )
  end

  def call(expression:)
    eval(expression).to_s
  rescue => e
    "Error: #{e.message}"
  end
end

# Create session and decision maker
session = AI::Session.new(
  name: "calculator_task",
  client: AI::Clients::OpenAI.new
)

decision_maker = AI::DecisionMaker.new(
  tools: [Calculator.new]
)

# Get task from command line
task = ARGV.join(" ")
if task.empty?
  puts "Usage: ruby external_loop.rb 'your task'"
  exit 1
end

puts "Task: #{task}"
puts "-" * 40

# Start the task
action = decision_maker.start(task)
max_steps = 10
step = 0

# THE LOOP IS HERE - visible and in your control
loop do
  step += 1
  puts "Step #{step}: #{action.type}"

  case action.type
  when :call_llm
    puts "  Asking LLM..."
    response = session.chat(action.prompt)
    puts "  LLM said: #{response[0..100]}..."
    action = decision_maker.observe(response)

  when :call_tool
    puts "  Calling #{action.tool.name} with #{action.args}"
    result = action.tool.call(**action.args)
    puts "  Result: #{result}"
    action = decision_maker.observe(result)

  when :answer
    puts
    puts "=" * 40
    puts "ANSWER: #{action.result}"
    break

  when :error
    puts "ERROR: #{action.result}"
    break

  else
    puts "Unknown action type: #{action.type}"
    break
  end

  if step >= max_steps
    puts "Max steps reached"
    break
  end
end
