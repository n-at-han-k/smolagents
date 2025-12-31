#!/usr/bin/env ruby
# frozen_string_literal: true

# Monitoring and Logging Example
#
# This example demonstrates the monitoring and logging capabilities
# of the smolagents library, including:
# - Token usage tracking
# - Timing measurements
# - Custom logging levels
# - Step-by-step monitoring

require_relative "../lib/smolagents"

# Add a simple truncate helper (Rails' truncate isn't available in plain Ruby)
class String
  def truncate(length, omission: "...")
    return self if self.length <= length
    self[0, length - omission.length] + omission
  end
end

include Smolagents

puts "=== Logging Levels Demo ==="
puts

# Create loggers at different levels
debug_logger = AgentLogger.new(level: LogLevel::DEBUG)
info_logger = AgentLogger.new(level: LogLevel::INFO)
error_logger = AgentLogger.new(level: LogLevel::ERROR)

puts "Debug logger (shows everything):"
debug_logger.log("This is a debug message", level: LogLevel::DEBUG)
debug_logger.log("This is an info message", level: LogLevel::INFO)
debug_logger.log_error("This is an error")

puts
puts "Info logger (shows info and errors):"
info_logger.log("This is a debug message", level: LogLevel::DEBUG)  # Won't show
info_logger.log("This is an info message", level: LogLevel::INFO)
info_logger.log_error("This is an error")

puts
puts "Error logger (shows only errors):"
error_logger.log("This is a debug message", level: LogLevel::DEBUG)  # Won't show
error_logger.log("This is an info message", level: LogLevel::INFO)   # Won't show
error_logger.log_error("This is an error")

puts
puts "=== Token Usage Tracking ==="
puts

# Track token usage across multiple steps
step1_usage = TokenUsage.new(input_tokens: 1500, output_tokens: 250)
step2_usage = TokenUsage.new(input_tokens: 2000, output_tokens: 300)
step3_usage = TokenUsage.new(input_tokens: 1800, output_tokens: 400)

puts "Step 1: #{step1_usage}"
puts "Step 2: #{step2_usage}"
puts "Step 3: #{step3_usage}"

# Combine usage
total_usage = step1_usage + step2_usage + step3_usage
puts
puts "Total: #{total_usage}"

puts
puts "=== Timing Measurements ==="
puts

# Measure operation timing
timing = Timing.start_now
puts "Started at: #{Time.at(timing.start_time)}"

# Simulate some work
sleep(0.5)

timing.stop!
puts "Ended at: #{Time.at(timing.end_time)}"
puts "Duration: #{timing.duration.round(3)} seconds"

puts
puts "=== Monitor Demo ==="
puts

# Create a monitor to track agent execution
logger = AgentLogger.new(level: LogLevel::INFO)

# Mock model for demonstration
mock_model = Object.new

monitor = Smolagents::Monitor.new(tracked_model: mock_model, logger: logger)

# Simulate tracking multiple steps
3.times do |i|
  step_timing = Timing.start_now
  sleep(rand * 0.3)  # Random work
  step_timing.stop!

  step = ActionStep.new(
    step_number: i + 1,
    timing: step_timing,
    token_usage: TokenUsage.new(
      input_tokens: rand(1000..3000),
      output_tokens: rand(100..500)
    )
  )

  monitor.update_metrics(step)
end

puts
puts "Final token counts: #{monitor.total_token_counts}"
puts "Step durations: #{monitor.step_durations.map { |d| d.round(3) }}"

puts
puts "=== Callback Registry Demo ==="
puts

# Set up callbacks to react to different step types
callbacks = CallbackRegistry.new

callbacks.register(ActionStep) do |step|
  puts "[Callback] Action step #{step.step_number} completed"
  if step.token_usage
    puts "[Callback] Used #{step.token_usage.total_tokens} tokens"
  end
end

callbacks.register(TaskStep) do |step|
  puts "[Callback] New task received: #{step.task.truncate(50)}"
end

callbacks.register(FinalAnswerStep) do |step|
  puts "[Callback] Final answer: #{step.output}"
end

# Trigger callbacks with sample steps
puts "Triggering callbacks:"
callbacks.callback(TaskStep.new(task: "Calculate the fibonacci sequence up to 100"))

callbacks.callback(ActionStep.new(
  step_number: 1,
  timing: Timing.new(start_time: Time.now.to_f, end_time: Time.now.to_f + 0.5),
  token_usage: TokenUsage.new(input_tokens: 500, output_tokens: 100)
))

callbacks.callback(FinalAnswerStep.new(output: "0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89"))

puts
puts "=== Rich Logging Demo ==="
puts

logger = AgentLogger.new(level: LogLevel::INFO)

logger.log_rule("Agent Execution Start")

logger.log_task(
  content: "Find information about Ruby programming language",
  subtitle: "Task ID: 12345",
  title: "Research Task"
)

logger.log_code(
  title: "Generated Code",
  content: <<~RUBY
    result = search_wikipedia(query: "Ruby programming")
    summary = result.first(500)
    final_answer(summary)
  RUBY
)

logger.log_markdown(
  title: "Agent Response",
  content: <<~MD
    Ruby is a dynamic, open source programming language with a focus on
    simplicity and productivity. It has an elegant syntax that is natural
    to read and easy to write.
  MD
)
