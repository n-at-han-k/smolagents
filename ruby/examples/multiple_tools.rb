#!/usr/bin/env ruby
# frozen_string_literal: true

# Multiple Tools Example
#
# This example demonstrates how to define and use multiple tools together,
# similar to Python's multiple_tools.py example.
#
# In a real implementation, these tools would be passed to a CodeAgent
# which would decide which tools to use based on the user's query.

require_relative "../lib/smolagents"
require "net/http"
require "json"
require "uri"

module Smolagents
  # Base tool class with common functionality
  class Tool
    class << self
      attr_accessor :tool_name, :tool_description, :input_schema, :output_type
    end

    def call(**kwargs)
      raise NotImplementedError
    end

    def to_h
      {
        name: self.class.tool_name,
        description: self.class.tool_description,
        inputs: self.class.input_schema,
        output_type: self.class.output_type
      }
    end
  end

  # Weather tool using a mock response
  class WeatherTool < Tool
    self.tool_name = "get_weather"
    self.tool_description = "Get the current weather at the given location."
    self.input_schema = {
      location: { type: "string", description: "The city name" },
      celsius: { type: "boolean", description: "Use Celsius (default: false)", default: false }
    }
    self.output_type = "string"

    def call(location:, celsius: false)
      # Mock weather data - in production, call a real API
      temp = celsius ? 22 : 72
      unit = celsius ? "°C" : "°F"
      "The current weather in #{location} is Sunny with a temperature of #{temp}#{unit}."
    end
  end

  # Joke tool using JokeAPI
  class JokeTool < Tool
    self.tool_name = "get_joke"
    self.tool_description = "Fetches a random joke."
    self.input_schema = {}
    self.output_type = "string"

    def call
      uri = URI("https://v2.jokeapi.dev/joke/Any?type=single")

      begin
        response = Net::HTTP.get_response(uri)
        data = JSON.parse(response.body)

        if data["joke"]
          data["joke"]
        elsif data["setup"] && data["delivery"]
          "#{data['setup']} - #{data['delivery']}"
        else
          "Error: Unable to fetch joke."
        end
      rescue StandardError => e
        "Error fetching joke: #{e.message}"
      end
    end
  end

  # Wikipedia search tool
  class WikipediaTool < Tool
    self.tool_name = "search_wikipedia"
    self.tool_description = "Fetches a summary of a Wikipedia page for a given query."
    self.input_schema = {
      query: { type: "string", description: "The search term to look up" }
    }
    self.output_type = "string"

    def call(query:)
      encoded_query = URI.encode_www_form_component(query)
      uri = URI("https://en.wikipedia.org/api/rest_v1/page/summary/#{encoded_query}")

      begin
        response = Net::HTTP.get_response(uri)
        data = JSON.parse(response.body)

        title = data["title"]
        extract = data["extract"]

        "Summary for #{title}: #{extract}"
      rescue StandardError => e
        "Error fetching Wikipedia data: #{e.message}"
      end
    end
  end

  # Random fact tool
  class RandomFactTool < Tool
    self.tool_name = "get_random_fact"
    self.tool_description = "Fetches a random interesting fact."
    self.input_schema = {}
    self.output_type = "string"

    def call
      uri = URI("https://uselessfacts.jsph.pl/random.json?language=en")

      begin
        response = Net::HTTP.get_response(uri)
        data = JSON.parse(response.body)
        "Random Fact: #{data['text']}"
      rescue StandardError => e
        "Error fetching random fact: #{e.message}"
      end
    end
  end

  # Tool registry for managing multiple tools
  class ToolRegistry
    def initialize
      @tools = {}
    end

    def register(tool)
      @tools[tool.class.tool_name] = tool
    end

    def [](name)
      @tools[name]
    end

    def each(&block)
      @tools.values.each(&block)
    end

    def names
      @tools.keys
    end

    def to_a
      @tools.values
    end
  end
end

# Usage example
if __FILE__ == $PROGRAM_NAME
  include Smolagents

  # Create a registry and register all tools
  registry = ToolRegistry.new
  registry.register(WeatherTool.new)
  registry.register(JokeTool.new)
  registry.register(WikipediaTool.new)
  registry.register(RandomFactTool.new)

  puts "=== Available Tools ==="
  registry.each do |tool|
    puts "- #{tool.class.tool_name}: #{tool.class.tool_description.lines.first.strip}"
  end
  puts

  # Demonstrate each tool
  puts "=== Weather Tool ==="
  weather = registry["get_weather"]
  puts weather.call(location: "New York", celsius: false)
  puts

  puts "=== Wikipedia Tool ==="
  wiki = registry["search_wikipedia"]
  puts wiki.call(query: "Ruby programming language")
  puts

  puts "=== Random Fact Tool ==="
  fact = registry["get_random_fact"]
  puts fact.call
  puts

  puts "=== Joke Tool ==="
  joke = registry["get_joke"]
  puts joke.call

  # In a full implementation, you would create an agent like this:
  #
  # agent = CodeAgent.new(
  #   tools: registry.to_a,
  #   model: InferenceClientModel.new,
  #   stream_outputs: true
  # )
  #
  # agent.run("What is the weather in Paris and tell me a joke!")
end
