# frozen_string_literal: true

module AI
  # DecisionMaker replaces the human decision process.
  # It does NOT loop. It receives input and decides the next action.
  # The loop lives in your script - you control it.
  #
  # Example:
  #   dm = AI::DecisionMaker.new(tools: [Calculator.new])
  #
  #   loop do
  #     action = dm.decide
  #     case action.type
  #     when :call_llm   then dm.observe(session.chat(action.prompt))
  #     when :call_tool  then dm.observe(action.tool.call(**action.args))
  #     when :answer     then break action.result
  #     end
  #   end
  #
  class DecisionMaker
    Action = Struct.new(:type, :prompt, :tool, :args, :result, keyword_init: true)

    attr_reader :tools, :context, :state

    def initialize(tools: [], system_prompt: nil)
      @tools = tools.each_with_object({}) { |t, h| h[t.name] = t }
      @system_prompt = system_prompt || default_system_prompt
      @context = []
      @state = :idle
      @pending_task = nil
    end

    # Start a new task
    def start(task)
      @pending_task = task
      @context = []
      @state = :thinking
      decide
    end

    # Observe a result (from LLM or tool) and decide next action
    def observe(result)
      @context << result
      decide
    end

    # Decide the next action based on current state and context
    def decide
      case @state
      when :idle
        Action.new(type: :none)

      when :thinking
        # Need to consult LLM
        @state = :waiting_llm
        Action.new(type: :call_llm, prompt: build_prompt)

      when :waiting_llm
        # Got LLM response, parse it
        response = @context.last
        parse_llm_response(response)

      when :waiting_tool
        # Got tool result, feed back to LLM
        @state = :thinking
        decide

      when :done
        Action.new(type: :answer, result: @final_answer)

      else
        Action.new(type: :error, result: "Unknown state: #{@state}")
      end
    end

    private

    def build_prompt
      parts = [@system_prompt]
      parts << "Task: #{@pending_task}" if @pending_task

      @context.each_with_index do |ctx, i|
        parts << "Observation #{i + 1}: #{ctx}"
      end

      parts.join("\n\n")
    end

    def parse_llm_response(response)
      # Check for final answer
      if response =~ /FINAL_ANSWER:\s*(.+)/m
        @final_answer = $1.strip
        @state = :done
        return Action.new(type: :answer, result: @final_answer)
      end

      # Check for tool call
      if response =~ /TOOL:\s*(\w+)\s*ARGS:\s*(\{.+?\})/m
        tool_name = $1.strip
        args = JSON.parse($2, symbolize_names: true)
        tool = @tools[tool_name]

        if tool
          @state = :waiting_tool
          return Action.new(type: :call_tool, tool: tool, args: args)
        else
          @context << "Error: Unknown tool '#{tool_name}'"
          @state = :thinking
          return decide
        end
      end

      # No clear action, keep thinking
      @state = :thinking
      decide
    end

    def default_system_prompt
      tool_docs = @tools.values.map { |t| "- #{t.name}: #{t.description}" }.join("\n")

      <<~PROMPT
        You are an AI assistant that solves tasks step by step.

        Available tools:
        #{tool_docs}

        To use a tool, respond with:
        TOOL: tool_name
        ARGS: {"arg1": "value1"}

        When you have the final answer, respond with:
        FINAL_ANSWER: your answer here

        Think step by step and use tools when needed.
      PROMPT
    end
  end
end
