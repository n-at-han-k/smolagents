# frozen_string_literal: true

# Copyright 2024 HuggingFace Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "logger"

module Smolagents
  # Log levels for agent output control
  module LogLevel
    OFF = -1   # No output
    ERROR = 0  # Only errors
    INFO = 1   # Normal output (default)
    DEBUG = 2  # Detailed output

    def self.from_string(str)
      const_get(str.upcase)
    rescue NameError
      INFO
    end
  end

  # Contains token usage information for a given step or run
  #
  # @attr_reader input_tokens [Integer] Number of input tokens
  # @attr_reader output_tokens [Integer] Number of output tokens
  # @attr_reader total_tokens [Integer] Total number of tokens (computed)
  class TokenUsage
    attr_reader :input_tokens, :output_tokens, :total_tokens

    # @param input_tokens [Integer] Number of input tokens
    # @param output_tokens [Integer] Number of output tokens
    def initialize(input_tokens:, output_tokens:)
      @input_tokens = input_tokens
      @output_tokens = output_tokens
      @total_tokens = input_tokens + output_tokens
    end

    # Convert to hash representation
    # @return [Hash] Hash with token counts
    def to_h
      {
        input_tokens: @input_tokens,
        output_tokens: @output_tokens,
        total_tokens: @total_tokens
      }
    end

    alias to_hash to_h

    # Add token usage from another instance
    # @param other [TokenUsage] Other token usage to add
    # @return [TokenUsage] New combined token usage
    def +(other)
      TokenUsage.new(
        input_tokens: @input_tokens + other.input_tokens,
        output_tokens: @output_tokens + other.output_tokens
      )
    end

    def to_s
      "TokenUsage(input: #{@input_tokens}, output: #{@output_tokens}, total: #{@total_tokens})"
    end

    def inspect
      "#<#{self.class} #{to_s}>"
    end
  end

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

  # Logger for agent output with rich formatting
  #
  # Supports multiple log levels and various output formats
  class AgentLogger
    YELLOW_HEX = "#d4b702"

    attr_reader :level
    attr_accessor :console

    # @param level [Integer] Log level (default: LogLevel::INFO)
    # @param console [IO, nil] Output stream (default: $stdout)
    def initialize(level: LogLevel::INFO, console: nil)
      @level = level
      @console = console || $stdout
      @ruby_logger = Logger.new(@console)
      @ruby_logger.formatter = proc { |_severity, _datetime, _progname, msg| "#{msg}\n" }
    end

    # Log a message at the specified level
    # @param args [Array] Messages to log
    # @param level [Integer, String] Log level
    # @return [void]
    def log(*args, level: LogLevel::INFO, **_kwargs)
      level = LogLevel.from_string(level) if level.is_a?(String)
      return unless level <= @level

      args.each { |arg| @console.puts(arg) }
    end

    # Log an error message
    # @param error_message [String] Error message to log
    # @return [void]
    def log_error(error_message)
      log(colorize(escape_code_brackets(error_message), :red, :bold), level: LogLevel::ERROR)
    end

    # Log markdown content with optional title
    # @param content [String] Markdown content
    # @param title [String, nil] Optional title
    # @param level [Integer] Log level
    # @return [void]
    def log_markdown(content:, title: nil, level: LogLevel::INFO, **_kwargs)
      if title
        log(rule(title), level: level)
      end
      log(content, level: level)
    end

    # Log code with syntax highlighting placeholder
    # @param title [String] Code block title
    # @param content [String] Code content
    # @param level [Integer] Log level
    # @return [void]
    def log_code(title:, content:, level: LogLevel::INFO)
      log(panel(title: title, content: content), level: level)
    end

    # Log a horizontal rule with title
    # @param title [String] Rule title
    # @param level [Integer] Log level
    # @return [void]
    def log_rule(title, level: LogLevel::INFO)
      log(rule(title), level: level)
    end

    # Log a task panel
    # @param content [String] Task content
    # @param subtitle [String] Task subtitle
    # @param title [String, nil] Optional title
    # @param level [Integer] Log level
    # @return [void]
    def log_task(content:, subtitle:, title: nil, level: LogLevel::INFO)
      header = "New run#{title ? " - #{title}" : ""}"
      log(panel(title: header, content: "\n#{escape_code_brackets(content)}\n", subtitle: subtitle), level: level)
    end

    # Log messages list
    # @param messages [Array<Hash>] Messages to log
    # @param level [Integer] Log level
    # @return [void]
    def log_messages(messages, level: LogLevel::DEBUG)
      messages_string = messages.map { |m| JSON.pretty_generate(m.to_h) }.join("\n")
      log(messages_string, level: level)
    end

    private

    def escape_code_brackets(text)
      text.to_s.gsub(/\[([^\]]*)\]/) do |match|
        content = ::Regexp.last_match(1)
        cleaned = content.gsub(/bold|red|green|blue|yellow|magenta|cyan|white|black|italic|dim|\s|#[0-9a-fA-F]{6}/, "")
        cleaned.strip.empty? ? match : "\\[#{content}\\]"
      end
    end

    def colorize(text, *styles)
      # Simple ANSI color codes for terminal output
      codes = {
        red: 31,
        green: 32,
        yellow: 33,
        blue: 34,
        bold: 1,
        dim: 2,
        italic: 3
      }

      prefix = styles.map { |s| "\e[#{codes[s]}m" }.join
      "#{prefix}#{text}\e[0m"
    end

    def rule(title, char: "━", width: 80)
      title_part = "── #{title} "
      remaining = width - title_part.length
      "#{title_part}#{char * [remaining, 0].max}"
    end

    def panel(title:, content:, subtitle: nil)
      lines = []
      lines << "╭─ #{title} ─╮"
      content.split("\n").each { |line| lines << "│ #{line}" }
      lines << "╰─#{subtitle ? " #{subtitle} " : ""}─╯"
      lines.join("\n")
    end
  end
end
