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

require "tempfile"
require "securerandom"
require "fileutils"
require "logger"

module Smolagents
  # Abstract class for types that can be returned by agents.
  #
  # These objects serve three purposes:
  # - They behave as the type they're meant to be (string for text, image for images)
  # - They can be stringified via to_s
  # - They provide consistent interfaces for raw and string representations
  #
  # @abstract Subclass and override {#to_raw} and {#to_string}
  class AgentType
    attr_reader :value

    # @param value [Object] The wrapped value
    def initialize(value)
      @value = value
      @logger = Logger.new($stderr)
    end

    # Convert to string representation
    # @return [String]
    def to_s
      to_string
    end

    # Get the raw underlying value
    # @return [Object]
    def to_raw
      @logger.error("This is a raw AgentType of unknown type. Display and string conversion will be unreliable")
      @value
    end

    # Get string representation for serialization
    # @return [String]
    def to_string
      @logger.error("This is a raw AgentType of unknown type. Display and string conversion will be unreliable")
      @value.to_s
    end
  end

  # Text type returned by the agent. Behaves as a string.
  #
  # @example
  #   text = AgentText.new("Hello, world!")
  #   puts text         # => "Hello, world!"
  #   text.upcase       # => "HELLO, WORLD!"
  class AgentText < AgentType
    include Comparable

    # Delegate string methods to the underlying value
    def method_missing(method, *args, &block)
      if @value.respond_to?(method)
        @value.public_send(method, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      @value.respond_to?(method, include_private) || super
    end

    # Get the raw string value
    # @return [String]
    def to_raw
      @value
    end

    # Get the string representation
    # @return [String]
    def to_string
      @value.to_s
    end

    # Compare with other strings
    def <=>(other)
      to_s <=> other.to_s
    end

    # String concatenation
    def +(other)
      to_s + other.to_s
    end

    # Check equality
    def ==(other)
      to_s == other.to_s
    end

    alias eql? ==

    def hash
      to_s.hash
    end

    # Get string length
    def length
      @value.length
    end

    alias size length
  end

  # Image type returned by the agent.
  #
  # Supports lazy loading from paths, raw bytes, or image data.
  # Uses ChunkyPNG for image manipulation if available.
  #
  # @example From path
  #   image = AgentImage.new("/path/to/image.png")
  #   image.save("output.png")
  #
  # @example From bytes
  #   image = AgentImage.new(File.binread("image.png"))
  class AgentImage < AgentType
    attr_reader :path

    # @param value [String, AgentImage, IO] Image source (path, bytes, or AgentImage)
    def initialize(value)
      super(value)
      @path = nil
      @raw_data = nil

      case value
      when AgentImage
        @raw_data = value.instance_variable_get(:@raw_data)
        @path = value.path
      when String
        if File.exist?(value)
          @path = value
        elsif value.encoding == Encoding::BINARY || value.bytes.any? { |b| b > 127 }
          # Looks like binary image data
          @raw_data = value
        else
          # Treat as path
          @path = value
        end
      when IO, StringIO
        @raw_data = value.read
      else
        raise TypeError, "Unsupported type for #{self.class}: #{value.class}"
      end

      raise TypeError, "Unsupported type for #{self.class}: #{value.class}" if @path.nil? && @raw_data.nil?
    end

    # Get the raw image data as bytes
    # @return [String] Binary image data
    def to_raw
      return @raw_data if @raw_data

      if @path
        @raw_data = File.binread(@path)
      end

      @raw_data
    end

    # Get the path to the image file
    # @return [String] File path (creates temp file if needed)
    def to_string
      return @path if @path && File.exist?(@path)

      if @raw_data
        dir = Dir.mktmpdir
        @path = File.join(dir, "#{SecureRandom.uuid}.png")
        File.binwrite(@path, @raw_data)
      end

      @path
    end

    # Save the image to a file
    #
    # @param output_path [String] Path to save the image
    # @param format [String] Image format (default: inferred from extension)
    # @return [void]
    def save(output_path, format: nil)
      data = to_raw
      File.binwrite(output_path, data)
    end

    # Get image dimensions (requires ChunkyPNG for PNG images)
    # @return [Array<Integer>] [width, height] or nil if unavailable
    def dimensions
      return nil unless defined?(ChunkyPNG)

      data = to_raw
      return nil unless data

      begin
        image = ChunkyPNG::Image.from_blob(data)
        [image.width, image.height]
      rescue StandardError
        nil
      end
    end

    # Check if image data is available
    # @return [Boolean]
    def loaded?
      !@raw_data.nil?
    end

    def inspect
      "#<#{self.class} path=#{@path.inspect} loaded=#{loaded?}>"
    end
  end

  # Audio type returned by the agent.
  #
  # Supports audio from file paths or raw sample data.
  #
  # @example From path
  #   audio = AgentAudio.new("/path/to/audio.wav")
  #
  # @example From samples
  #   audio = AgentAudio.new([16000, samples_array]) # [samplerate, samples]
  class AgentAudio < AgentType
    attr_reader :samplerate, :path

    DEFAULT_SAMPLERATE = 16_000

    # @param value [String, Array] Audio source (path or [samplerate, samples])
    # @param samplerate [Integer] Sample rate (default: 16000)
    def initialize(value, samplerate: DEFAULT_SAMPLERATE)
      super(value)
      @path = nil
      @samples = nil
      @samplerate = samplerate

      case value
      when String
        # Treat as file path
        @path = value
      when Array
        # [samplerate, samples] tuple
        if value.length == 2 && value[0].is_a?(Numeric)
          @samplerate = value[0].to_i
          @samples = value[1]
        else
          @samples = value
        end
      else
        raise ArgumentError, "Unsupported audio type: #{value.class}"
      end
    end

    # Get the raw audio samples
    # @return [Array<Float>] Audio samples
    def to_raw
      return @samples if @samples

      if @path
        # Read audio file - this is a simplified version
        # In a real implementation, you'd use an audio library
        @samples = File.binread(@path).unpack("s*").map { |s| s / 32768.0 }
      end

      @samples
    end

    # Get the path to the audio file
    # @return [String] File path (creates temp file if needed)
    def to_string
      return @path if @path && File.exist?(@path)

      if @samples
        dir = Dir.mktmpdir
        @path = File.join(dir, "#{SecureRandom.uuid}.wav")
        write_wav(@path, @samples, @samplerate)
      end

      @path
    end

    # Get duration in seconds
    # @return [Float] Duration in seconds
    def duration
      samples = to_raw
      return 0.0 unless samples

      samples.length.to_f / @samplerate
    end

    def inspect
      "#<#{self.class} samplerate=#{@samplerate} path=#{@path.inspect} duration=#{duration.round(2)}s>"
    end

    private

    # Write samples to a WAV file (simplified mono 16-bit PCM)
    def write_wav(path, samples, samplerate)
      samples_16bit = samples.map { |s| (s * 32767).to_i.clamp(-32768, 32767) }
      data = samples_16bit.pack("s*")

      File.open(path, "wb") do |f|
        # WAV header
        f.write("RIFF")
        f.write([36 + data.bytesize].pack("V"))
        f.write("WAVE")
        f.write("fmt ")
        f.write([16, 1, 1, samplerate, samplerate * 2, 2, 16].pack("VvvVVvv"))
        f.write("data")
        f.write([data.bytesize].pack("V"))
        f.write(data)
      end
    end
  end

  # Mapping of type names to agent type classes
  AGENT_TYPE_MAPPING = {
    "string" => AgentText,
    "text" => AgentText,
    "image" => AgentImage,
    "audio" => AgentAudio
  }.freeze

  module_function

  # Convert agent input types to raw values
  #
  # @param args [Array] Positional arguments
  # @param kwargs [Hash] Keyword arguments
  # @return [Array<Array, Hash>] Converted [args, kwargs]
  def handle_agent_input_types(*args, **kwargs)
    converted_args = args.map { |arg| arg.is_a?(AgentType) ? arg.to_raw : arg }
    converted_kwargs = kwargs.transform_values { |v| v.is_a?(AgentType) ? v.to_raw : v }
    [converted_args, converted_kwargs]
  end

  # Convert output to appropriate agent type
  #
  # @param output [Object] Output value to wrap
  # @param output_type [String, nil] Expected output type
  # @return [AgentType, Object] Wrapped output or original if no match
  def handle_agent_output_types(output, output_type: nil)
    if output_type && AGENT_TYPE_MAPPING.key?(output_type)
      return AGENT_TYPE_MAPPING[output_type].new(output)
    end

    # Auto-detect type
    case output
    when String
      AgentText.new(output)
    else
      output
    end
  end
end
