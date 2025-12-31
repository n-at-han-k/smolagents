# frozen_string_literal: true

module Smolagents
  module Core
    # Execute Ruby code with tools available as methods.
    class Executor
      Result = Struct.new(:output, :final_answer?, :logs, keyword_init: true)

      def initialize(tools)
        @tools = tools.each_with_object({}) { |t, h| h[t.name] = t }
      end

      def run(code)
        @final_answer = nil
        @logs = StringIO.new

        sandbox = create_sandbox
        output = nil

        begin
          old_stdout = $stdout
          $stdout = @logs
          output = sandbox.eval(code)
        rescue => e
          output = "Error: #{e.message}"
        ensure
          $stdout = old_stdout
        end

        Result.new(
          output: @final_answer || output,
          final_answer?: !@final_answer.nil?,
          logs: @logs.string
        )
      end

      private

      def create_sandbox
        binding.tap do |b|
          # Inject tools as methods
          @tools.each do |name, tool|
            b.local_variable_set(name.to_sym, ->(**args) { tool.call(**args) })
          end

          # Special handling for final_answer
          b.local_variable_set(:final_answer, ->(answer) {
            @final_answer = answer
          })
        end
      end
    end
  end
end
