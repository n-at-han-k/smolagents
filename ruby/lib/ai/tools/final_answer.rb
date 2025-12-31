# frozen_string_literal: true

module AI
  module Tools
    # Signal that the task is complete with a final answer.
    class FinalAnswer < Tool
      def initialize
        super(
          name: "final_answer",
          description: "Return the final answer to the task",
          inputs: { answer: { type: "any", description: "The final answer" } }
        )
      end

      def call(answer:)
        answer
      end
    end
  end
end
