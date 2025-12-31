# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module AI
  module Clients
    # Base client with shared HTTP logic
    class Base
      attr_reader :api_key, :base_url, :model

      def initialize(api_key:, base_url:, model: nil)
        @api_key  = api_key
        @base_url = base_url
        @model    = model
      end

      # Make an LLM call with a message and optional history
      def call(message, history: [], **opts)
        raise NotImplementedError, "Subclass must implement #call"
      end

      # List available models
      def available_models
        raise NotImplementedError, "Subclass must implement #available_models"
      end

      protected

      def post(path, body, headers: {})
        uri = URI.join(@base_url, path)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"

        request = Net::HTTP::Post.new(uri.path)
        request["Content-Type"] = "application/json"
        default_headers.merge(headers).each { |k, v| request[k] = v }
        request.body = body.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise "API error #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      end

      def get(path, headers: {})
        uri = URI.join(@base_url, path)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"

        request = Net::HTTP::Get.new(uri.path)
        default_headers.merge(headers).each { |k, v| request[k] = v }

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise "API error #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      end

      def default_headers
        {}
      end
    end
  end
end
