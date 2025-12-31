# frozen_string_literal: true

require_relative "ai/message"
require_relative "ai/session"
require_relative "ai/tool"
require_relative "ai/decision_maker"

require_relative "ai/clients/base"
require_relative "ai/clients/openai"
require_relative "ai/clients/claude"
require_relative "ai/clients/open_router"
require_relative "ai/clients/grok"

module AI
  class << self
    # Quick access to create a client
    def client(provider, **opts)
      case provider.to_sym
      when :openai, :chatgpt then Clients::OpenAI.new(**opts)
      when :claude, :anthropic then Clients::Claude.new(**opts)
      when :openrouter then Clients::OpenRouter.new(**opts)
      when :grok, :xai then Clients::Grok.new(**opts)
      else raise "Unknown provider: #{provider}"
      end
    end

    # Create a session with a client
    def session(name:, provider:, **opts)
      Session.new(name: name, client: client(provider, **opts))
    end
  end
end
