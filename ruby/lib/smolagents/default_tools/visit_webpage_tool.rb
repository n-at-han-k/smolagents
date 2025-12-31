# frozen_string_literal: true

require "net/http"
require "uri"

module Smolagents
  # Visits a webpage and returns its content as markdown.
  #
  # This tool fetches a webpage and converts the HTML content to markdown.
  #
  # @example
  #   tool = VisitWebpageTool.new(max_output_length: 10000)
  #   content = tool.call(url: "https://example.com")
  #
  class VisitWebpageTool < Tool
    self.tool_name = "visit_webpage"
    self.tool_description = "Visits a webpage at the given url and reads its content as a markdown string. Use this to browse webpages."
    self.input_schema = {
      url: { type: "string", description: "The url of the webpage to visit." }
    }
    self.output_type = "string"

    # @return [Integer] Maximum output length
    attr_reader :max_output_length

    # Create a new VisitWebpageTool
    #
    # @param max_output_length [Integer] Maximum characters in output
    def initialize(max_output_length: 40000)
      @max_output_length = max_output_length
      super()
    end

    def forward(url:)
      uri = URI.parse(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 20
      http.read_timeout = 20

      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = "Mozilla/5.0 (compatible; Smolagents/1.0)"

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        return "Error fetching the webpage: HTTP #{response.code}"
      end

      markdown = html_to_markdown(response.body)
      truncate_content(markdown)
    rescue Net::OpenTimeout, Net::ReadTimeout
      "The request timed out. Please try again later or check the URL."
    rescue StandardError => e
      "Error fetching the webpage: #{e.message}"
    end

    private

    def html_to_markdown(html)
      # Simple HTML to markdown conversion
      text = html.dup

      # Remove script and style tags
      text.gsub!(/<script[^>]*>.*?<\/script>/mi, "")
      text.gsub!(/<style[^>]*>.*?<\/style>/mi, "")

      # Convert headers
      text.gsub!(/<h1[^>]*>(.*?)<\/h1>/mi) { "\n# #{strip_tags(Regexp.last_match(1))}\n" }
      text.gsub!(/<h2[^>]*>(.*?)<\/h2>/mi) { "\n## #{strip_tags(Regexp.last_match(1))}\n" }
      text.gsub!(/<h3[^>]*>(.*?)<\/h3>/mi) { "\n### #{strip_tags(Regexp.last_match(1))}\n" }
      text.gsub!(/<h4[^>]*>(.*?)<\/h4>/mi) { "\n#### #{strip_tags(Regexp.last_match(1))}\n" }
      text.gsub!(/<h5[^>]*>(.*?)<\/h5>/mi) { "\n##### #{strip_tags(Regexp.last_match(1))}\n" }
      text.gsub!(/<h6[^>]*>(.*?)<\/h6>/mi) { "\n###### #{strip_tags(Regexp.last_match(1))}\n" }

      # Convert links
      text.gsub!(/<a[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>/mi) { "[#{strip_tags(Regexp.last_match(2))}](#{Regexp.last_match(1)})" }

      # Convert bold and italic
      text.gsub!(/<(strong|b)[^>]*>(.*?)<\/\1>/mi) { "**#{Regexp.last_match(2)}**" }
      text.gsub!(/<(em|i)[^>]*>(.*?)<\/\1>/mi) { "*#{Regexp.last_match(2)}*" }

      # Convert code blocks
      text.gsub!(/<pre[^>]*><code[^>]*>(.*?)<\/code><\/pre>/mi) { "\n```\n#{Regexp.last_match(1)}\n```\n" }
      text.gsub!(/<code[^>]*>(.*?)<\/code>/mi) { "`#{Regexp.last_match(1)}`" }

      # Convert lists
      text.gsub!(/<li[^>]*>(.*?)<\/li>/mi) { "\n- #{strip_tags(Regexp.last_match(1))}" }

      # Convert paragraphs
      text.gsub!(/<p[^>]*>(.*?)<\/p>/mi) { "\n#{Regexp.last_match(1)}\n" }

      # Convert line breaks
      text.gsub!(/<br\s*\/?>/i, "\n")

      # Remove remaining HTML tags
      text.gsub!(/<[^>]+>/, "")

      # Decode HTML entities
      text.gsub!("&amp;", "&")
      text.gsub!("&lt;", "<")
      text.gsub!("&gt;", ">")
      text.gsub!("&quot;", '"')
      text.gsub!("&#39;", "'")
      text.gsub!("&nbsp;", " ")

      # Clean up multiple newlines
      text.gsub!(/\n{3,}/, "\n\n")

      text.strip
    end

    def strip_tags(html)
      html.to_s.gsub(/<[^>]+>/, "").strip
    end

    def truncate_content(content)
      return content if content.length <= @max_output_length

      "#{content[0, @max_output_length]}\n..._This content has been truncated to stay below #{@max_output_length} characters_...\n"
    end
  end
end
