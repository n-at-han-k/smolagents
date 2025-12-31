#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic Tool Example
#
# This example demonstrates how to define and use tools in a Ruby-idiomatic way.
# Compare to Python's @tool decorator pattern.

require_relative "../lib/smolagents"

module Smolagents
  # In Ruby, we define tools as classes that inherit from a base Tool class.
  # This is more idiomatic than Python's decorator approach.
  #
  # Future implementation would include:
  # - Tool base class with #call method
  # - Automatic argument validation
  # - Type coercion
  class Tool
    class << self
      attr_accessor :tool_name, :tool_description, :input_schema, :output_type
    end

    def call(**kwargs)
      raise NotImplementedError, "Subclasses must implement #call"
    end
  end

  # Example: Weather tool
  #
  # In Python:
  #   @tool
  #   def get_weather(location: str, celsius: bool = False) -> str:
  #       """Get weather at given location."""
  #       return "The weather is sunny"
  #
  # In Ruby, we prefer explicit classes:
  class GetWeatherTool < Tool
    self.tool_name = "get_weather"
    self.tool_description = <<~DESC
      Get weather in the next days at given location.
      Secretly this tool does not care about the location, it hates the weather everywhere.
    DESC
    self.input_schema = {
      location: { type: "string", description: "The location to check weather for" },
      celsius: { type: "boolean", description: "Return temperature in Celsius", default: false }
    }
    self.output_type = "string"

    def call(location:, celsius: false)
      # In a real implementation, this would call a weather API
      temp_unit = celsius ? "°C" : "°F"
      temp = celsius ? -10 : 14

      "The weather in #{location} is UNGODLY with torrential rains and temperatures of #{temp}#{temp_unit}"
    end
  end
end

# Usage example
if __FILE__ == $PROGRAM_NAME
  weather_tool = Smolagents::GetWeatherTool.new

  puts "Tool: #{weather_tool.class.tool_name}"
  puts "Description: #{weather_tool.class.tool_description}"
  puts

  # Call the tool
  result = weather_tool.call(location: "Paris", celsius: true)
  puts "Result: #{result}"

  result = weather_tool.call(location: "New York")
  puts "Result: #{result}"
end
