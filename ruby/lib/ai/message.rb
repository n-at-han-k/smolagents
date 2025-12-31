# frozen_string_literal: true

module AI
  # Builder for constructing messages to send to LLM APIs.
  # Similar to the Mail gem's API for building emails.
  #
  # Example:
  #   Message.new do |m|
  #     m.text "Describe this image"
  #     m.attachment file_path
  #     m.response_schema { type: "object", properties: { ... } }
  #   end
  #
  class Message
    attr_reader :parts

    def initialize
      @parts = []
      @schema = nil
      @metadata = {}

      yield self if block_given?
    end

    # Add text content
    def text(content)
      @parts << { type: :text, content: content }
      self
    end

    # Add file attachment (image, document, etc.)
    def attachment(file_path_or_data, mime_type: nil)
      if file_path_or_data.is_a?(String) && File.exist?(file_path_or_data)
        data = File.read(file_path_or_data)
        mime_type ||= detect_mime_type(file_path_or_data)
        @parts << { type: :attachment, data: data, mime_type: mime_type, path: file_path_or_data }
      else
        @parts << { type: :attachment, data: file_path_or_data, mime_type: mime_type }
      end
      self
    end

    # Add image (convenience method)
    def image(file_path_or_url)
      if file_path_or_url.start_with?("http")
        @parts << { type: :image_url, url: file_path_or_url }
      else
        attachment(file_path_or_url)
      end
      self
    end

    # Set expected response schema (for structured output)
    def response_schema(schema)
      @schema = schema
      self
    end

    # Add arbitrary metadata
    def meta(key, value)
      @metadata[key] = value
      self
    end

    # Convert to hash for API serialization
    def to_h
      {
        parts: @parts,
        schema: @schema,
        metadata: @metadata
      }.compact
    end

    # Get just the text content
    def to_s
      @parts.select { |p| p[:type] == :text }.map { |p| p[:content] }.join("\n")
    end

    private

    def detect_mime_type(path)
      case File.extname(path).downcase
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".gif" then "image/gif"
      when ".webp" then "image/webp"
      when ".pdf" then "application/pdf"
      else "application/octet-stream"
      end
    end
  end
end
