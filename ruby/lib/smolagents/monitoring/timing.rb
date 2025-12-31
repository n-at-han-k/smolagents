# frozen_string_literal: true

module Smolagents
  # Contains timing information for a given step or run
  #
  # @attr_reader start_time [Float] Start time as Unix timestamp
  # @attr_accessor end_time [Float, nil] End time as Unix timestamp
  class Timing
    attr_reader :start_time
    attr_accessor :end_time

    # @param start_time [Float] Start time as Unix timestamp
    # @param end_time [Float, nil] End time as Unix timestamp (optional)
    def initialize(start_time:, end_time: nil)
      @start_time = start_time
      @end_time = end_time
    end

    # Calculate duration in seconds
    # @return [Float, nil] Duration in seconds, or nil if not ended
    def duration
      return nil if @end_time.nil?

      @end_time - @start_time
    end

    # Convert to hash representation
    # @return [Hash] Hash with timing data
    def to_h
      {
        start_time: @start_time,
        end_time: @end_time,
        duration: duration
      }
    end

    alias to_hash to_h

    # Create a new Timing starting now
    # @return [Timing] New timing instance
    def self.start_now
      new(start_time: Time.now.to_f)
    end

    # Mark the timing as ended now
    # @return [self]
    def stop!
      @end_time = Time.now.to_f
      self
    end

    def to_s
      "Timing(start: #{@start_time}, end: #{@end_time}, duration: #{duration&.round(3)})"
    end

    def inspect
      "#<#{self.class} #{to_s}>"
    end
  end
end
