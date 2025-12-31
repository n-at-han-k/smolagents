#!/usr/bin/env ruby
# frozen_string_literal: true

# Custom Tool Class Example
#
# This example demonstrates how to create custom tool classes in Ruby,
# similar to Python's class-based Tool pattern used in rag.py.
#
# Ruby's class-based approach is more natural for complex tools that
# need initialization, state, or dependencies.

require_relative "../lib/smolagents"

module Smolagents
  # Abstract base class for tools
  class Tool
    class << self
      attr_accessor :tool_name, :tool_description, :input_schema, :output_type
    end

    def call(**kwargs)
      raise NotImplementedError, "Subclasses must implement #call"
    end

    # Convert to OpenAI function-calling format
    def to_function_schema
      {
        type: "function",
        function: {
          name: self.class.tool_name,
          description: self.class.tool_description,
          parameters: {
            type: "object",
            properties: self.class.input_schema.transform_values do |v|
              { type: v[:type], description: v[:description] }
            end,
            required: self.class.input_schema.select { |_, v| !v.key?(:default) }.keys.map(&:to_s)
          }
        }
      }
    end
  end

  # Example: Document Retriever Tool
  #
  # This is similar to Python's RetrieverTool in rag.py
  # In Ruby, we initialize with dependencies and maintain state
  class RetrieverTool < Tool
    self.tool_name = "retriever"
    self.tool_description = <<~DESC
      Uses lexical search to retrieve document chunks that could be
      most relevant to answer your query. Use the affirmative form
      rather than a question for best results.
    DESC
    self.input_schema = {
      query: {
        type: "string",
        description: "The search query. Should be lexically close to target documents."
      }
    }
    self.output_type = "string"

    def initialize(documents, top_k: 5)
      @documents = documents
      @top_k = top_k
    end

    def call(query:)
      raise ArgumentError, "Query must be a string" unless query.is_a?(String)

      # Simple BM25-like scoring (simplified for demonstration)
      query_terms = query.downcase.split(/\W+/)

      scored_docs = @documents.map do |doc|
        doc_terms = doc[:content].downcase.split(/\W+/)
        score = query_terms.count { |term| doc_terms.include?(term) }
        { doc: doc, score: score }
      end

      top_docs = scored_docs
        .sort_by { |d| -d[:score] }
        .take(@top_k)
        .select { |d| d[:score] > 0 }

      return "No relevant documents found." if top_docs.empty?

      result = "\nRetrieved documents:\n"
      top_docs.each_with_index do |item, i|
        result += "\n\n===== Document #{i} (score: #{item[:score]}) =====\n"
        result += item[:doc][:content]
      end

      result
    end
  end

  # Example: SQL Engine Tool
  #
  # This is similar to Python's sql_engine tool in text_to_sql.py
  class SqlEngineTool < Tool
    self.tool_name = "sql_engine"
    self.tool_description = <<~DESC
      Allows you to perform SQL queries on the database.
      Returns a string representation of the result.
    DESC
    self.input_schema = {
      query: {
        type: "string",
        description: "The SQL query to execute. Must be valid SQL syntax."
      }
    }
    self.output_type = "string"

    def initialize(connection)
      @connection = connection
    end

    def call(query:)
      # In a real implementation, you'd use the connection
      # For safety, you might want to add query validation
      #
      # Example with Sequel:
      #   @connection.fetch(query).map(&:to_h).to_s
      #
      # Example with ActiveRecord:
      #   ActiveRecord::Base.connection.execute(query).to_a.to_s

      # Mock response for demonstration
      <<~RESULT
        Query: #{query}
        Results:
        (1, 'Alan Payne', 12.06, 1.20)
        (2, 'Alex Mason', 23.86, 0.24)
      RESULT
    end
  end

  # Example: Configurable HTTP Tool
  #
  # Shows how to create tools with configuration
  class HttpTool < Tool
    self.tool_name = "http_request"
    self.tool_description = "Make HTTP requests to specified URLs."
    self.input_schema = {
      url: { type: "string", description: "The URL to request" },
      method: { type: "string", description: "HTTP method (GET, POST)", default: "GET" }
    }
    self.output_type = "string"

    def initialize(base_url: nil, headers: {}, timeout: 30)
      @base_url = base_url
      @headers = headers
      @timeout = timeout
    end

    def call(url:, method: "GET")
      full_url = @base_url ? File.join(@base_url, url) : url

      # In production, use Net::HTTP or Faraday
      "Mock response from #{method} #{full_url}"
    end
  end
end

# Usage example
if __FILE__ == $PROGRAM_NAME
  include Smolagents

  puts "=== Document Retriever Tool ==="
  puts

  # Sample documents (in production, load from a database or file)
  documents = [
    { id: 1, content: "Ruby is a dynamic programming language with a focus on simplicity and productivity." },
    { id: 2, content: "Python is widely used for machine learning and data science applications." },
    { id: 3, content: "The forward pass in neural networks computes the output from input." },
    { id: 4, content: "The backward pass computes gradients for updating model weights." },
    { id: 5, content: "Ruby on Rails is a popular web framework written in Ruby." },
    { id: 6, content: "Training deep learning models requires significant GPU resources." }
  ]

  retriever = RetrieverTool.new(documents, top_k: 3)
  puts "Tool Schema:"
  require "json"
  puts JSON.pretty_generate(retriever.to_function_schema)
  puts

  puts "Query: 'Ruby programming language'"
  puts retriever.call(query: "Ruby programming language")
  puts

  puts "Query: 'neural network training backward'"
  puts retriever.call(query: "neural network training backward")
  puts

  puts "=== SQL Engine Tool ==="
  puts

  # Mock database connection
  mock_connection = Object.new
  sql_tool = SqlEngineTool.new(mock_connection)

  puts sql_tool.call(query: "SELECT * FROM receipts WHERE price > 20")
  puts

  puts "=== HTTP Tool with Configuration ==="
  puts

  # Configure an HTTP tool for a specific API
  api_tool = HttpTool.new(
    base_url: "https://api.example.com",
    headers: { "Authorization" => "Bearer token123" },
    timeout: 10
  )

  puts api_tool.call(url: "/users/1", method: "GET")

  # In a full agent implementation:
  #
  # agent = CodeAgent.new(
  #   tools: [retriever, sql_tool, api_tool],
  #   model: model
  # )
  #
  # agent.run("Find documents about Ruby and query the database for expensive receipts")
end
