# frozen_string_literal: true

module Smolagents
  module Core
    # Minimal tool interface.
    # Subclass and implement #call.
    class Tool
      attr_accessor :name, :description, :inputs

      def initialize(name:, description:, inputs: {})
        @name = name
        @description = description
        @inputs = inputs
      end

      def call(**args)
        raise NotImplementedError, "Implement #call in your tool"
      end

      # Generate the function signature for the system prompt
      def to_signature
        args = @inputs.map { |k, v| "#{k}: #{v[:type]}" }.join(", ")
        "#{@name}(#{args}) - #{@description}"
      end
    end

    # The final_answer tool - signals completion
    class FinalAnswer < Tool
      def initialize
        super(name: "final_answer", description: "Return the final answer", inputs: { answer: { type: "any" } })
      end

      def call(answer:)
        answer
      end
    end
  end
end
