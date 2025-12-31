# frozen_string_literal: true

require_relative "tools/base_tool"
require_relative "tools/tool"
require_relative "tools/tool_collection"
require_relative "tools/pipeline_tool"

module Smolagents
  # Helper method to create a tool from a block (similar to Python's @tool decorator)
  #
  # @param name [String] Tool name
  # @param description [String] Tool description
  # @param inputs [Hash] Input schema
  # @param output_type [String] Output type
  # @yield The tool implementation
  # @return [Tool]
  #
  # @example
  #   weather_tool = Smolagents.create_tool(
  #     name: "get_weather",
  #     description: "Get weather for a location",
  #     inputs: {
  #       location: { type: "string", description: "City name" }
  #     },
  #     output_type: "string"
  #   ) do |location:|
  #     "Weather in #{location}: sunny"
  #   end
  #
  def self.create_tool(name:, description:, inputs:, output_type: "string", output_schema: nil, &block)
    raise ArgumentError, "Block required" unless block_given?

    tool_class = Class.new(Tool) do
      self.tool_name = name
      self.tool_description = description
      self.input_schema = inputs
      self.output_type = output_type
      self.output_schema = output_schema if output_schema

      define_method(:forward, &block)
    end

    tool_class.new
  end

  # Validate tool arguments against tool's input schema.
  #
  # @param tool [Tool] The tool to validate against
  # @param arguments [Hash, Object] The arguments to validate
  # @raise [ValueError] If arguments don't match schema
  # @raise [TypeError] If argument types don't match
  def self.validate_tool_arguments(tool, arguments)
    if arguments.is_a?(Hash)
      arguments.each do |key, value|
        key_sym = key.to_sym
        unless tool.inputs.key?(key_sym)
          raise ValueError, "Argument #{key} is not in the tool's input schema"
        end

        actual_type = get_json_schema_type(value)
        expected_type = tool.inputs[key_sym][:type]
        expected_nullable = tool.inputs[key_sym][:nullable]

        # Type is valid if it matches, is "any", or is null for nullable parameters
        type_matches = if expected_type.is_a?(Array)
                         expected_type.include?(actual_type)
                       else
                         actual_type == expected_type
                       end

        unless type_matches || expected_type == "any" || (actual_type == "null" && expected_nullable)
          # Allow integer -> number coercion
          next if actual_type == "integer" && expected_type == "number"

          raise TypeError,
                "Argument #{key} has type '#{actual_type}' but should be '#{expected_type}'"
        end
      end

      # Check required arguments
      tool.inputs.each do |key, schema|
        nullable = schema[:nullable] || schema[:default]
        unless arguments.key?(key) || arguments.key?(key.to_s) || nullable
          raise ValueError, "Argument #{key} is required"
        end
      end
    else
      # Single argument case
      expected_type = tool.inputs.values.first[:type]
      actual_type = get_json_schema_type(arguments)
      unless actual_type == expected_type || expected_type == "any"
        raise TypeError,
              "Argument has type '#{arguments.class}' but should be '#{expected_type}'"
      end
    end
    nil
  end

  # Get JSON schema type for a Ruby value
  #
  # @param value [Object] The value to get type for
  # @return [String] The JSON schema type
  def self.get_json_schema_type(value)
    case value
    when String then "string"
    when Integer then "integer"
    when Float then "number"
    when TrueClass, FalseClass then "boolean"
    when Array then "array"
    when Hash then "object"
    when NilClass then "null"
    when AgentImage then "image"
    when AgentAudio then "audio"
    else "any"
    end
  end

  # Generate tool definition code for use in prompts
  #
  # @param tools [Hash<String, Tool>] Tools keyed by name
  # @return [String] Ruby code defining the tools
  def self.get_tools_definition_code(tools)
    tool_codes = tools.values.map do |tool|
      <<~RUBY
        class #{tool.class.name.split("::").last} < Tool
          self.tool_name = #{tool.name.inspect}
          self.tool_description = #{tool.description.inspect}
          self.input_schema = #{tool.inputs.inspect}
          self.output_type = #{tool.output_type.inspect}

          def call(*args, **kwargs)
            forward(*args, **kwargs)
          end

          def forward(*args, **kwargs)
            # Implementation
          end
        end

        #{tool.name} = #{tool.class.name.split("::").last}.new
      RUBY
    end

    base_code = <<~RUBY
      class Tool
        def call(*args, **kwargs)
          forward(*args, **kwargs)
        end

        def forward(*args, **kwargs)
          # to be implemented in child class
        end
      end
    RUBY

    base_code + "\n\n" + tool_codes.join("\n\n")
  end
end
