# frozen_string_literal: true

module Smolagents
  # Simple retrying controller with exponential backoff
  #
  # Inspired by the tenacity library
  #
  # @example
  #   retrier = Retrying.new(max_attempts: 3, wait_seconds: 1.0)
  #   result = retrier.call { risky_operation }
  class Retrying
    attr_reader :max_attempts, :wait_seconds, :exponential_base

    # @param max_attempts [Integer] Maximum number of retry attempts
    # @param wait_seconds [Float] Initial wait time between retries
    # @param exponential_base [Float] Base for exponential backoff
    # @param jitter [Boolean] Whether to add random jitter
    # @param retry_predicate [Proc, nil] Proc that takes exception and returns true to retry
    # @param before_sleep_logger [Array<Logger, Integer>, nil] Logger and level for pre-sleep logging
    # @param after_logger [Array<Logger, Integer>, nil] Logger and level for post-attempt logging
    def initialize(
      max_attempts: 1,
      wait_seconds: 0.0,
      exponential_base: 2.0,
      jitter: true,
      retry_predicate: nil,
      before_sleep_logger: nil,
      after_logger: nil
    )
      @max_attempts = max_attempts
      @wait_seconds = wait_seconds
      @exponential_base = exponential_base
      @jitter = jitter
      @retry_predicate = retry_predicate
      @before_sleep_logger = before_sleep_logger
      @after_logger = after_logger
    end

    # Execute a block with retry logic
    #
    # @yield The block to execute
    # @return [Object] Result of the block
    # @raise [StandardError] Re-raises the last exception if all retries fail
    def call(&block)
      raise ArgumentError, "Block required" unless block_given?

      start_time = Time.now.to_f
      delay = @wait_seconds

      (1..@max_attempts).each do |attempt_number|
        begin
          result = yield

          # Log after successful call if we had retries
          log_after(attempt_number, start_time, "block") if @after_logger && attempt_number > 1

          return result
        rescue StandardError => e
          # Check if we should retry
          should_retry = @retry_predicate&.call(e) || false

          # If this is the last attempt or we shouldn't retry, raise
          raise if !should_retry || attempt_number >= @max_attempts

          # Log after failed attempt
          log_after(attempt_number, start_time, "block") if @after_logger

          # Exponential backoff with jitter
          jitter_factor = @jitter ? (1 + rand) : 1
          delay *= @exponential_base * jitter_factor

          # Log before sleeping
          if @before_sleep_logger
            logger, level = @before_sleep_logger
            logger.log(level) { "Retrying in #{delay} seconds as it raised #{e.class}: #{e.message}" }
          end

          sleep(delay) if delay.positive?
        end
      end
    end

    private

    def log_after(attempt_number, start_time, fn_name)
      return unless @after_logger

      logger, level = @after_logger
      seconds = Time.now.to_f - start_time
      logger.log(level) do
        "Finished call to '#{fn_name}' after #{format('%.3f', seconds)}(s), " \
          "this was attempt n°#{attempt_number}/#{@max_attempts}."
      end
    end
  end
end
