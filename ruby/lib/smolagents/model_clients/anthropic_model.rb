# frozen_string_literal: true

module Smolagents
  # Anthropic Claude model implementation.
  #
  # This model connects to Anthropic's Claude API.
  #
  # @example
  #   model = AnthropicModel.new(
  #     model_id: "claude-3-opus-20240229",
  #     api_key: ENV["ANTHROPIC_API_KEY"]
  #   )
  #   response = model.generate([ChatMessage.user("Hello!")])
  #
  class AnthropicModel < ApiModel
    # @return [Hash] Client configuration
    attr_reader :client_kwargs

    # @return [Integer] Maximum tokens to generate
    attr_accessor :max_tokens

    # Create a new AnthropicModel
    #
    # @param model_id [String] Model identifier (e.g., "claude-3-opus-20240229")
    # @param api_key [String, nil] API key for authentication
    # @param max_tokens [Integer] Maximum tokens to generate
    # @param client_kwargs [Hash, nil] Additional client options
    # @param custom_role_conversions [Hash, nil] Custom role mappings
    # @param kwargs [Hash] Additional arguments
    def initialize(
      model_id: "claude-3-5-sonnet-20241022",
      api_key: nil,
      max_tokens: 4096,
      client_kwargs: nil,
      custom_role_conversions: nil,
      **kwargs
    )
      @client_kwargs = {
        **(client_kwargs || {}),
        api_key: api_key || ENV["ANTHROPIC_API_KEY"]
      }.compact

      @max_tokens = max_tokens

      # Anthropic requires converting system messages
      custom_role_conversions ||= {}

      super(
        model_id: model_id,
        custom_role_conversions: custom_role_conversions,
        flatten_messages_as_text: false,
        **kwargs
      )
    end

    # Create the Anthropic client
    # @return [Object] Anthropic client
    def create_client
      begin
        require "anthropic"
      rescue LoadError
        raise LoadError, "Please install the 'anthropic' gem to use AnthropicModel"
      end

      Anthropic::Client.new(**@client_kwargs)
    end

    # Generate a response from the model
    #
    # @param messages [Array<ChatMessage, Hash>] Input messages
    # @param stop_sequences [Array<String>, nil] Stop sequences
    # @param response_format [Hash, nil] Response format
    # @param tools_to_call_from [Array<Tool>, nil] Available tools
    # @param kwargs [Hash] Additional arguments
    # @return [ChatMessage] Model response
    def generate(messages, stop_sequences: nil, response_format: nil, tools_to_call_from: nil, **kwargs)
      # Extract system message
      system_message = nil
      filtered_messages = []

      clean_messages = Smolagents.get_clean_message_list(
        messages,
        role_conversions: @custom_role_conversions,
        convert_images_to_image_urls: false,
        flatten_messages_as_text: false
      )

      clean_messages.each do |msg|
        if msg[:role] == MessageRole::SYSTEM || msg[:role] == "system"
          system_message = msg[:content].is_a?(Array) ? msg[:content].first&.dig(:text) : msg[:content]
        else
          # Convert content format for Anthropic
          content = if msg[:content].is_a?(Array)
                      msg[:content].map do |c|
                        if c[:type] == "text"
                          { type: "text", text: c[:text] }
                        elsif c[:type] == "image" || c[:type] == "image_url"
                          # Handle image content
                          { type: "text", text: "[Image]" }
                        else
                          c
                        end
                      end
                    else
                      msg[:content]
                    end

          filtered_messages << { role: msg[:role], content: content }
        end
      end

      apply_rate_limit

      request_params = {
        model: @model_id,
        max_tokens: kwargs[:max_tokens] || @max_tokens,
        messages: filtered_messages
      }

      request_params[:system] = system_message if system_message
      request_params[:stop_sequences] = stop_sequences if stop_sequences

      # Add tools if provided
      if tools_to_call_from&.any?
        request_params[:tools] = tools_to_call_from.map do |tool|
          {
            name: tool.name,
            description: tool.description,
            input_schema: {
              type: "object",
              properties: tool.inputs.transform_keys(&:to_s),
              required: tool.inputs.keys.map(&:to_s).reject { |k| tool.inputs[k.to_sym][:nullable] }
            }
          }
        end
      end

      response = @retryer.call do
        @client.messages(parameters: request_params)
      end

      content_blocks = response["content"] || []
      text_content = content_blocks.find { |b| b["type"] == "text" }
      content = text_content ? text_content["text"] : nil

      if stop_sequences && !supports_stop_parameter?
        content = Smolagents.remove_content_after_stop_sequences(content, stop_sequences)
      end

      usage = response["usage"] || {}

      # Handle tool use
      tool_calls = nil
      tool_use_blocks = content_blocks.select { |b| b["type"] == "tool_use" }
      if tool_use_blocks.any?
        tool_calls = tool_use_blocks.map do |tc|
          ChatMessageToolCall.new(
            id: tc["id"],
            type: "function",
            function: ChatMessageToolCallFunction.new(
              name: tc["name"],
              arguments: tc["input"]
            )
          )
        end
      end

      ChatMessage.new(
        role: MessageRole::ASSISTANT,
        content: content ? [{ type: "text", text: content }] : nil,
        tool_calls: tool_calls,
        raw: response,
        token_usage: TokenUsage.new(
          input_tokens: usage["input_tokens"] || 0,
          output_tokens: usage["output_tokens"] || 0
        )
      )
    end

    # Generate a streaming response
    #
    # @param messages [Array<ChatMessage, Hash>] Input messages
    # @param stop_sequences [Array<String>, nil] Stop sequences
    # @param response_format [Hash, nil] Response format
    # @param tools_to_call_from [Array<Tool>, nil] Available tools
    # @param kwargs [Hash] Additional arguments
    # @return [Enumerator<ChatMessageStreamDelta>] Stream of deltas
    def generate_stream(messages, stop_sequences: nil, response_format: nil, tools_to_call_from: nil, **kwargs)
      # Extract system message
      system_message = nil
      filtered_messages = []

      clean_messages = Smolagents.get_clean_message_list(
        messages,
        role_conversions: @custom_role_conversions,
        convert_images_to_image_urls: false,
        flatten_messages_as_text: false
      )

      clean_messages.each do |msg|
        if msg[:role] == MessageRole::SYSTEM || msg[:role] == "system"
          system_message = msg[:content].is_a?(Array) ? msg[:content].first&.dig(:text) : msg[:content]
        else
          content = if msg[:content].is_a?(Array)
                      msg[:content].map do |c|
                        c[:type] == "text" ? { type: "text", text: c[:text] } : c
                      end
                    else
                      msg[:content]
                    end
          filtered_messages << { role: msg[:role], content: content }
        end
      end

      apply_rate_limit

      request_params = {
        model: @model_id,
        max_tokens: kwargs[:max_tokens] || @max_tokens,
        messages: filtered_messages,
        stream: true
      }

      request_params[:system] = system_message if system_message
      request_params[:stop_sequences] = stop_sequences if stop_sequences

      Enumerator.new do |yielder|
        @retryer.call do
          @client.messages(parameters: request_params) do |event|
            case event["type"]
            when "content_block_delta"
              delta = event.dig("delta", "text")
              yielder << ChatMessageStreamDelta.new(content: delta) if delta
            when "message_delta"
              usage = event.dig("usage")
              if usage
                yielder << ChatMessageStreamDelta.new(
                  token_usage: TokenUsage.new(
                    input_tokens: 0,
                    output_tokens: usage["output_tokens"] || 0
                  )
                )
              end
            end
          end
        end
      end
    end
  end
end
