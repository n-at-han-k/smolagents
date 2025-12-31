# frozen_string_literal: true

module AI
  module Clients
    class Claude < Base
      BASE_URL = "https://api.anthropic.com"
      DEFAULT_MODEL = "claude-sonnet-4-20250514"

      def initialize(api_key: nil, model: DEFAULT_MODEL, **opts)
        api_key ||= ENV["ANTHROPIC_API_KEY"]
        raise "ANTHROPIC_API_KEY not set" unless api_key

        super(api_key: api_key, base_url: BASE_URL, model: model, **opts)
      end

      def call(message, history: [], **opts)
        messages = build_messages(history, message)

        body = {
          model: opts[:model] || @model,
          max_tokens: opts[:max_tokens] || 4096,
          messages: messages
        }

        body[:system] = opts[:system] if opts[:system]

        response = post("/v1/messages", body)
        extract_text(response)
      end

      def available_models
        response = get("/v1/models")
        response["data"]
      end

      protected

      def default_headers
        {
          "x-api-key" => @api_key,
          "anthropic-version" => "2023-06-01"
        }
      end

      private

      def build_messages(history, message)
        msgs = history.map do |h|
          { role: h[:role], content: h[:content].to_s }
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
            { type: "image", source: { type: "url", url: part[:url] } }
          when :attachment
            {
              type: "image",
              source: {
                type: "base64",
                media_type: part[:mime_type],
                data: Base64.strict_encode64(part[:data])
              }
            }
          end
        end

        parts.length == 1 && parts[0][:type] == "text" ? parts[0][:text] : parts
      end

      def extract_text(response)
        content = response["content"]
        return "" unless content

        content.map { |c| c["text"] }.compact.join
      end
    end
  end
end
