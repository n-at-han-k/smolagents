#!/usr/bin/env ruby
# frozen_string_literal: true

# Rate Limiting and Retry Example
#
# This example demonstrates the utility classes for rate limiting
# and retry logic, useful when calling external APIs.

require_relative "../lib/smolagents"

include Smolagents

puts "=== Rate Limiter Demo ==="
puts

# Create a rate limiter: max 10 requests per minute
limiter = RateLimiter.new(requests_per_minute: 10)

puts "Rate limiter configured for 10 requests/minute"
puts "Enabled: #{limiter.enabled?}"
puts

# Simulate rapid API calls
puts "Making 5 rapid calls (observe throttling):"
5.times do |i|
  start = Time.now
  limiter.throttle  # Will sleep if needed
  elapsed = Time.now - start

  puts "  Call #{i + 1}: waited #{(elapsed * 1000).round}ms"
end

puts
puts "=== Rate Limiter (Disabled) ==="
puts

# Disabled rate limiter (nil requests_per_minute)
no_limit = RateLimiter.new(requests_per_minute: nil)
puts "Enabled: #{no_limit.enabled?}"

puts "Making 5 calls without throttling:"
5.times do |i|
  start = Time.now
  no_limit.throttle
  elapsed = Time.now - start
  puts "  Call #{i + 1}: waited #{(elapsed * 1000).round}ms"
end

puts
puts "=== Retry Logic Demo ==="
puts

# Simulate an unreliable operation
call_count = 0
unreliable_operation = lambda do
  call_count += 1
  puts "  Attempt #{call_count}..."

  if call_count < 3
    raise StandardError, "Temporary failure (attempt #{call_count})"
  end

  "Success on attempt #{call_count}!"
end

# Create a retrier with exponential backoff
retrier = Retrying.new(
  max_attempts: 5,
  wait_seconds: 0.1,
  exponential_base: 2.0,
  jitter: true,
  retry_predicate: ->(e) { e.is_a?(StandardError) }
)

puts "Retrying with max_attempts=5, wait_seconds=0.1, exponential_base=2.0"
puts

begin
  call_count = 0
  result = retrier.call(&unreliable_operation)
  puts "Result: #{result}"
rescue StandardError => e
  puts "Failed after all retries: #{e.message}"
end

puts
puts "=== Retry with Logging ==="
puts

# Create a simple logger that responds to #log
simple_logger = Object.new
def simple_logger.log(level)
  message = yield if block_given?
  puts "[LOG] #{message}"
end

call_count = 0
retrier_with_logging = Retrying.new(
  max_attempts: 4,
  wait_seconds: 0.05,
  exponential_base: 1.5,
  jitter: false,
  retry_predicate: ->(e) { e.message.include?("Temporary") },
  before_sleep_logger: [simple_logger, :info],
  after_logger: [simple_logger, :debug]
)

always_fails = lambda do
  call_count += 1
  raise StandardError, "Temporary error #{call_count}"
end

puts "Retrying operation that always fails (with logging):"
begin
  call_count = 0
  retrier_with_logging.call(&always_fails)
rescue StandardError => e
  puts "Final failure: #{e.message}"
end

puts
puts "=== Selective Retry ==="
puts

# Only retry specific exceptions
class NetworkError < StandardError; end
class ValidationError < StandardError; end

selective_retrier = Retrying.new(
  max_attempts: 3,
  wait_seconds: 0.01,
  retry_predicate: ->(e) { e.is_a?(NetworkError) }
)

puts "Testing NetworkError (should retry):"
attempts = 0
begin
  selective_retrier.call do
    attempts += 1
    raise NetworkError, "Connection failed" if attempts < 3
    "Connected!"
  end
  puts "  Success after #{attempts} attempts"
rescue NetworkError => e
  puts "  Failed: #{e.message}"
end

puts
puts "Testing ValidationError (should NOT retry):"
begin
  selective_retrier.call do
    raise ValidationError, "Invalid input"
  end
rescue ValidationError => e
  puts "  Immediately failed: #{e.message}"
end

puts
puts "=== Practical Example: API Client ==="
puts

# Combine rate limiting and retry for a robust API client
class RobustApiClient
  def initialize(requests_per_minute: 60, max_retries: 3)
    @limiter = RateLimiter.new(requests_per_minute: requests_per_minute)
    @retrier = Retrying.new(
      max_attempts: max_retries,
      wait_seconds: 1.0,
      exponential_base: 2.0,
      jitter: true,
      retry_predicate: method(:should_retry?)
    )
  end

  def get(url)
    @retrier.call do
      @limiter.throttle
      make_request(url)
    end
  end

  private

  def should_retry?(error)
    # Retry on network errors and rate limits, not on client errors
    case error
    when NetworkError
      true
    else
      error.message.include?("rate limit") || error.message.include?("timeout")
    end
  end

  def make_request(url)
    # Simulated request
    puts "  Making request to #{url}"
    "Response from #{url}"
  end
end

client = RobustApiClient.new(requests_per_minute: 120, max_retries: 3)

puts "Making API requests with rate limiting and retry:"
3.times do |i|
  result = client.get("https://api.example.com/resource/#{i}")
  puts "  Result: #{result}"
end

puts
puts "=== Summary ==="
puts

puts <<~SUMMARY
  RateLimiter:
    - Enforces minimum delay between requests
    - Useful for API rate limits
    - Can be disabled by passing nil

  Retrying:
    - Exponential backoff with optional jitter
    - Selective retry based on exception type
    - Pre/post logging hooks
    - Configurable max attempts and delays

  Together they enable robust API clients that:
    - Respect rate limits
    - Handle transient failures gracefully
    - Provide visibility into retry behavior
SUMMARY
