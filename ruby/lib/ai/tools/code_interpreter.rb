# frozen_string_literal: true

require "stringio"

module AI
  module Tools
    # Execute Ruby code and return the result.
    # This is THE core tool - LLM writes code, we run it.
    class CodeInterpreter < Tool
      def initialize
        super(
          name: "code",
          description: "Execute Ruby code and return the result",
          inputs: { code: { type: "string", description: "Ruby code to execute" } }
        )
        @context = {}
      end

      def call(code:)
        stdout = StringIO.new
        result = nil

        begin
          # Capture stdout
          old_stdout = $stdout
          $stdout = stdout

          # Execute in a binding that persists variables
          result = eval(code, sandbox_binding)

          $stdout = old_stdout
        rescue => e
          $stdout = old_stdout
          return "Error: #{e.class}: #{e.message}"
        end

        output = stdout.string
        if output.empty?
          result.inspect
        else
          "Output:\n#{output}\nResult: #{result.inspect}"
        end
      end

      # Reset the execution context
      def reset!
        @context = {}
        @binding = nil
      end

      private

      def sandbox_binding
        @binding ||= create_sandbox
      end

      def create_sandbox
        # Create a clean binding with access to safe methods
        sandbox = Object.new

        # Inject context for variable persistence
        sandbox.instance_variable_set(:@ctx, @context)

        sandbox.instance_eval do
          def ctx
            @ctx
          end
        end

        sandbox.instance_eval { binding }
      end
    end
  end
end
