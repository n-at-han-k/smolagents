# frozen_string_literal: true

require "json"

module Smolagents
  # MCP (Model Context Protocol) client for connecting to MCP servers.
  #
  # This client manages connections to MCP servers and makes their tools
  # available to smolagents.
  #
  # @note This is a basic implementation. Full MCP support requires
  #   additional Ruby MCP libraries.
  #
  # @example Using with a context block
  #   MCPClient.open(url: "http://localhost:8000/mcp") do |tools|
  #     # tools are now available
  #   end
  #
  # @example Manual connection management
  #   client = MCPClient.new(url: "http://localhost:8000/mcp")
  #   begin
  #     tools = client.get_tools
  #     # use tools
  #   ensure
  #     client.disconnect
  #   end
  #
  class MCPClient
    # @return [String, nil] Server URL
    attr_reader :url

    # @return [Hash] Server parameters
    attr_reader :server_parameters

    # @return [Boolean] Whether to use structured output
    attr_reader :structured_output

    # @return [Array<Tool>, nil] Available tools
    attr_reader :tools

    # Create a new MCP client
    #
    # @param server_parameters [Hash, String] Server configuration
    # @param url [String, nil] Server URL (alternative to server_parameters)
    # @param transport [String] Transport protocol ("streamable-http" or "sse")
    # @param structured_output [Boolean] Enable structured output features
    # @param adapter_kwargs [Hash] Additional adapter options
    def initialize(
      server_parameters: nil,
      url: nil,
      transport: "streamable-http",
      structured_output: false,
      **adapter_kwargs
    )
      @structured_output = structured_output
      @adapter_kwargs = adapter_kwargs

      if server_parameters.is_a?(Hash)
        @server_parameters = server_parameters.dup
        @server_parameters[:transport] ||= transport
        @url = @server_parameters[:url]
      elsif url
        @server_parameters = { url: url, transport: transport }
        @url = url
      else
        raise ArgumentError, "Either server_parameters or url must be provided"
      end

      validate_transport!
      @tools = nil
      @connected = false

      connect
    end

    # Connect to the MCP server
    def connect
      return if @connected

      begin
        @tools = fetch_tools_from_server
        @connected = true
      rescue StandardError => e
        raise ConnectionError.new("Failed to connect to MCP server: #{e.message}")
      end
    end

    # Disconnect from the MCP server
    def disconnect
      @tools = nil
      @connected = false
    end

    # Get available tools from the MCP server
    #
    # @return [Array<Tool>] Available tools
    # @raise [ValueError] If not connected
    def get_tools
      if @tools.nil?
        raise ValueError, "Couldn't retrieve tools from MCP server. Run connect() first."
      end

      @tools
    end

    # Check if connected
    # @return [Boolean]
    def connected?
      @connected
    end

    # Open a connection with automatic cleanup
    #
    # @param kwargs [Hash] Arguments to pass to new
    # @yield [Array<Tool>] Available tools
    # @return [Object] Block result
    def self.open(**kwargs, &block)
      client = new(**kwargs)
      begin
        yield client.get_tools
      ensure
        client.disconnect
      end
    end

    private

    def validate_transport!
      transport = @server_parameters[:transport]
      valid_transports = %w[streamable-http sse]

      unless valid_transports.include?(transport)
        raise ArgumentError, "Unsupported transport: #{transport}. Supported: #{valid_transports.join(', ')}"
      end
    end

    def fetch_tools_from_server
      # This is a placeholder implementation
      # Full MCP support requires proper MCP protocol implementation
      #
      # For now, we return an empty array and log a warning
      warn "[MCPClient] Full MCP protocol support is not yet implemented in Ruby. " \
           "Returning empty tool list. Consider using the Python version for full MCP support."

      []
    end

    # Create a Tool from MCP tool definition
    #
    # @param tool_def [Hash] MCP tool definition
    # @return [Tool]
    def create_tool_from_definition(tool_def)
      name = tool_def[:name] || tool_def["name"]
      description = tool_def[:description] || tool_def["description"]
      input_schema = tool_def[:inputSchema] || tool_def["inputSchema"] || {}

      # Create a dynamic tool class
      tool_class = Class.new(Tool) do
        class << self
          attr_accessor :mcp_definition, :mcp_client
        end

        define_method(:forward) do |**kwargs|
          # Call MCP server to execute tool
          self.class.mcp_client&.execute_tool(name, kwargs)
        end
      end

      tool_class.tool_name = name
      tool_class.tool_description = description
      tool_class.input_schema = convert_json_schema_to_input_schema(input_schema)
      tool_class.output_type = determine_output_type(tool_def)
      tool_class.mcp_definition = tool_def
      tool_class.mcp_client = self

      tool_class.new
    end

    def convert_json_schema_to_input_schema(json_schema)
      properties = json_schema[:properties] || json_schema["properties"] || {}
      required = json_schema[:required] || json_schema["required"] || []

      properties.transform_keys(&:to_sym).transform_values do |prop|
        type = prop[:type] || prop["type"] || "any"
        desc = prop[:description] || prop["description"] || ""
        nullable = !required.include?(prop.keys.first.to_s)

        {
          type: type,
          description: desc,
          nullable: nullable
        }
      end
    end

    def determine_output_type(tool_def)
      if @structured_output && (tool_def[:outputSchema] || tool_def["outputSchema"])
        "object"
      else
        "string"
      end
    end

    # Execute a tool on the MCP server
    #
    # @param tool_name [String] Name of the tool
    # @param arguments [Hash] Tool arguments
    # @return [Object] Tool result
    def execute_tool(tool_name, arguments)
      # Placeholder for MCP tool execution
      # This would make an HTTP request to the MCP server
      warn "[MCPClient] Tool execution not implemented. Tool: #{tool_name}"
      nil
    end
  end

  # Connection error for MCP
  class ConnectionError < AgentError
    def initialize(message, logger = nil)
      super(message, logger)
    end
  end
end
