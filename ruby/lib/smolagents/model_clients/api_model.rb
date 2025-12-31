# frozen_string_literal: true

require "logger"

module Smolagents
  # Base class for API-based language models.
  #
  # This class handles common functionality for managing model IDs,
  # custom role mappings, and API client connections.
  #
  # @abstract Subclass and implement {#create_client}
  #
  class ApiModel < Model
    # @return [Hash<String, String>] Custom role conversions
    attr_accessor :custom_role_conversions

    # @return [Object] API client
    attr_accessor :client

    # @return [RateLimiter] Rate limiter
    attr_reader :rate_limiter

    # @return [Retrying] Retry handler
    attr_reader :retryer

    # Create a new ApiModel
    #
    # @param model_id [String] Model identifier
    # @param custom_role_conversions [Hash, nil] Custom role mappings
    # @param client [Object, nil] Pre-configured API client
    # @param requests_per_minute [Float, nil] Rate limit
    # @param retry_enabled [Boolean] Whether to retry on rate limit errors
    # @param kwargs [Hash] Additional arguments
    def initialize(
      model_id:,
      custom_role_conversions: nil,
      client: nil,
      requests_per_minute: nil,
      retry_enabled: true,
      **kwargs
    )
      super(model_id: model_id, **kwargs)

      @custom_role_conversions = custom_role_conversions || {}
      @client = client || create_client
      @rate_limiter = RateLimiter.new(requests_per_minute: requests_per_minute)
      @retryer = Retrying.new(
        max_attempts: retry_enabled ? RETRY_MAX_ATTEMPTS : 1,
        wait_seconds: RETRY_WAIT,
        exponential_base: RETRY_EXPONENTIAL_BASE,
        jitter: RETRY_JITTER,
        retry_predicate: method(:rate_limit_error?)
      )
    end

    # Create the API client for the specific service.
    # @abstract
    # @return [Object] API client
    def create_client
      raise NotImplementedError, "Subclasses must implement #create_client"
    end

    # Apply rate limiting before API calls
    def apply_rate_limit
      @rate_limiter.throttle
    end

    # Check if an exception is a rate limit error
    # @param exception [Exception] The exception to check
    # @return [Boolean]
    def rate_limit_error?(exception)
      error_str = exception.to_s.downcase
      error_str.include?("429") ||
        error_str.include?("rate limit") ||
        error_str.include?("too many requests") ||
        error_str.include?("rate_limit")
    end
  end
end
