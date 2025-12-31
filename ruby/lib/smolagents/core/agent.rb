# frozen_string_literal: true

module Smolagents
  module Core
    # Minimal code-generating agent.
    # LLM writes Ruby code → we execute it → repeat until final_answer.
    class Agent
      def initialize(model:, provider: "openai", tools: [], max_steps: 10, verbose: false)
        @model = Model.new(provider: provider, model: model)
        @tools = tools
        @max_steps = max_steps
        @verbose = verbose
        @executor = Executor.new(@tools)
      end

      def run(task)
        messages = [
          { role: "system", content: system_prompt },
          { role: "user", content: task }
        ]

        @max_steps.times do |step|
          log "Step #{step + 1}..."

          response = @model.generate(messages)
          log "LLM response:\n#{response}" if @verbose

          code = extract_code(response)
          unless code
            messages << { role: "assistant", content: response }
            messages << { role: "user", content: "Please provide code in a ```ruby block." }
            next
          end

          log "Executing:\n#{code}" if @verbose

          result = @executor.run(code)
          log "Output: #{result.output}"

          return result.output if result.final_answer?

          messages << { role: "assistant", content: response }
          messages << { role: "user", content: "Execution output:\n#{result.logs}\nResult: #{result.output}" }
        end

        "Max steps reached without final answer"
      end

      private

      def system_prompt
        tool_docs = @tools.map(&:to_signature).join("\n")

        <<~PROMPT
          You are an AI assistant that solves tasks by writing Ruby code.

          Available tools (call as methods):
          #{tool_docs}
          final_answer(answer) - Call this with your final answer when done

          Write your code in a ```ruby block. The code will be executed and you'll see the output.
          When you have the answer, call final_answer(your_answer).
        PROMPT
      end

      def extract_code(text)
        match = text.match(/```ruby\s*(.*?)```/m)
        match ? match[1].strip : nil
      end

      def log(msg)
        puts msg if @verbose || !msg.start_with?("LLM")
      end
    end
  end

  # Convenience alias at top level
  Agent = Core::Agent
end
