# frozen_string_literal: true

module Smolagents
  # Retry configuration constants
  RETRY_WAIT = 60
  RETRY_MAX_ATTEMPTS = 3
  RETRY_EXPONENTIAL_BASE = 2
  RETRY_JITTER = true

  # Role conversions for tool calls
  TOOL_ROLE_CONVERSIONS = {
    MessageRole::TOOL_CALL => MessageRole::ASSISTANT,
    MessageRole::TOOL_RESPONSE => MessageRole::USER
  }.freeze

  # Base class for all language model implementations.
  #
  # This abstract class defines the core interface that all model implementations
  # must follow to work with agents.
  #
  # @abstract Subclass and implement {#generate}
  #
  # @example Creating a custom model
  #   class CustomModel < Smolagents::Model
  #     def generate(messages, **kwargs)
  #       # Implementation specific to your model
  #     end
  #   end
  #
  class Model
    # @return [Boolean] Whether to flatten messages as text
    attr_accessor :flatten_messages_as_text

    # @return [String] Key for extracting tool names
    attr_accessor :tool_name_key

    # @return [String] Key for extracting tool arguments
    attr_accessor :tool_arguments_key

    # @return [Hash] Additional kwargs for model calls
    attr_accessor :kwargs

    # @return [String, nil] Model identifier
    attr_accessor :model_id

    # Create a new Model
    #
    # @param flatten_messages_as_text [Boolean] Flatten complex messages to text
    # @param tool_name_key [String] Key for tool names in responses
    # @param tool_arguments_key [String] Key for tool arguments in responses
    # @param model_id [String, nil] Model identifier
    # @param kwargs [Hash] Additional arguments for model calls
    def initialize(
      flatten_messages_as_text: false,
      tool_name_key: "name",
      tool_arguments_key: "arguments",
      model_id: nil,
      **kwargs
    )
      @flatten_messages_as_text = flatten_messages_as_text
      @tool_name_key = tool_name_key
      @tool_arguments_key = tool_arguments_key
      @kwargs = kwargs
      @model_id = model_id
    end

    # Check if model supports stop parameter
    # @return [Boolean]
    def supports_stop_parameter?
      Smolagents.supports_stop_parameter(@model_id || "")
    end

    # Prepare completion kwargs for model call
    #
    # @param messages [Array<ChatMessage, Hash>] Messages to process
    # @param stop_sequences [Array<String>, nil] Stop sequences
    # @param response_format [Hash, nil] Response format specification
    # @param tools_to_call_from [Array<Tool>, nil] Available tools
    # @param custom_role_conversions [Hash, nil] Custom role mappings
    # @param convert_images_to_image_urls [Boolean] Convert images to URLs
    # @param tool_choice [String, Hash, nil] Tool choice setting
    # @param kwargs [Hash] Additional arguments
    # @return [Hash] Prepared completion kwargs
    def prepare_completion_kwargs(
      messages:,
      stop_sequences: nil,
      response_format: nil,
      tools_to_call_from: nil,
      custom_role_conversions: nil,
      convert_images_to_image_urls: false,
      tool_choice: "required",
      **kwargs
    )
      flatten_text = kwargs.delete(:flatten_messages_as_text) || @flatten_messages_as_text

      messages_as_dicts = Smolagents.get_clean_message_list(
        messages,
        role_conversions: custom_role_conversions || TOOL_ROLE_CONVERSIONS,
        convert_images_to_image_urls: convert_images_to_image_urls,
        flatten_messages_as_text: flatten_text
      )

      completion_kwargs = { messages: messages_as_dicts }

      if stop_sequences && supports_stop_parameter?
        completion_kwargs[:stop] = stop_sequences
      end

      completion_kwargs[:response_format] = response_format if response_format

      if tools_to_call_from&.any?
        completion_kwargs[:tools] = tools_to_call_from.map { |t| Smolagents.get_tool_json_schema(t) }
        completion_kwargs[:tool_choice] = tool_choice if tool_choice
      end

      completion_kwargs.merge!(kwargs)
      completion_kwargs.merge!(@kwargs)

      completion_kwargs
    end

    # Process messages and return model response.
    #
    # @abstract
    # @param messages [Array<ChatMessage>] Input messages
    # @param stop_sequences [Array<String>, nil] Stop sequences
    # @param response_format [Hash, nil] Response format
    # @param tools_to_call_from [Array<Tool>, nil] Available tools
    # @param kwargs [Hash] Additional arguments
    # @return [ChatMessage] Model response
    def generate(messages, stop_sequences: nil, response_format: nil, tools_to_call_from: nil, **kwargs)
      raise NotImplementedError, "Subclasses must implement #generate"
    end

    # Call the model (alias for generate)
    def call(*args, **kwargs)
      generate(*args, **kwargs)
    end

    # Parse tool calls from message content
    #
    # @param message [ChatMessage] Message to parse
    # @return [ChatMessage] Message with tool_calls populated
    def parse_tool_calls(message)
      message.role = MessageRole::ASSISTANT

      unless message.tool_calls
        raise ArgumentError, "Message contains no content and no tool calls" unless message.content

        message.tool_calls = [
          Smolagents.get_tool_call_from_text(
            message.content.to_s,
            @tool_name_key,
            @tool_arguments_key
          )
        ]
      end

      raise "No tool call was found in the model output" if message.tool_calls.empty?

      message.tool_calls.each do |tool_call|
        tool_call.function.arguments = Smolagents.parse_json_if_needed(tool_call.function.arguments)
      end

      message
    end

    # Convert model to hash representation
    # @return [Hash]
    def to_h
      result = @kwargs.merge(model_id: @model_id)

      %i[custom_role_conversion temperature max_tokens provider timeout api_base
         torch_dtype device_map organization project azure_endpoint].each do |attr|
        result[attr] = send(attr) if respond_to?(attr)
      end

      # Don't include sensitive attributes
      %i[token api_key].each do |attr|
        if respond_to?(attr)
          puts "For security reasons, we do not export the `#{attr}` attribute. Please export it manually."
        end
      end

      result
    end

    # Create model from hash
    # @param model_dictionary [Hash] Model configuration
    # @return [Model]
    def self.from_h(model_dictionary)
      new(**model_dictionary.transform_keys(&:to_sym))
    end
  end

  # Helper module methods
  module_function

  # Check if model supports stop parameter
  # @param model_id [String] Model identifier
  # @return [Boolean]
  def supports_stop_parameter(model_id)
    model_name = model_id.split("/").last.to_s
    return true if model_name == "o3-mini"

    # o3*, o4*, gpt-5*, and grok-* don't support stop parameter
    pattern = /^(o3(?:$|[-.].*)|o4(?:$|[-.].*)|gpt-5.*|([A-Za-z][A-Za-z0-9_-]*\.)?grok-[A-Za-z0-9][A-Za-z0-9_.-]*)$/
    !model_name.match?(pattern)
  end

  # Get clean message list for LLM
  # @param message_list [Array<ChatMessage, Hash>] Messages to clean
  # @param role_conversions [Hash] Role conversion mapping
  # @param convert_images_to_image_urls [Boolean] Convert images to URLs
  # @param flatten_messages_as_text [Boolean] Flatten messages as text
  # @return [Array<Hash>]
  def get_clean_message_list(
    message_list,
    role_conversions: {},
    convert_images_to_image_urls: false,
    flatten_messages_as_text: false
  )
    output = []
    message_list = message_list.map { |m| m.is_a?(Hash) ? ChatMessage.from_h(m) : m }

    message_list.each do |message|
      role = message.role

      unless MessageRole.valid?(role)
        raise ArgumentError, "Incorrect role #{role}, only #{MessageRole.roles} are supported"
      end

      message.role = role_conversions[role] if role_conversions.key?(role)

      # Process content
      if message.content.is_a?(Array)
        message.content.each do |element|
          next unless element.is_a?(Hash) && element[:type] == "image"

          if flatten_messages_as_text
            raise ArgumentError, "Cannot use images with flatten_messages_as_text=true"
          end

          if convert_images_to_image_urls
            element[:type] = "image_url"
            element[:image_url] = { url: Smolagents.make_image_url(Smolagents.encode_image_base64(element.delete(:image))) }
          else
            element[:image] = Smolagents.encode_image_base64(element[:image])
          end
        end
      end

      # Merge consecutive messages with same role
      if output.any? && message.role == output.last[:role]
        if flatten_messages_as_text
          output.last[:content] += "\n" + message.content.first[:text].to_s
        else
          message.content.each do |el|
            if el[:type] == "text" && output.last[:content].last&.dig(:type) == "text"
              output.last[:content].last[:text] += "\n" + el[:text].to_s
            else
              output.last[:content] << el
            end
          end
        end
      else
        content = flatten_messages_as_text ? message.content&.first&.dig(:text) : message.content
        output << { role: message.role, content: content }
      end
    end

    output
  end

  # Get tool JSON schema for API calls
  # @param tool [Tool] Tool to convert
  # @return [Hash] JSON schema representation
  def get_tool_json_schema(tool)
    properties = tool.inputs.transform_values(&:dup)
    required = []

    properties.each do |key, value|
      value[:type] = "string" if value[:type] == "any"
      required << key.to_s unless value[:nullable] || value.key?(:default)
    end

    {
      type: "function",
      function: {
        name: tool.name,
        description: tool.description,
        parameters: {
          type: "object",
          properties: properties.transform_keys(&:to_s),
          required: required
        }
      }
    }
  end

  # Extract tool call from text
  # @param text [String] Text containing tool call
  # @param tool_name_key [String] Key for tool name
  # @param tool_arguments_key [String] Key for tool arguments
  # @return [ChatMessageToolCall]
  def get_tool_call_from_text(text, tool_name_key, tool_arguments_key)
    require "json"
    tool_call_dict = JSON.parse(text)

    tool_name = tool_call_dict[tool_name_key]
    unless tool_name
      raise ArgumentError, "Tool call needs key '#{tool_name_key}'. Got: #{tool_call_dict.keys}"
    end

    tool_arguments = tool_call_dict[tool_arguments_key]
    tool_arguments = parse_json_if_needed(tool_arguments) if tool_arguments.is_a?(String)

    ChatMessageToolCall.new(
      id: SecureRandom.uuid,
      type: "function",
      function: ChatMessageToolCallFunction.new(name: tool_name, arguments: tool_arguments)
    )
  end

  # Parse JSON if value is a string
  # @param value [String, Hash] Value to parse
  # @return [String, Hash]
  def parse_json_if_needed(value)
    return value if value.is_a?(Hash)

    require "json"
    JSON.parse(value)
  rescue JSON::ParserError
    value
  end

  # Remove content after stop sequences
  # @param content [String, nil] Content to process
  # @param stop_sequences [Array<String>, nil] Stop sequences
  # @return [String, nil]
  def remove_content_after_stop_sequences(content, stop_sequences)
    return content if content.nil? || stop_sequences.nil? || stop_sequences.empty?

    stop_sequences.each do |stop_seq|
      content = content.split(stop_seq).first
    end
    content
  end

  # Encode image to base64
  # @param image [String, Object] Image path or data
  # @return [String] Base64 encoded string
  def encode_image_base64(image)
    require "base64"

    if image.is_a?(String) && File.exist?(image)
      Base64.strict_encode64(File.binread(image))
    elsif image.respond_to?(:to_raw)
      Base64.strict_encode64(image.to_raw)
    else
      image.to_s
    end
  end

  # Make image URL from base64 data
  # @param base64_data [String] Base64 encoded image
  # @return [String] Data URL
  def make_image_url(base64_data)
    "data:image/png;base64,#{base64_data}"
  end
end
