# frozen_string_literal: true

module AI
  module Tools
    # Ask the user for input.
    class UserInput < Tool
      def initialize
        super(
          name: "ask_user",
          description: "Ask the user a question and wait for their response",
          inputs: { question: { type: "string", description: "The question to ask" } }
        )
      end

      def call(question:)
        print "#{question} => "
        gets.chomp
      end
    end
  end
end
