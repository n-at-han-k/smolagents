# frozen_string_literal: true

module Smolagents
  # Registry for callbacks that are called at each step of the agent's execution
  #
  # Callbacks are registered by passing a step class and a callback function.
  #
  # @example
  #   registry = CallbackRegistry.new
  #   registry.register(ActionStep) { |step| puts "Action: #{step.step_number}" }
  class CallbackRegistry
    def initialize
      @callbacks = {}
    end

    # Register a callback for a step class
    #
    # @param step_class [Class] Step class to register the callback for
    # @param callback [Proc] Callback to register
    # @yield [MemoryStep] Block to use as callback
    # @return [void]
    def register(step_class, callback = nil, &block)
      callback ||= block
      raise ArgumentError, "Callback required" unless callback

      @callbacks[step_class] ||= []
      @callbacks[step_class] << callback
    end

    # Call callbacks registered for a step type
    #
    # @param memory_step [MemoryStep] Step to call callbacks for
    # @param kwargs [Hash] Additional arguments to pass to callbacks
    # @return [void]
    def callback(memory_step, **kwargs)
      # Walk up the class hierarchy to find registered callbacks
      memory_step.class.ancestors.each do |ancestor_class|
        @callbacks[ancestor_class]&.each do |cb|
          if cb.arity == 1 || cb.parameters.count { |type, _| %i[req opt].include?(type) } == 1
            cb.call(memory_step)
          else
            cb.call(memory_step, **kwargs)
          end
        end
      end
    end

    # Check if any callbacks are registered
    # @return [Boolean]
    def empty?
      @callbacks.empty? || @callbacks.values.all?(&:empty?)
    end

    # Get the number of registered callbacks
    # @return [Integer]
    def size
      @callbacks.values.sum(&:size)
    end
  end
end
