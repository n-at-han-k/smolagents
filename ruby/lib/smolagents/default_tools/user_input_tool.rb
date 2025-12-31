# frozen_string_literal: true

module Smolagents
  # Asks for user's input on a specific question.
  #
  # This tool prompts the user for input and returns their response.
  #
  # @example
  #   tool = UserInputTool.new
  #   response = tool.call(question: "What is your name?")
  #
  class UserInputTool < Tool
    self.tool_name = "user_input"
    self.tool_description = "Asks for user's input on a specific question"
    self.input_schema = {
      question: { type: "string", description: "The question to ask the user" }
    }
    self.output_type = "string"

    def forward(question:)
      print "#{question} => Type your answer here: "
      gets.chomp
    end
  end
end
