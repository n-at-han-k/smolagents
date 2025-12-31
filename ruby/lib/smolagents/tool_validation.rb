# frozen_string_literal: true

module Smolagents
  # Tool validation utilities.
  #
  # This module provides methods for validating that Tool classes
  # follow proper patterns and conventions.
  module ToolValidation
    # Reserved Ruby keywords that cannot be used as identifiers
    RESERVED_KEYWORDS = %w[
      BEGIN END alias and begin break case class def defined? do else elsif end
      ensure false for if in module next nil not or redo rescue retry return self
      super then true undef unless until when while yield __FILE__ __LINE__ __ENCODING__
    ].freeze

    # Validate that a name is a valid Ruby identifier
    #
    # @param name [String] The name to validate
    # @return [Boolean] Whether the name is valid
    def self.valid_name?(name)
      return false if name.nil? || name.empty?
      return false unless name.match?(/\A[a-z_][a-zA-Z0-9_]*\z/)
      return false if RESERVED_KEYWORDS.include?(name)

      true
    end

    # Validate a Tool class
    #
    # @param tool_class [Class] The Tool class to validate
    # @raise [ValidationError] If validation fails
    # @return [nil] If validation succeeds
    def self.validate_tool_class(tool_class)
      errors = []

      # Check it's a Tool subclass
      unless tool_class < Tool
        errors << "Class must be a subclass of Tool"
      end

      # Check required class attributes
      %i[tool_name tool_description input_schema output_type].each do |attr|
        value = tool_class.send(attr) rescue nil
        if value.nil?
          errors << "Missing required class attribute: #{attr}"
        end
      end

      # Validate tool_name
      tool_name = tool_class.tool_name rescue nil
      if tool_name
        unless tool_name.is_a?(String)
          errors << "tool_name must be a String, got #{tool_name.class}"
        end
        unless valid_name?(tool_name)
          errors << "tool_name '#{tool_name}' is not a valid identifier or is a reserved keyword"
        end
      end

      # Validate tool_description
      description = tool_class.tool_description rescue nil
      if description && !description.is_a?(String)
        errors << "tool_description must be a String, got #{description.class}"
      end

      # Validate input_schema
      input_schema = tool_class.input_schema rescue nil
      if input_schema
        unless input_schema.is_a?(Hash)
          errors << "input_schema must be a Hash, got #{input_schema.class}"
        else
          validate_input_schema(input_schema, errors)
        end
      end

      # Validate output_type
      output_type = tool_class.output_type rescue nil
      if output_type
        unless output_type.is_a?(String)
          errors << "output_type must be a String, got #{output_type.class}"
        end
        unless AUTHORIZED_TYPES.include?(output_type)
          errors << "output_type '#{output_type}' must be one of #{AUTHORIZED_TYPES}"
        end
      end

      # Check that call or forward method is defined
      unless tool_class.instance_methods(false).include?(:forward) ||
             tool_class.instance_methods(false).include?(:call)
        errors << "Tool must implement either #forward or #call method"
      end

      unless errors.empty?
        raise ValidationError.new(
          "Tool validation failed for #{tool_class.name}:\n" + errors.map { |e| "- #{e}" }.join("\n")
        )
      end

      nil
    end

    # Validate input schema structure
    #
    # @param schema [Hash] The input schema
    # @param errors [Array] Array to append errors to
    def self.validate_input_schema(schema, errors)
      schema.each do |name, config|
        unless config.is_a?(Hash)
          errors << "Input '#{name}' configuration must be a Hash"
          next
        end

        unless config.key?(:type)
          errors << "Input '#{name}' is missing required :type key"
        end

        unless config.key?(:description)
          errors << "Input '#{name}' is missing required :description key"
        end

        if config.key?(:type)
          input_type = config[:type]
          types = Array(input_type)

          types.each do |t|
            unless t.is_a?(String)
              errors << "Input '#{name}': type must be a string, got #{t.class}"
            end
            unless AUTHORIZED_TYPES.include?(t)
              errors << "Input '#{name}': type '#{t}' must be one of #{AUTHORIZED_TYPES}"
            end
          end
        end
      end
    end

    # Validate a tool instance
    #
    # @param tool [Tool] The tool instance to validate
    # @raise [ValidationError] If validation fails
    # @return [nil] If validation succeeds
    def self.validate_tool_instance(tool)
      validate_tool_class(tool.class)

      # Additional instance-level validations could go here
      nil
    end

    # Validate arguments against a tool's input schema
    #
    # @param tool [Tool] The tool to validate against
    # @param arguments [Hash] The arguments to validate
    # @raise [ValidationError] If validation fails
    # @return [nil] If validation succeeds
    def self.validate_arguments(tool, arguments)
      errors = []
      schema = tool.inputs

      # Check for unknown arguments
      arguments.each_key do |key|
        key_sym = key.to_sym
        unless schema.key?(key_sym)
          errors << "Unknown argument: #{key}. Expected one of: #{schema.keys.join(', ')}"
        end
      end

      # Check required arguments
      schema.each do |name, config|
        required = !config[:nullable] && !config.key?(:default)
        if required && !arguments.key?(name) && !arguments.key?(name.to_s)
          errors << "Missing required argument: #{name}"
        end
      end

      # Validate argument types
      arguments.each do |name, value|
        name_sym = name.to_sym
        next unless schema.key?(name_sym)

        expected_type = schema[name_sym][:type]
        actual_type = get_json_type(value)

        types = Array(expected_type)
        type_valid = types.any? do |t|
          t == "any" ||
            actual_type == t ||
            (actual_type == "integer" && t == "number") ||
            (actual_type == "null" && schema[name_sym][:nullable])
        end

        unless type_valid
          errors << "Argument '#{name}' has type '#{actual_type}', expected '#{expected_type}'"
        end
      end

      unless errors.empty?
        raise ValidationError.new("Argument validation failed:\n" + errors.map { |e| "- #{e}" }.join("\n"))
      end

      nil
    end

    # Get JSON schema type for a Ruby value
    #
    # @param value [Object] The value to get type for
    # @return [String] The JSON schema type
    def self.get_json_type(value)
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
  end

  # Custom validation error
  class ValidationError < AgentError
    def initialize(message, logger = nil)
      super(message, logger)
    end
  end
end
