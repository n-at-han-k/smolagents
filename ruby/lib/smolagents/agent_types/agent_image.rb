# frozen_string_literal: true

require "tempfile"
require "securerandom"
require "fileutils"
require_relative "agent_type"

module Smolagents
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
end
