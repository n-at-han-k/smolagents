# frozen_string_literal: true

module AI
  # Base class for tools that can be called by the DecisionMaker
  class Tool
    attr_reader :name, :description, :inputs

    def initialize(name:, description:, inputs: {})
      @name = name
      @description = description
      @inputs = inputs
    end

    def call(**args)
      raise NotImplementedError, "Implement #call in your tool"
    end

    def to_s
      args = @inputs.map { |k, v| "#{k}: #{v[:type]}" }.join(", ")
      "#{@name}(#{args}) - #{@description}"
    end
  end
end
