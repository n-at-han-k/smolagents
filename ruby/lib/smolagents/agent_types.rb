# frozen_string_literal: true

require_relative "agent_types/agent_type"
require_relative "agent_types/agent_text"
require_relative "agent_types/agent_image"
require_relative "agent_types/agent_audio"

module Smolagents
  # Mapping of type names to agent type classes
  AGENT_TYPE_MAPPING = {
    "string" => AgentText,
    "text" => AgentText,
    "image" => AgentImage,
    "audio" => AgentAudio
  }.freeze

  module_function

  # Convert agent input types to raw values
  #
  # @param args [Array] Positional arguments
  # @param kwargs [Hash] Keyword arguments
  # @return [Array<Array, Hash>] Converted [args, kwargs]
  def handle_agent_input_types(*args, **kwargs)
    converted_args = args.map { |arg| arg.is_a?(AgentType) ? arg.to_raw : arg }
    converted_kwargs = kwargs.transform_values { |v| v.is_a?(AgentType) ? v.to_raw : v }
    [converted_args, converted_kwargs]
  end

  # Convert output to appropriate agent type
  #
  # @param output [Object] Output value to wrap
  # @param output_type [String, nil] Expected output type
  # @return [AgentType, Object] Wrapped output or original if no match
  def handle_agent_output_types(output, output_type: nil)
    if output_type && AGENT_TYPE_MAPPING.key?(output_type)
      return AGENT_TYPE_MAPPING[output_type].new(output)
    end

    # Auto-detect type
    case output
    when String
      AgentText.new(output)
    else
      output
    end
  end
end
