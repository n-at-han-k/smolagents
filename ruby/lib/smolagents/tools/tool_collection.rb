# frozen_string_literal: true

module Smolagents
  # A collection of tools that can be loaded from various sources.
  #
  # Tool collections enable loading multiple tools at once for use
  # with an agent.
  #
  # @example Creating a tool collection
  #   tools = [GetWeatherTool.new, SearchTool.new]
  #   collection = Smolagents::ToolCollection.new(tools)
  #
  class ToolCollection
    # The tools in this collection
    # @return [Array<Tool>]
    attr_reader :tools

    # Create a new tool collection
    #
    # @param tools [Array<Tool>] The tools to include
    def initialize(tools)
      @tools = tools
    end

    # Iterate over the tools
    #
    # @yield [Tool] Each tool in the collection
    def each(&block)
      @tools.each(&block)
    end

    # Get a tool by name
    #
    # @param name [String, Symbol] The tool name
    # @return [Tool, nil]
    def [](name)
      name_str = name.to_s
      @tools.find { |t| t.name == name_str }
    end

    # Get the number of tools
    #
    # @return [Integer]
    def size
      @tools.size
    end

    alias length size

    # Check if collection is empty
    #
    # @return [Boolean]
    def empty?
      @tools.empty?
    end

    # Convert to array
    #
    # @return [Array<Tool>]
    def to_a
      @tools.dup
    end

    # Get tool names
    #
    # @return [Array<String>]
    def names
      @tools.map(&:name)
    end

    # Create a hash of tools keyed by name
    #
    # @return [Hash<String, Tool>]
    def to_h
      @tools.each_with_object({}) { |tool, h| h[tool.name] = tool }
    end

    # Add a tool to the collection
    #
    # @param tool [Tool] The tool to add
    # @return [self]
    def add(tool)
      @tools << tool
      self
    end

    alias << add

    # Remove a tool from the collection
    #
    # @param tool_or_name [Tool, String, Symbol] The tool or tool name to remove
    # @return [Tool, nil] The removed tool, or nil if not found
    def remove(tool_or_name)
      if tool_or_name.is_a?(Tool)
        @tools.delete(tool_or_name)
      else
        name_str = tool_or_name.to_s
        tool = @tools.find { |t| t.name == name_str }
        @tools.delete(tool) if tool
        tool
      end
    end

    # Create a ToolCollection from an array of tool classes
    #
    # @param tool_classes [Array<Class>] Tool classes to instantiate
    # @param kwargs [Hash] Arguments to pass to each tool constructor
    # @return [ToolCollection]
    def self.from_classes(tool_classes, **kwargs)
      tools = tool_classes.map { |klass| klass.new(**kwargs) }
      new(tools)
    end

    # Create a ToolCollection from a hash of tool configurations
    #
    # @param configs [Hash<String, Hash>] Tool configurations keyed by name
    # @return [ToolCollection]
    def self.from_config(configs)
      tools = configs.map do |_name, config|
        klass = Object.const_get(config[:class] || config["class"])
        args = config[:args] || config["args"] || {}
        klass.new(**args.transform_keys(&:to_sym))
      end
      new(tools)
    end

    include Enumerable
  end
end
