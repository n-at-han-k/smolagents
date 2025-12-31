# frozen_string_literal: true

module Smolagents
  # Simple rate limiter that enforces a minimum delay between consecutive requests
  #
  # @example
  #   limiter = RateLimiter.new(requests_per_minute: 60)
  #   limiter.throttle # waits if needed
  #   make_api_call()
  class RateLimiter
    # @param requests_per_minute [Float, nil] Maximum requests per minute (nil to disable)
    def initialize(requests_per_minute: nil)
      @enabled = !requests_per_minute.nil?
      @interval = @enabled ? 60.0 / requests_per_minute : 0.0
      @last_call = 0.0
    end

    # Pause execution to respect the rate limit
    # @return [void]
    def throttle
      return unless @enabled

      now = Time.now.to_f
      elapsed = now - @last_call

      if elapsed < @interval
        sleep(@interval - elapsed)
      end

      @last_call = Time.now.to_f
    end

    # Check if rate limiting is enabled
    # @return [Boolean]
    def enabled?
      @enabled
    end
  end
end
