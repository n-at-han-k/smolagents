# Smolagents Ruby

A minimal code-generating agent in ~150 lines of Ruby.

The agent writes Ruby code to solve your task, executes it, and repeats until done.

## Usage

### CLI

```bash
# Set your API key
export OPENAI_API_KEY=sk-...
# or
export ANTHROPIC_API_KEY=sk-ant-...

# Run a task
bin/smolagents "What is 2^10?"

# Use a different model
bin/smolagents -m gpt-4o "Calculate the factorial of 10"
bin/smolagents -p anthropic -m claude-3-opus-20240229 "List prime numbers under 50"

# Verbose mode
bin/smolagents -v "Solve this step by step: what is 15% of 340?"
```

### Options

```
-m, --model MODEL      Model to use (default: gpt-4)
-p, --provider PROVIDER  openai or anthropic (default: openai)
-s, --max-steps N      Maximum steps (default: 10)
-v, --verbose          Show detailed output
```

### Library

```ruby
require "smolagents"

# Create an agent
agent = Smolagents::Agent.new(
  model: "gpt-4",
  provider: "openai"
)

# Run a task
result = agent.run("What is the sum of the first 100 prime numbers?")
puts result
```

### Custom Tools

```ruby
require "smolagents"

# Define a tool
class Calculator < Smolagents::Core::Tool
  def initialize
    super(
      name: "calculate",
      description: "Evaluate a math expression",
      inputs: { expression: { type: "string" } }
    )
  end

  def call(expression:)
    eval(expression).to_s
  end
end

# Use it
agent = Smolagents::Agent.new(
  model: "gpt-4",
  provider: "openai",
  tools: [Calculator.new]
)

result = agent.run("Use the calculator to compute 123 * 456")
```

## How It Works

1. Agent sends task to LLM with system prompt
2. LLM responds with Ruby code in a ```ruby block
3. Agent executes the code in a sandbox
4. If code calls `final_answer(result)`, return the result
5. Otherwise, send execution output back to LLM and repeat

That's it. ~150 lines total.

## Files

```
lib/smolagents/core/
  agent.rb      # The main loop
  tool.rb       # Tool interface
  model.rb      # OpenAI/Anthropic client
  executor.rb   # Code execution sandbox
```

## License

Apache License 2.0
