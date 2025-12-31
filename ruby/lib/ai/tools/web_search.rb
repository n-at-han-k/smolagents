# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module AI
  module Tools
    # Search the web using DuckDuckGo.
    class WebSearch < Tool
      def initialize(max_results: 10)
        super(
          name: "web_search",
          description: "Search the web and return top results",
          inputs: { query: { type: "string", description: "Search query" } }
        )
        @max_results = max_results
      end

      def call(query:)
        results = search_duckduckgo(query)

        if results.empty?
          "No results found for: #{query}"
        else
          format_results(results)
        end
      rescue => e
        "Search error: #{e.message}"
      end

      private

      def search_duckduckgo(query)
        uri = URI("https://lite.duckduckgo.com/lite/")
        uri.query = URI.encode_www_form(q: query)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "Mozilla/5.0 (compatible; AI Ruby Client)"

        response = http.request(request)
        parse_duckduckgo_html(response.body)
      end

      def parse_duckduckgo_html(html)
        results = []

        # Simple regex parsing for DuckDuckGo lite results
        html.scan(/<a[^>]+class="result-link"[^>]*href="([^"]+)"[^>]*>([^<]+)</).each do |href, title|
          results << { url: href, title: title.strip }
          break if results.size >= @max_results
        end

        # Get snippets
        snippets = html.scan(/<td[^>]+class="result-snippet"[^>]*>([^<]+)</).flatten
        results.each_with_index do |r, i|
          r[:snippet] = snippets[i]&.strip || ""
        end

        results
      end

      def format_results(results)
        lines = ["## Search Results", ""]
        results.each_with_index do |r, i|
          lines << "#{i + 1}. [#{r[:title]}](#{r[:url]})"
          lines << "   #{r[:snippet]}" unless r[:snippet].empty?
          lines << ""
        end
        lines.join("\n")
      end
    end
  end
end
