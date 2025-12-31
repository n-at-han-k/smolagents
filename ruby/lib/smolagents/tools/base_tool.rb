# frozen_string_literal: true

module Smolagents
  # Abstract base class for all tools.
  #
  # All tools must implement the {#call} method.
  #
  # @abstract
  class BaseTool
    # The name of the tool
    # @return [String]
    class << self
      attr_accessor :tool_name
    end

    # Get the tool name
    # @return [String]
    def name
      self.class.tool_name || self.class.name.split("::").last
    end

    # Execute the tool with the given arguments.
    #
    # @param args [Array] Positional arguments
    # @param kwargs [Hash] Keyword arguments
    # @return [Object] The result of the tool execution
    # @abstract
    def call(*args, **kwargs)
      raise NotImplementedError, "Subclasses must implement the #call method"
    end
  end
end
