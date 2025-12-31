# frozen_string_literal: true

module Smolagents
  # Holds extended information about an agent run.
  #
  # @attr output [Object, nil] The final output of the agent run
  # @attr state [String] The final state ("success" or "max_steps_error")
  # @attr steps [Array<Hash>] The agent's memory as a list of steps
  # @attr token_usage [TokenUsage, nil] Token usage during the run
  # @attr timing [Timing] Timing details of the run
  class RunResult
    # @return [Object, nil] The final output
    attr_accessor :output

    # @return [String] The final state
    attr_accessor :state

    # @return [Array<Hash>] The steps
    attr_accessor :steps

    # @return [TokenUsage, nil] Token usage
    attr_accessor :token_usage

    # @return [Timing] Timing details
    attr_accessor :timing

    # Create a new RunResult
    #
    # @param output [Object, nil] The final output
    # @param state [String] The final state
    # @param steps [Array<Hash>] The steps
    # @param token_usage [TokenUsage, nil] Token usage
    # @param timing [Timing] Timing details
    # @param messages [Array<Hash>] Deprecated: Use steps instead
    def initialize(output: nil, state: nil, steps: nil, token_usage: nil, timing: nil, messages: nil)
      if messages && steps
        raise ArgumentError, "Cannot specify both 'messages' and 'steps' parameters. Use 'steps' instead."
      end

      if messages
        warn "[DEPRECATION] Parameter 'messages' is deprecated. Use 'steps' instead."
        steps = messages
      end

      @output = output
      @state = state
      @steps = steps || []
      @token_usage = token_usage
      @timing = timing
    end

    # Backward compatibility for messages
    # @deprecated Use {#steps} instead
    # @return [Array<Hash>]
    def messages
      warn "[DEPRECATION] Parameter 'messages' is deprecated. Use 'steps' instead."
      @steps
    end

    # Check if the run was successful
    # @return [Boolean]
    def success?
      @state == "success"
    end

    # Check if the run hit max steps
    # @return [Boolean]
    def max_steps_error?
      @state == "max_steps_error"
    end

    # Convert to hash
    # @return [Hash]
    def to_h
      {
        output: @output,
        state: @state,
        steps: @steps,
        token_usage: @token_usage&.to_h,
        timing: @timing&.to_h
      }
    end

    alias dict to_h
  end
end
