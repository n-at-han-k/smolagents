# Smolagents Ruby

A Ruby port of the [smolagents](https://github.com/huggingface/smolagents) library for building AI agents.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'smolagents'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install smolagents
```

## Usage

### Basic Example

```ruby
require 'smolagents'

# Create an agent memory with a system prompt
memory = Smolagents::AgentMemory.new(
  system_prompt: "You are a helpful AI assistant."
)

# Add a task step
memory.steps << Smolagents::TaskStep.new(task: "Help me write code")

# Create timing for an action
timing = Smolagents::Timing.start_now

# Add an action step
memory.steps << Smolagents::ActionStep.new(
  step_number: 1,
  timing: timing,
  model_output: "I'll help you write code!"
)

# Stop timing when done
timing.stop!

# Track token usage
usage = Smolagents::TokenUsage.new(input_tokens: 100, output_tokens: 50)
puts usage.total_tokens # => 150
```

### Agent Types

```ruby
# Text output that behaves like a string
text = Smolagents::AgentText.new("Hello, world!")
puts text.upcase  # => "HELLO, WORLD!"

# Image output
image = Smolagents::AgentImage.new("/path/to/image.png")
image.save("output.png")

# Audio output
audio = Smolagents::AgentAudio.new("/path/to/audio.wav")
puts audio.duration  # Duration in seconds
```

### Logging

```ruby
# Create a logger
logger = Smolagents::AgentLogger.new(level: Smolagents::LogLevel::DEBUG)

# Log at different levels
logger.log("Info message", level: Smolagents::LogLevel::INFO)
logger.log_error("Something went wrong!")
logger.log_code(title: "Python", content: "print('hello')")
```

### Callback Registry

```ruby
# Register callbacks for different step types
registry = Smolagents::CallbackRegistry.new

registry.register(Smolagents::ActionStep) do |step|
  puts "Action step #{step.step_number} completed!"
end

registry.register(Smolagents::PlanningStep) do |step|
  puts "Plan created: #{step.plan}"
end

# Callbacks are triggered automatically during agent execution
```

### Retry Logic

```ruby
# Create a retrier with exponential backoff
retrier = Smolagents::Retrying.new(
  max_attempts: 3,
  wait_seconds: 1.0,
  exponential_base: 2.0,
  jitter: true,
  retry_predicate: ->(e) { e.is_a?(Net::OpenTimeout) }
)

# Use it to wrap API calls
result = retrier.call { make_api_request }
```

### Rate Limiting

```ruby
# Limit to 60 requests per minute
limiter = Smolagents::RateLimiter.new(requests_per_minute: 60)

100.times do
  limiter.throttle  # Automatically waits if needed
  make_api_call
end
```

## Modules Converted

| Python Module | Ruby Module | Description |
|---------------|-------------|-------------|
| `monitoring.py` | `monitoring.rb` | TokenUsage, Timing, Monitor, LogLevel, AgentLogger |
| `utils.py` | `utils.rb`, `errors.rb` | Utility functions and error classes |
| `agent_types.py` | `agent_types.rb` | AgentType, AgentText, AgentImage, AgentAudio |
| `memory.py` | `memory.rb` | MemoryStep classes, AgentMemory, CallbackRegistry |
| `models.py` | `models.rb` | ChatMessage, MessageRole, tool call classes |

## Ruby Idioms Used

This port uses idiomatic Ruby patterns:

- **Keyword arguments** instead of positional arguments for clarity
- **attr_reader/attr_accessor** for property access
- **Modules** for namespacing and mixins
- **Blocks** for callbacks instead of function references
- **Method delegation** via `method_missing` for wrapper types
- **Comparable** mixin for comparison operations
- **to_h/to_s** conventions for serialization
- **Frozen string literals** for performance
- **RuboCop-compliant** code style

## License

This project is licensed under the Apache License 2.0 - see the original [smolagents](https://github.com/huggingface/smolagents) repository for details.
