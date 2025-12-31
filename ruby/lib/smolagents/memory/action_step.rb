# frozen_string_literal: true

require_relative "memory_step"

module Smolagents
  # Represents an action step in the agent's execution
  class ActionStep < MemoryStep
    attr_accessor :step_number, :timing, :model_input_messages, :tool_calls,
                  :error, :model_output_message, :model_output, :code_action,
                  :observations, :observations_images, :action_output,
                  :token_usage, :is_final_answer

    # @param step_number [Integer] Step number in the execution
    # @param timing [Timing] Timing information
    # @param model_input_messages [Array<ChatMessage>, nil] Input messages to the model
    # @param tool_calls [Array<ToolCall>, nil] Tool calls made
    # @param error [AgentError, nil] Error if any occurred
    # @param model_output_message [ChatMessage, nil] Output message from model
    # @param model_output [String, Array<Hash>, nil] Raw model output
    # @param code_action [String, nil] Code that was executed
    # @param observations [String, nil] Observations from execution
    # @param observations_images [Array, nil] Images from observations
    # @param action_output [Object, nil] Output from the action
    # @param token_usage [TokenUsage, nil] Token usage for this step
    # @param is_final_answer [Boolean] Whether this is the final answer
    def initialize(
      step_number:,
      timing:,
      model_input_messages: nil,
      tool_calls: nil,
      error: nil,
      model_output_message: nil,
      model_output: nil,
      code_action: nil,
      observations: nil,
      observations_images: nil,
      action_output: nil,
      token_usage: nil,
      is_final_answer: false
    )
      @step_number = step_number
      @timing = timing
      @model_input_messages = model_input_messages
      @tool_calls = tool_calls
      @error = error
      @model_output_message = model_output_message
      @model_output = model_output
      @code_action = code_action
      @observations = observations
      @observations_images = observations_images
      @action_output = action_output
      @token_usage = token_usage
      @is_final_answer = is_final_answer
    end

    # Convert to hash representation
    # @return [Hash]
    def to_h
      {
        step_number: @step_number,
        timing: @timing.to_h,
        model_input_messages: @model_input_messages&.map { |m| Utils.make_json_serializable(Smolagents.get_dict_from_nested_dataclasses(m)) },
        tool_calls: @tool_calls&.map(&:to_h) || [],
        error: @error&.to_h,
        model_output_message: @model_output_message ? Utils.make_json_serializable(Smolagents.get_dict_from_nested_dataclasses(@model_output_message)) : nil,
        model_output: @model_output,
        code_action: @code_action,
        observations: @observations,
        observations_images: @observations_images&.map(&:to_s),
        action_output: Utils.make_json_serializable(@action_output),
        token_usage: @token_usage&.to_h,
        is_final_answer: @is_final_answer
      }
    end

    # Convert step to chat messages
    # @param summary_mode [Boolean] Whether to use summary mode
    # @return [Array<ChatMessage>]
    def to_messages(summary_mode: false)
      messages = []

      if @model_output && !summary_mode
        messages << ChatMessage.new(
          role: MessageRole::ASSISTANT,
          content: [{ type: "text", text: @model_output.to_s.strip }]
        )
      end

      if @tool_calls
        messages << ChatMessage.new(
          role: MessageRole::TOOL_CALL,
          content: [
            {
              type: "text",
              text: "Calling tools:\n#{@tool_calls.map(&:to_h)}"
            }
          ]
        )
      end

      if @observations_images&.any?
        messages << ChatMessage.new(
          role: MessageRole::USER,
          content: @observations_images.map { |image| { type: "image", image: image } }
        )
      end

      if @observations
        messages << ChatMessage.new(
          role: MessageRole::TOOL_RESPONSE,
          content: [{ type: "text", text: "Observation:\n#{@observations}" }]
        )
      end

      if @error
        error_message = "Error:\n#{@error}\n" \
                        "Now let's retry: take care not to repeat previous errors! " \
                        "If you have retried several times, try a completely different approach.\n"
        message_content = @tool_calls&.first ? "Call id: #{@tool_calls.first.id}\n" : ""
        message_content += error_message

        messages << ChatMessage.new(
          role: MessageRole::TOOL_RESPONSE,
          content: [{ type: "text", text: message_content }]
        )
      end

      messages
    end
  end
end
