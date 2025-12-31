# frozen_string_literal: true

module Smolagents
  # Authorized types for tool inputs and outputs
  AUTHORIZED_TYPES = %w[
    string
    boolean
    integer
    number
    image
    audio
    array
    object
    any
    null
  ].freeze

  # Conversion dictionary for type mapping
  CONVERSION_DICT = {
    "String" => "string",
    "Integer" => "integer",
    "Float" => "number",
    "TrueClass" => "boolean",
    "FalseClass" => "boolean",
    "Array" => "array",
    "Hash" => "object",
    "NilClass" => "null"
  }.freeze

  # A base class for tools used by agents.
  #
  # To create a tool, subclass this and set the following class attributes:
  # - `tool_name` - A performative name for the tool
  # - `tool_description` - A short description of what the tool does
  # - `input_schema` - A hash defining the expected inputs
  # - `output_type` - The type of output the tool returns
  #
  # Then implement the `call` method with your tool's logic.
  #
  # @example Creating a weather tool
  #   class GetWeatherTool < Smolagents::Tool
  #     self.tool_name = "get_weather"
  #     self.tool_description = "Get weather at a given location"
  #     self.input_schema = {
  #       location: { type: "string", description: "The city to check weather for" },
  #       celsius: { type: "boolean", description: "Use Celsius", default: true }
  #     }
  #     self.output_type = "string"
  #
  #     def call(location:, celsius: true)
  #       # Implementation here
  #       "Weather in #{location}: sunny, 22°#{celsius ? 'C' : 'F'}"
  #     end
  #   end
  #
  class Tool < BaseTool
    class << self
      # The tool's name
      attr_accessor :tool_name

      # A description of what the tool does
      attr_accessor :tool_description

      # The input schema defining expected arguments
      # @return [Hash<Symbol, Hash>]
      attr_accessor :input_schema

      # The type of output the tool returns
      attr_accessor :output_type

      # Optional JSON schema for structured output
      attr_accessor :output_schema

      # Skip forward signature validation for wrapper tools
      attr_accessor :skip_forward_signature_validation
    end

    # Whether the tool has been initialized/setup
    # @return [Boolean]
    attr_accessor :is_initialized

    def initialize(**kwargs)
      @is_initialized = false
      validate_arguments
    end

    # Get the tool name
    # @return [String]
    def name
      self.class.tool_name || self.class.name.split("::").last.gsub(/Tool$/, "").downcase
    end

    # Get the tool description
    # @return [String]
    def description
      self.class.tool_description || ""
    end

    # Get the input schema
    # @return [Hash]
    def inputs
      self.class.input_schema || {}
    end

    # Get the output type
    # @return [String]
    def output_type
      self.class.output_type || "string"
    end

    # Get the output schema
    # @return [Hash, nil]
    def output_schema
      self.class.output_schema
    end

    # Validate that the tool has all required attributes
    def validate_arguments
      required_attributes = {
        tool_description: String,
        tool_name: String,
        input_schema: Hash,
        output_type: String
      }

      required_attributes.each do |attr, expected_type|
        value = self.class.send(attr)
        if value.nil?
          raise TypeError, "You must set the class attribute `#{attr}`."
        end
        unless value.is_a?(expected_type)
          raise TypeError,
                "Attribute #{attr} should be #{expected_type}, got #{value.class} instead."
        end
      end

      # Validate name is a valid identifier
      unless valid_name?(name)
        raise ArgumentError,
              "Invalid Tool name '#{name}': must be a valid identifier and not a reserved keyword"
      end

      # Validate inputs
      inputs.each do |input_name, input_content|
        unless input_content.is_a?(Hash)
          raise ArgumentError, "Input '#{input_name}' should be a Hash."
        end
        unless input_content.key?(:type) && input_content.key?(:description)
          raise ArgumentError,
                "Input '#{input_name}' should have keys :type and :description, has only #{input_content.keys}."
        end

        input_types = Array(input_content[:type])
        unless input_types.all? { |t| t.is_a?(String) }
          raise TypeError,
                "Input '#{input_name}': type must be a string or array of strings"
        end

        invalid_types = input_types - AUTHORIZED_TYPES
        unless invalid_types.empty?
          raise ValueError,
                "Input '#{input_name}': types #{invalid_types} must be one of #{AUTHORIZED_TYPES}"
        end
      end

      # Validate output type
      unless AUTHORIZED_TYPES.include?(output_type)
        raise ArgumentError, "Output type '#{output_type}' must be one of #{AUTHORIZED_TYPES}"
      end

      # Validate output_schema if present
      if self.class.output_schema && !self.class.output_schema.is_a?(Hash)
        raise TypeError, "Attribute output_schema should be a Hash, got #{self.class.output_schema.class}"
      end
    end

    # Execute the tool
    #
    # @param args [Array] Positional arguments
    # @param sanitize_inputs_outputs [Boolean] Whether to convert agent types
    # @param kwargs [Hash] Keyword arguments
    # @return [Object] Tool result
    def call(*args, sanitize_inputs_outputs: false, **kwargs)
      setup unless @is_initialized

      # Handle case where a single hash is passed as the only argument
      if args.length == 1 && kwargs.empty? && args[0].is_a?(Hash)
        potential_kwargs = args[0]
        if potential_kwargs.keys.all? { |k| inputs.key?(k.to_sym) || inputs.key?(k.to_s) }
          args = []
          kwargs = potential_kwargs.transform_keys(&:to_sym)
        end
      end

      if sanitize_inputs_outputs
        args, kwargs = handle_agent_input_types(*args, **kwargs)
      end

      outputs = forward(*args, **kwargs)

      if sanitize_inputs_outputs
        outputs = handle_agent_output_types(outputs, output_type)
      end

      outputs
    end

    # Implement the tool's logic in this method.
    #
    # @abstract
    def forward(*args, **kwargs)
      raise NotImplementedError, "Implement this method in your Tool subclass."
    end

    # Optional setup method for expensive operations.
    # Called automatically on first use.
    def setup
      @is_initialized = true
    end

    # Generate a code-style prompt representation of this tool.
    #
    # @return [String]
    def to_code_prompt
      args_signature = inputs.map do |arg_name, arg_schema|
        "#{arg_name}: #{arg_schema[:type]}"
      end.join(", ")

      has_schema = !output_schema.nil?
      out_type = has_schema ? "dict" : output_type
      tool_signature = "(#{args_signature}) -> #{out_type}"
      tool_doc = description.dup

      if has_schema
        tool_doc += "\n\nImportant: This tool returns structured output! " \
                    "Use the JSON schema below to directly access fields like result['field_name']. " \
                    "NO print() statements needed to inspect the output!"
      end

      if inputs.any?
        args_descriptions = inputs.map do |arg_name, arg_schema|
          "#{arg_name}: #{arg_schema[:description]}"
        end.join("\n")
        args_doc = "Args:\n#{indent(args_descriptions, 4)}"
        tool_doc += "\n\n#{args_doc}"
      end

      if has_schema
        require "json"
        formatted_schema = JSON.pretty_generate(output_schema)
        indented_schema = indent(formatted_schema, 8)
        returns_doc = "\nReturns:\n    dict (structured output): This tool ALWAYS returns a dictionary " \
                      "that strictly adheres to the following JSON schema:\n#{indented_schema}"
        tool_doc += "\n#{returns_doc}"
      end

      tool_doc = "\"\"\"#{tool_doc}\n\"\"\""
      "def #{name}#{tool_signature}:\n#{indent(tool_doc, 4)}"
    end

    # Generate a tool-calling style prompt representation.
    #
    # @return [String]
    def to_tool_calling_prompt
      "#{name}: #{description}\n    Takes inputs: #{inputs}\n    Returns an output of type: #{output_type}"
    end

    # Convert the tool to a dictionary representation.
    #
    # @return [Hash]
    def to_h
      result = {
        name: name,
        description: description,
        inputs: inputs,
        output_type: output_type
      }
      result[:output_schema] = output_schema if output_schema
      result
    end

    alias to_hash to_h

    # Convert tool to JSON schema format for API calls
    #
    # @return [Hash]
    def to_json_schema
      properties = {}
      required = []

      inputs.each do |input_name, input_content|
        prop = {
          "type" => input_content[:type],
          "description" => input_content[:description]
        }

        if input_content[:default].nil? && !input_content[:nullable]
          required << input_name.to_s
        end

        properties[input_name.to_s] = prop
      end

      {
        "type" => "function",
        "function" => {
          "name" => name,
          "description" => description,
          "parameters" => {
            "type" => "object",
            "properties" => properties,
            "required" => required
          }
        }
      }
    end

    private

    def valid_name?(name)
      return false if name.nil? || name.empty?

      # Check it's a valid Ruby identifier
      return false unless name.match?(/\A[a-z_][a-zA-Z0-9_]*\z/)

      # Check it's not a reserved keyword
      reserved = %w[
        BEGIN END alias and begin break case class def defined? do else elsif end
        ensure false for if in module next nil not or redo rescue retry return self
        super then true undef unless until when while yield __FILE__ __LINE__ __ENCODING__
      ]
      !reserved.include?(name)
    end

    def indent(text, spaces)
      prefix = " " * spaces
      text.lines.map { |line| "#{prefix}#{line}" }.join
    end

    def handle_agent_input_types(*args, **kwargs)
      # Convert AgentType objects to raw values
      converted_args = args.map { |arg| arg.respond_to?(:to_raw) ? arg.to_raw : arg }
      converted_kwargs = kwargs.transform_values { |v| v.respond_to?(:to_raw) ? v.to_raw : v }
      [converted_args, converted_kwargs]
    end

    def handle_agent_output_types(output, output_type)
      case output_type
      when "text", "string"
        AgentText.new(output.to_s)
      when "image"
        AgentImage.new(output)
      when "audio"
        AgentAudio.new(output)
      else
        output
      end
    end
  end
end
