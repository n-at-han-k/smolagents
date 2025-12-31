# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Smolagents
  # Performs web searches and returns results.
  #
  # This tool performs web searches using various backends (DuckDuckGo, Bing)
  # and returns formatted markdown results.
  #
  # @example
  #   tool = WebSearchTool.new(engine: "duckduckgo", max_results: 5)
  #   results = tool.call(query: "Ruby programming")
  #
  class WebSearchTool < Tool
    self.tool_name = "web_search"
    self.tool_description = "Performs a web search for a query and returns a string of the top search results formatted as markdown with titles, links, and descriptions."
    self.input_schema = {
      query: { type: "string", description: "The search query to perform." }
    }
    self.output_type = "string"

    # @return [Integer] Maximum number of results to return
    attr_reader :max_results

    # @return [String] Search engine to use
    attr_reader :engine

    # Create a new WebSearchTool
    #
    # @param max_results [Integer] Maximum number of results
    # @param engine [String] Search engine ("duckduckgo" or "bing")
    def initialize(max_results: 10, engine: "duckduckgo")
      @max_results = max_results
      @engine = engine
      super()
    end

    def forward(query:)
      results = search(query)

      if results.empty?
        raise AgentToolExecutionError.new(
          "No results found! Try a less restrictive/shorter query.",
          nil
        )
      end

      parse_results(results)
    end

    private

    def search(query)
      case @engine
      when "duckduckgo"
        search_duckduckgo(query)
      when "bing"
        search_bing(query)
      else
        raise ArgumentError, "Unsupported engine: #{@engine}"
      end
    end

    def parse_results(results)
      formatted = results.map do |result|
        "[#{result[:title]}](#{result[:link]})\n#{result[:description]}"
      end

      "## Search Results\n\n" + formatted.join("\n\n")
    end

    def search_duckduckgo(query)
      uri = URI("https://lite.duckduckgo.com/lite/")
      uri.query = URI.encode_www_form(q: query)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Mozilla/5.0 (compatible; Smolagents/1.0)"

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise "HTTP error: #{response.code}"
      end

      parse_duckduckgo_html(response.body)
    end

    def parse_duckduckgo_html(html)
      results = []

      # Simple regex-based parsing for DuckDuckGo lite HTML
      # Look for result links and snippets
      html.scan(/<a class="result-link"[^>]*href="([^"]+)"[^>]*>([^<]+)<\/a>/) do |href, title|
        results << {
          title: title.strip,
          link: href,
          description: ""
        }
      end

      # Try to extract descriptions
      html.scan(/<td class="result-snippet">([^<]+)<\/td>/) do |snippet|
        if results.length > 0 && results.last[:description].empty?
          results.last[:description] = snippet[0].strip
        end
      end

      results.first(@max_results)
    end

    def search_bing(query)
      uri = URI("https://www.bing.com/search")
      uri.query = URI.encode_www_form(q: query, format: "rss")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Mozilla/5.0 (compatible; Smolagents/1.0)"

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise "HTTP error: #{response.code}"
      end

      parse_bing_rss(response.body)
    end

    def parse_bing_rss(xml)
      require "rexml/document"

      results = []
      doc = REXML::Document.new(xml)

      doc.elements.each("//item") do |item|
        results << {
          title: item.elements["title"]&.text || "",
          link: item.elements["link"]&.text || "",
          description: item.elements["description"]&.text || ""
        }
      end

      results.first(@max_results)
    end
  end
end
