# frozen_string_literal: true

module Smolagents
  # Abstract base class for memory steps
  #
  # @abstract Subclass and implement {#to_messages}
  class MemoryStep
    # Convert to hash representation
    # @return [Hash]
    def to_h
      instance_variables.each_with_object({}) do |var, hash|
        key = var.to_s.delete("@").to_sym
        value = instance_variable_get(var)
        hash[key] = value.respond_to?(:to_h) ? value.to_h : value
      end
    end

    alias to_hash to_h

    # Convert step to chat messages
    # @param summary_mode [Boolean] Whether to use summary mode
    # @return [Array<ChatMessage>]
    def to_messages(summary_mode: false)
      raise NotImplementedError, "Subclasses must implement #to_messages"
    end
  end
end
