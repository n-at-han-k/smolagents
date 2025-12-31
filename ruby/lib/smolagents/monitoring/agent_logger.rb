# frozen_string_literal: true

require "logger"
require "json"
require_relative "log_level"

module Smolagents
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
