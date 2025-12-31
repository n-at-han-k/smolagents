# Smolagents Ruby Examples

This directory contains examples demonstrating how to use the Smolagents Ruby library.

## Running Examples

Each example is a standalone Ruby script. Run them from the `ruby` directory:

```bash
cd ruby
ruby examples/basic_tool.rb
ruby examples/memory_tracking.rb
# etc.
```

## Examples Overview

### Core Concepts

| Example | Description |
|---------|-------------|
| `basic_tool.rb` | How to define tools as Ruby classes |
| `multiple_tools.rb` | Working with multiple tools and tool registries |
| `custom_tool_class.rb` | Creating complex tools with dependencies |

### Memory & Execution

| Example | Description |
|---------|-------------|
| `memory_tracking.rb` | Using AgentMemory to track execution steps |
| `monitoring_and_logging.rb` | Token tracking, timing, and logging |

### Data Types

| Example | Description |
|---------|-------------|
| `agent_types_demo.rb` | Working with AgentText, AgentImage, AgentAudio |
| `chat_messages.rb` | Chat message types and tool call handling |

### Utilities

| Example | Description |
|---------|-------------|
| `rate_limiting_and_retry.rb` | Rate limiting and retry logic for API calls |

## Ruby vs Python Patterns

### Tool Definition

**Python:**
```python
@tool
def get_weather(location: str, celsius: bool = False) -> str:
    """Get weather at given location."""
    return f"Weather in {location}: sunny"
```

**Ruby:**
```ruby
class GetWeatherTool < Smolagents::Tool
  self.tool_name = "get_weather"
  self.tool_description = "Get weather at given location."
  self.input_schema = {
    location: { type: "string", description: "Location" },
    celsius: { type: "boolean", default: false }
  }
  self.output_type = "string"

  def call(location:, celsius: false)
    "Weather in #{location}: sunny"
  end
end
```

### Memory Management

**Python:**
```python
memory = AgentMemory(system_prompt="You are helpful.")
memory.steps.append(TaskStep(task="Do something"))
```

**Ruby:**
```ruby
memory = AgentMemory.new(system_prompt: "You are helpful.")
memory.steps << TaskStep.new(task: "Do something")
```

### Logging

**Python:**
```python
logger = AgentLogger(level=LogLevel.DEBUG)
logger.log("Message", level=LogLevel.INFO)
```

**Ruby:**
```ruby
logger = AgentLogger.new(level: LogLevel::DEBUG)
logger.log("Message", level: LogLevel::INFO)
```

## Notes

- These examples demonstrate the library's current capabilities
- Full agent orchestration (CodeAgent, ToolCallingAgent) is planned for future implementation
- Examples use mock data where external APIs would normally be called
