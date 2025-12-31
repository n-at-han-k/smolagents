# frozen_string_literal: true

require "tempfile"
require "securerandom"
require_relative "agent_type"

module Smolagents
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
end
