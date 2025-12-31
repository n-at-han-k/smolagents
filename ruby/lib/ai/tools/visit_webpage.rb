# frozen_string_literal: true

require "net/http"
require "uri"

module AI
  module Tools
    # Fetch a webpage and return its content as text.
    class VisitWebpage < Tool
      def initialize(max_length: 40_000)
        super(
          name: "visit_webpage",
          description: "Fetch a webpage and return its content",
          inputs: { url: { type: "string", description: "URL to visit" } }
        )
        @max_length = max_length
      end

      def call(url:)
        uri = URI(url)
        uri = URI("https://#{url}") unless uri.scheme

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 20

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "Mozilla/5.0 (compatible; AI Ruby Client)"

        response = http.request(request)

        case response
        when Net::HTTPSuccess
          content = html_to_text(response.body)
          truncate(content)
        when Net::HTTPRedirection
          call(url: response["location"])
        else
          "Error: HTTP #{response.code}"
        end
      rescue => e
        "Error fetching #{url}: #{e.message}"
      end

      private

      def html_to_text(html)
        # Remove scripts and styles
        text = html.gsub(/<script[^>]*>.*?<\/script>/mi, "")
        text = text.gsub(/<style[^>]*>.*?<\/style>/mi, "")

        # Convert common elements
        text = text.gsub(/<br\s*\/?>/i, "\n")
        text = text.gsub(/<\/p>/i, "\n\n")
        text = text.gsub(/<\/div>/i, "\n")
        text = text.gsub(/<\/h[1-6]>/i, "\n\n")
        text = text.gsub(/<li>/i, "- ")
        text = text.gsub(/<\/li>/i, "\n")

        # Remove remaining tags
        text = text.gsub(/<[^>]+>/, "")

        # Decode entities
        text = text.gsub(/&nbsp;/i, " ")
        text = text.gsub(/&amp;/i, "&")
        text = text.gsub(/&lt;/i, "<")
        text = text.gsub(/&gt;/i, ">")
        text = text.gsub(/&quot;/i, '"')

        # Clean up whitespace
        text = text.gsub(/\n{3,}/, "\n\n")
        text.strip
      end

      def truncate(text)
        return text if text.length <= @max_length

        text[0, @max_length] + "\n...(truncated)..."
      end
    end
  end
end
