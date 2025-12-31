# frozen_string_literal: true

require "fileutils"
require "time"

module AI
  # Session stores conversation history and handles logging.
  # Similar to a Faraday connection - reusable context for multiple requests.
  class Session
    attr_reader :name, :history
    attr_accessor :log_path, :defaults, :stream, :logger, :client

    def initialize(name:, client: nil, log_path: nil, stream: nil, logger: nil, **defaults)
      @name     = name
      @client   = client
      @log_path = log_path || File.join("log", "#{name}.log")
      @stream   = stream
      @logger   = logger
      @defaults = defaults
      @history  = []

      yield self if block_given?
    end

    # Send a message and record in history
    def chat(input, **opts)
      raise "No client configured" unless @client

      message = input.is_a?(Message) ? input : Message.new { |m| m.text(input) }
      merged  = defaults.merge(opts)

      response = @client.call(message, history: @history, **merged)

      @history << { role: "user", content: message.to_h }
      @history << { role: "assistant", content: response }

      log_exchange(message, response)

      response
    end

    # Clear conversation history
    def clear!
      @history = []
    end

    # Add a message to history without sending
    def add_to_history(role:, content:)
      @history << { role: role, content: content }
    end

    private

    def log_exchange(message, response)
      @logger&.call(message, response)

      return unless @log_path

      FileUtils.mkdir_p(File.dirname(@log_path))
      File.open(@log_path, "a") do |f|
        timestamp = Time.now.iso8601
        f.puts "[#{timestamp}] User: #{message.to_h}"
        f.puts "[#{timestamp}] Assistant: #{response}"
        f.puts
      end
    end
  end
end
