# frozen_string_literal: true

require_relative "default_tools/final_answer_tool"
require_relative "default_tools/user_input_tool"
require_relative "default_tools/ruby_interpreter_tool"
require_relative "default_tools/web_search_tool"
require_relative "default_tools/visit_webpage_tool"

module Smolagents
  # Mapping of tool names to tool classes
  TOOL_MAPPING = {
    "ruby_interpreter" => RubyInterpreterTool,
    "final_answer" => FinalAnswerTool,
    "user_input" => UserInputTool,
    "web_search" => WebSearchTool,
    "visit_webpage" => VisitWebpageTool
  }.freeze
end
