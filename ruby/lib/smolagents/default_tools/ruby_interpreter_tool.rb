# frozen_string_literal: true

module Smolagents
  # Evaluates Ruby code. Equivalent to Python's PythonInterpreterTool.
  #
  # This tool safely evaluates Ruby code snippets and returns the result.
  #
  # @example
  #   tool = RubyInterpreterTool.new
  #   result = tool.call(code: "2 + 2")
  #
  class RubyInterpreterTool < Tool
    self.tool_name = "ruby_interpreter"
    self.tool_description = "This is a tool that evaluates Ruby code. It can be used to perform calculations."
    self.input_schema = {
      code: {
        type: "string",
        description: "The Ruby code to run in the interpreter. All variables used must be defined in this snippet."
      }
    }
    self.output_type = "string"

    # Base allowed modules/gems
    BASE_BUILTIN_MODULES = %w[
      base64 json time date yaml csv uri cgi digest
      set ostruct securerandom fileutils tempfile
      stringio matrix bigdecimal
    ].freeze

    # @return [Array<String>] Authorized requires/gems
    attr_reader :authorized_imports

    # Create a new RubyInterpreterTool
    #
    # @param authorized_imports [Array<String>, nil] Additional allowed imports
    def initialize(authorized_imports: nil)
      @authorized_imports = if authorized_imports.nil?
                              BASE_BUILTIN_MODULES.dup
                            else
                              (BASE_BUILTIN_MODULES + authorized_imports).uniq
                            end
      super()
    end

    def forward(code:)
      output = StringIO.new
      result = nil

      begin
        # Capture stdout
        old_stdout = $stdout
        $stdout = output

        # Create a sandboxed binding
        sandbox = create_sandbox

        # Evaluate the code
        result = sandbox.eval(code)
      rescue StandardError => e
        result = "Error: #{e.class}: #{e.message}"
      ensure
        $stdout = old_stdout
      end

      stdout_content = output.string
      "Stdout:\n#{stdout_content}\nOutput: #{result}"
    end

    private

    def create_sandbox
      # Create a clean binding with basic methods
      sandbox = binding

      # Add commonly used math methods
      sandbox.local_variable_set(:Math, Math)

      sandbox
    end
  end
end
