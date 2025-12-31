# AI Ruby

A minimal Ruby library for LLM interactions. No magic, no hidden loops.

## Architecture

| Class | Responsibility |
|-------|----------------|
| **Session** | Stores history, logging, defaults (like Faraday) |
| **Client** | Provider-specific API calls (Claude, OpenAI, Grok, OpenRouter) |
| **Message** | Builder for requests (like the Mail gem) |
| **DecisionMaker** | Decides next action - you control the loop |

## Usage

### Simple Chat

```ruby
require "ai"

session = AI.session(name: "chat", provider: :openai)

response = session.chat("What is Ruby?")
puts response

# History is kept
session.chat("Tell me more")
```

### Building Messages

```ruby
message = AI::Message.new do |m|
  m.text "Describe this image"
  m.image "/path/to/photo.jpg"
  m.response_schema { type: "object", ... }
end

session.chat(message)
```

### Using Clients Directly

```ruby
client = AI::Clients::Claude.new(model: "claude-sonnet-4-20250514")
response = client.call("Hello")

# Or via factory
client = AI.client(:openai, model: "gpt-4o")
```

### DecisionMaker with External Loop

The loop is **yours** - visible and controllable:

```ruby
dm = AI::DecisionMaker.new(tools: [Calculator.new])
action = dm.start("What is 15% of 340?")

loop do
  case action.type
  when :call_llm
    result = session.chat(action.prompt)
    action = dm.observe(result)

  when :call_tool
    result = action.tool.call(**action.args)
    action = dm.observe(result)

  when :answer
    puts action.result
    break
  end
end
```

### Custom Tools

```ruby
class WebSearch < AI::Tool
  def initialize
    super(
      name: "search",
      description: "Search the web",
      inputs: { query: { type: "string" } }
    )
  end

  def call(query:)
    # your implementation
  end
end
```

## Providers

```ruby
AI.client(:openai)      # OPENAI_API_KEY
AI.client(:claude)      # ANTHROPIC_API_KEY
AI.client(:grok)        # XAI_API_KEY
AI.client(:openrouter)  # OPENROUTER_API_KEY
```

## Files

```
lib/ai/
  session.rb          # History and logging
  message.rb          # Request builder
  decision_maker.rb   # Action decisions
  tool.rb             # Tool interface
  clients/
    base.rb           # HTTP helpers
    openai.rb         # OpenAI/ChatGPT
    claude.rb         # Anthropic Claude
    grok.rb           # xAI Grok
    open_router.rb    # OpenRouter
```

## License

Apache License 2.0
