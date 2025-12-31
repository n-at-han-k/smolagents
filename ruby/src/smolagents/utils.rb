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

require "json"
require "base64"
require "fileutils"

module Smolagents
  # Utility methods for the smolagents library
  module Utils
    # Default maximum content length before truncation
    MAX_LENGTH_TRUNCATE_CONTENT = 20_000

    # Base built-in modules that are safe to use
    BASE_BUILTIN_MODULES = %w[
      date
      time
      json
      set
      securerandom
      digest
      base64
      uri
      cgi
      erb
    ].freeze

    module_function

    # Recursively make objects JSON serializable
    #
    # @param obj [Object] Object to make serializable
    # @return [Object] JSON-serializable version of the object
    def make_json_serializable(obj)
      case obj
      when nil, true, false, Integer, Float
        obj
      when String
        # Try to parse string as JSON if it looks like JSON
        if (obj.start_with?("{") && obj.end_with?("}")) || (obj.start_with?("[") && obj.end_with?("]"))
          begin
            parsed = JSON.parse(obj)
            make_json_serializable(parsed)
          rescue JSON::ParserError
            obj
          end
        else
          obj
        end
      when Array
        obj.map { |item| make_json_serializable(item) }
      when Hash
        obj.transform_keys(&:to_s).transform_values { |v| make_json_serializable(v) }
      when Symbol
        obj.to_s
      else
        if obj.respond_to?(:to_h)
          { "_type" => obj.class.name }.merge(make_json_serializable(obj.to_h))
        else
          obj.to_s
        end
      end
    end

    # Extract JSON blob from text
    #
    # @param json_blob [String] Text containing JSON
    # @return [Array<Hash, String>] Tuple of [parsed_json, prefix_text]
    # @raise [ArgumentError] If no valid JSON is found
    def parse_json_blob(json_blob)
      first_brace = json_blob.index("{")
      raise ArgumentError, "The model output does not contain any JSON blob." unless first_brace

      last_brace = json_blob.rindex("}")
      raise ArgumentError, "The model output does not contain any JSON blob." unless last_brace

      json_str = json_blob[first_brace..last_brace]

      begin
        json_data = JSON.parse(json_str)
        [json_data, json_blob[0...first_brace]]
      rescue JSON::ParserError => e
        if json_blob[e.message[/at position (\d+)/, 1].to_i - 1, 3] == "},\n"
          raise ArgumentError, "JSON is invalid: you probably tried to provide multiple tool calls in one action. PROVIDE ONLY ONE TOOL CALL."
        end

        raise ArgumentError, "The JSON blob you used is invalid due to the following error: #{e.message}.\nJSON blob was: #{json_blob}"
      end
    end

    # Extract code from text using regex patterns
    #
    # @param text [String] Text containing code blocks
    # @param code_block_tags [Array<String>] Opening and closing tags for code blocks
    # @return [String, nil] Extracted code or nil if not found
    def extract_code_from_text(text, code_block_tags)
      pattern = /#{Regexp.escape(code_block_tags[0])}(.*?)#{Regexp.escape(code_block_tags[1])}/m
      matches = text.scan(pattern).flatten
      return nil if matches.empty?

      matches.map(&:strip).join("\n\n")
    end

    # Parse code blobs from LLM output
    #
    # @param text [String] LLM output text
    # @param code_block_tags [Array<String>] Opening and closing tags
    # @return [String] Extracted code block
    # @raise [ArgumentError] If no valid code block is found
    def parse_code_blobs(text, code_block_tags)
      matches = extract_code_from_text(text, code_block_tags)
      return matches if matches

      # Fallback to markdown pattern
      matches = extract_code_from_text(text, ["```(?:ruby|rb)", "\n```"])
      return matches if matches

      # Maybe the LLM outputted a code blob directly - try to parse it
      begin
        RubyVM::InstructionSequence.compile(text)
        return text
      rescue SyntaxError
        # Not valid Ruby
      end

      if text.include?("final") && text.include?("answer")
        raise ArgumentError, <<~ERROR.strip
          Your code snippet is invalid, because the regex pattern #{code_block_tags[0]}(.*?)#{code_block_tags[1]} was not found in it.
          Here is your code snippet:
          #{text}
          It seems like you're trying to return the final answer, you can do it as follows:
          #{code_block_tags[0]}
          final_answer("YOUR FINAL ANSWER HERE")
          #{code_block_tags[1]}
        ERROR
      end

      raise ArgumentError, <<~ERROR.strip
        Your code snippet is invalid, because the regex pattern #{code_block_tags[0]}(.*?)#{code_block_tags[1]} was not found in it.
        Here is your code snippet:
        #{text}
        Make sure to include code with the correct pattern, for instance:
        Thoughts: Your thoughts
        #{code_block_tags[0]}
        # Your ruby code here
        #{code_block_tags[1]}
      ERROR
    end

    # Truncate content if it exceeds maximum length
    #
    # @param content [String] Content to truncate
    # @param max_length [Integer] Maximum allowed length
    # @return [String] Truncated content
    def truncate_content(content, max_length: MAX_LENGTH_TRUNCATE_CONTENT)
      return content if content.length <= max_length

      half = max_length / 2
      "#{content[0, half]}\n..._This content has been truncated to stay below #{max_length} characters_...\n#{content[-half..]}"
    end

    # Escape square brackets in text while preserving Rich styling tags
    #
    # @param text [String] Text to escape
    # @return [String] Escaped text
    def escape_code_brackets(text)
      text.gsub(/\[([^\]]*)\]/) do |match|
        content = ::Regexp.last_match(1)
        cleaned = content.gsub(/bold|red|green|blue|yellow|magenta|cyan|white|black|italic|dim|\s|#[0-9a-fA-F]{6}/, "")
        cleaned.strip.empty? ? match : "\\[#{content}\\]"
      end
    end

    # Check if a name is a valid Ruby identifier
    #
    # @param name [String] Name to validate
    # @return [Boolean] True if valid identifier
    def valid_name?(name)
      return false unless name.is_a?(String)
      return false if name.empty?

      # Ruby identifiers: start with letter or underscore, followed by letters, digits, or underscores
      # Cannot be a reserved word
      reserved_words = %w[
        __ENCODING__ __LINE__ __FILE__ BEGIN END alias and begin break case class def
        defined? do else elsif end ensure false for if in module next nil not or redo
        rescue retry return self super then true undef unless until when while yield
      ]

      name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) && !reserved_words.include?(name)
    end

    # Encode an image to base64
    #
    # @param image_data [String] Raw image data
    # @return [String] Base64-encoded image
    def encode_image_base64(image_data)
      Base64.strict_encode64(image_data)
    end

    # Create a data URL for an image
    #
    # @param base64_image [String] Base64-encoded image
    # @param format [String] Image format (default: png)
    # @return [String] Data URL
    def make_image_url(base64_image, format: "png")
      "data:image/#{format};base64,#{base64_image}"
    end

    # Create a directory with __init__.rb file (Ruby equivalent of Python's __init__.py)
    #
    # @param folder [String] Folder path to create
    # @return [void]
    def make_init_file(folder)
      FileUtils.mkdir_p(folder)
      # Ruby doesn't need __init__ files, but we could create a loader file
      # This is mainly for compatibility with the Python pattern
    end
  end

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
