# frozen_string_literal: true

module Smolagents
  # Provides a final answer to the given problem.
  #
  # This tool is used by agents to signal that they have completed
  # their task and are returning the final result.
  #
  # @example
  #   tool = FinalAnswerTool.new
  #   result = tool.call(answer: "42")
  #
  class FinalAnswerTool < Tool
    self.tool_name = "final_answer"
    self.tool_description = "Provides a final answer to the given problem."
    self.input_schema = {
      answer: { type: "any", description: "The final answer to the problem" }
    }
    self.output_type = "any"

    def forward(answer:)
      answer
    end
  end
end
