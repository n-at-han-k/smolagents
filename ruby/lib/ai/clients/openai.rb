# frozen_string_literal: true

require "base64"

module AI
  module Clients
    class OpenAI < Base
      BASE_URL = "https://api.openai.com"
      DEFAULT_MODEL = "gpt-4o"

      def initialize(api_key: nil, base_url: BASE_URL, model: DEFAULT_MODEL, **opts)
        api_key ||= ENV["OPENAI_API_KEY"]
        raise "OPENAI_API_KEY not set" unless api_key

        super(api_key: api_key, base_url: base_url, model: model, **opts)
      end

      def call(message, history: [], **opts)
        messages = build_messages(history, message, opts[:system])

        body = {
          model: opts[:model] || @model,
          messages: messages
        }

        body[:max_tokens] = opts[:max_tokens] if opts[:max_tokens]
        body[:response_format] = opts[:response_format] if opts[:response_format]

        response = post("/v1/chat/completions", body)
        extract_text(response)
      end

      def available_models
        response = get("/v1/models")
        response["data"]
      end

      protected

      def default_headers
        { "Authorization" => "Bearer #{@api_key}" }
      end

      private

      def build_messages(history, message, system_prompt)
        msgs = []
        msgs << { role: "system", content: system_prompt } if system_prompt

        history.each do |h|
          msgs << { role: h[:role], content: h[:content].to_s }
        end

        msgs << { role: "user", content: format_message(message) }
        msgs
      end

      def format_message(message)
        return message.to_s unless message.is_a?(Message)

        parts = message.parts.map do |part|
          case part[:type]
          when :text
            { type: "text", text: part[:content] }
          when :image_url
            { type: "image_url", image_url: { url: part[:url] } }
          when :attachment
            encoded = Base64.strict_encode64(part[:data])
            {
              type: "image_url",
              image_url: { url: "data:#{part[:mime_type]};base64,#{encoded}" }
            }
          end
        end

        parts.length == 1 && parts[0][:type] == "text" ? parts[0][:text] : parts
      end

      def extract_text(response)
        response.dig("choices", 0, "message", "content") || ""
      end
    end

    # Alias for convenience
    ChatGPT = OpenAI
  end
end
