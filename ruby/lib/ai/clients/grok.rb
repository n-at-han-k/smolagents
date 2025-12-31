# frozen_string_literal: true

module AI
  module Clients
    # xAI's Grok models
    class Grok < Base
      BASE_URL = "https://api.x.ai"
      DEFAULT_MODEL = "grok-2-latest"

      def initialize(api_key: nil, model: DEFAULT_MODEL, **opts)
        api_key ||= ENV["XAI_API_KEY"]
        raise "XAI_API_KEY not set" unless api_key

        super(api_key: api_key, base_url: BASE_URL, model: model, **opts)
      end

      def call(message, history: [], **opts)
        messages = build_messages(history, message, opts[:system])

        body = {
          model: opts[:model] || @model,
          messages: messages
        }

        body[:max_tokens] = opts[:max_tokens] if opts[:max_tokens]

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

        msgs << { role: "user", content: message.to_s }
        msgs
      end

      def extract_text(response)
        response.dig("choices", 0, "message", "content") || ""
      end
    end
  end
end
