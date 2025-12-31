# frozen_string_literal: true

module Smolagents
  # OpenAI-compatible API model.
  #
  # This model connects to an OpenAI-compatible API server.
  #
  # @example
  #   model = OpenAIModel.new(
  #     model_id: "gpt-4",
  #     api_key: ENV["OPENAI_API_KEY"]
  #   )
  #   response = model.generate([ChatMessage.user("Hello!")])
  #
  class OpenAIModel < ApiModel
    # @return [Hash] Client configuration
    attr_reader :client_kwargs

    # Create a new OpenAIModel
    #
    # @param model_id [String] Model identifier (e.g., "gpt-4")
    # @param api_base [String, nil] Base URL for the API
    # @param api_key [String, nil] API key for authentication
    # @param organization [String, nil] Organization ID
    # @param project [String, nil] Project ID
    # @param client_kwargs [Hash, nil] Additional client options
    # @param custom_role_conversions [Hash, nil] Custom role mappings
    # @param flatten_messages_as_text [Boolean] Flatten messages as text
    # @param kwargs [Hash] Additional arguments
    def initialize(
      model_id:,
      api_base: nil,
      api_key: nil,
      organization: nil,
      project: nil,
      client_kwargs: nil,
      custom_role_conversions: nil,
      flatten_messages_as_text: false,
      **kwargs
    )
      @client_kwargs = {
        **(client_kwargs || {}),
        api_key: api_key,
        base_url: api_base,
        organization: organization,
        project: project
      }.compact

      super(
        model_id: model_id,
        custom_role_conversions: custom_role_conversions,
        flatten_messages_as_text: flatten_messages_as_text,
        **kwargs
      )
    end

    # Create the OpenAI client
    # @return [Object] OpenAI client
    def create_client
      begin
        require "openai"
      rescue LoadError
        raise LoadError, "Please install the 'ruby-openai' gem to use OpenAIModel"
      end

      OpenAI::Client.new(**@client_kwargs)
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
      completion_kwargs = prepare_completion_kwargs(
        messages: messages,
        stop_sequences: stop_sequences,
        response_format: response_format,
        tools_to_call_from: tools_to_call_from,
        custom_role_conversions: @custom_role_conversions,
        convert_images_to_image_urls: true,
        **kwargs
      )

      completion_kwargs[:model] = @model_id

      apply_rate_limit

      response = @retryer.call do
        @client.chat(parameters: completion_kwargs)
      end

      choice = response.dig("choices", 0)
      message_data = choice&.dig("message") || {}
      content = message_data["content"]

      if stop_sequences && !supports_stop_parameter?
        content = Smolagents.remove_content_after_stop_sequences(content, stop_sequences)
      end

      usage = response["usage"] || {}

      tool_calls = nil
      if message_data["tool_calls"]
        tool_calls = message_data["tool_calls"].map do |tc|
          ChatMessageToolCall.new(
            id: tc["id"],
            type: tc["type"],
            function: ChatMessageToolCallFunction.new(
              name: tc.dig("function", "name"),
              arguments: tc.dig("function", "arguments")
            )
          )
        end
      end

      ChatMessage.new(
        role: message_data["role"] || MessageRole::ASSISTANT,
        content: content ? [{ type: "text", text: content }] : nil,
        tool_calls: tool_calls,
        raw: response,
        token_usage: TokenUsage.new(
          input_tokens: usage["prompt_tokens"] || 0,
          output_tokens: usage["completion_tokens"] || 0
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
      completion_kwargs = prepare_completion_kwargs(
        messages: messages,
        stop_sequences: stop_sequences,
        response_format: response_format,
        tools_to_call_from: tools_to_call_from,
        custom_role_conversions: @custom_role_conversions,
        convert_images_to_image_urls: true,
        **kwargs
      )

      completion_kwargs[:model] = @model_id
      completion_kwargs[:stream] = true

      apply_rate_limit

      Enumerator.new do |yielder|
        @retryer.call do
          @client.chat(parameters: completion_kwargs) do |chunk|
            delta = chunk.dig("choices", 0, "delta")
            next unless delta

            tool_call_deltas = nil
            if delta["tool_calls"]
              tool_call_deltas = delta["tool_calls"].map do |tc|
                ChatMessageToolCallStreamDelta.new(
                  index: tc["index"],
                  id: tc["id"],
                  type: tc["type"],
                  function: tc["function"] ? ChatMessageToolCallFunction.new(
                    name: tc.dig("function", "name"),
                    arguments: tc.dig("function", "arguments")
                  ) : nil
                )
              end
            end

            yielder << ChatMessageStreamDelta.new(
              content: delta["content"],
              tool_calls: tool_call_deltas
            )
          end
        end
      end
    end
  end

  # Alias for backward compatibility
  OpenAIServerModel = OpenAIModel
end
