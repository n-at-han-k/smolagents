# frozen_string_literal: true

require_relative "log_level"
require_relative "token_usage"

module Smolagents
  # Monitor for tracking agent execution metrics
  #
  # Tracks step durations and token counts across an agent run
  class Monitor
    attr_reader :step_durations, :tracked_model, :logger,
                :total_input_token_count, :total_output_token_count

    # @param tracked_model [Object] The model being tracked
    # @param logger [AgentLogger] Logger for output
    def initialize(tracked_model:, logger:)
      @tracked_model = tracked_model
      @logger = logger
      reset
    end

    # Get total token counts as TokenUsage
    # @return [TokenUsage] Combined token usage
    def total_token_counts
      TokenUsage.new(
        input_tokens: @total_input_token_count,
        output_tokens: @total_output_token_count
      )
    end

    # Reset all metrics
    # @return [void]
    def reset
      @step_durations = []
      @total_input_token_count = 0
      @total_output_token_count = 0
    end

    # Update metrics from a step log
    # @param step_log [MemoryStep] Step log to update from
    # @return [void]
    def update_metrics(step_log)
      step_duration = step_log.timing.duration
      @step_durations << step_duration

      output_parts = ["[Step #{@step_durations.length}: Duration #{format('%.2f', step_duration)} seconds"]

      if step_log.token_usage
        @total_input_token_count += step_log.token_usage.input_tokens
        @total_output_token_count += step_log.token_usage.output_tokens
        output_parts << "| Input tokens: #{format_number(@total_input_token_count)}"
        output_parts << "| Output tokens: #{format_number(@total_output_token_count)}"
      end

      output_parts << "]"
      @logger.log(output_parts.join(" "), level: LogLevel::INFO)
    end

    private

    def format_number(num)
      num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
  end
end
