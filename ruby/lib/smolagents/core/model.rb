# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Smolagents
  module Core
    # Minimal LLM client. Supports OpenAI and Anthropic.
    class Model
      def initialize(provider:, model:, api_key: nil)
        @provider = provider
        @model = model
        @api_key = api_key || default_api_key
      end

      def generate(messages)
        case @provider
        when "openai" then call_openai(messages)
        when "anthropic" then call_anthropic(messages)
        else raise "Unknown provider: #{@provider}"
        end
      end

      private

      def default_api_key
        case @provider
        when "openai" then ENV["OPENAI_API_KEY"]
        when "anthropic" then ENV["ANTHROPIC_API_KEY"]
        end
      end

      def call_openai(messages)
        uri = URI("https://api.openai.com/v1/chat/completions")
        body = { model: @model, messages: messages }

        response = post_json(uri, body, {
          "Authorization" => "Bearer #{@api_key}",
          "Content-Type" => "application/json"
        })

        response.dig("choices", 0, "message", "content")
      end

      def call_anthropic(messages)
        uri = URI("https://api.anthropic.com/v1/messages")

        # Extract system message
        system = messages.find { |m| m[:role] == "system" }&.dig(:content)
        msgs = messages.reject { |m| m[:role] == "system" }

        body = { model: @model, max_tokens: 4096, messages: msgs }
        body[:system] = system if system

        response = post_json(uri, body, {
          "x-api-key" => @api_key,
          "anthropic-version" => "2023-06-01",
          "Content-Type" => "application/json"
        })

        response.dig("content", 0, "text")
      end

      def post_json(uri, body, headers)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri.path, headers)
        request.body = body.to_json

        response = http.request(request)
        JSON.parse(response.body)
      end
    end
  end
end
