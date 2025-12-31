# frozen_string_literal: true

module Smolagents
  # A tool tailored towards ML pipeline/model usage.
  #
  # This is a base class for tools that wrap machine learning models.
  # It provides a standard interface for preprocessing, model inference,
  # and postprocessing.
  #
  # @abstract Subclass and implement {#encode}, {#forward}, and {#decode}
  #
  # @example Creating a pipeline tool
  #   class TextClassifierTool < Smolagents::PipelineTool
  #     self.tool_name = "text_classifier"
  #     self.tool_description = "Classify text into categories"
  #     self.input_schema = {
  #       text: { type: "string", description: "Text to classify" }
  #     }
  #     self.output_type = "string"
  #     self.default_checkpoint = "distilbert-base-uncased-finetuned-sst-2-english"
  #
  #     def encode(text)
  #       # Tokenize input
  #     end
  #
  #     def forward(inputs)
  #       # Run model inference
  #     end
  #
  #     def decode(outputs)
  #       # Convert outputs to label
  #     end
  #   end
  #
  class PipelineTool < Tool
    class << self
      # The model class to use for loading
      attr_accessor :model_class

      # The default checkpoint to use
      attr_accessor :default_checkpoint

      # The preprocessor class
      attr_accessor :pre_processor_class

      # The postprocessor class
      attr_accessor :post_processor_class
    end

    # Skip forward signature validation for pipeline tools
    self.skip_forward_signature_validation = true

    # Default attributes
    self.tool_description = "This is a pipeline tool"
    self.tool_name = "pipeline"
    self.input_schema = { prompt: { type: "string", description: "Input prompt" } }
    self.output_type = "string"

    # The loaded model
    attr_accessor :model

    # The preprocessor instance
    attr_accessor :pre_processor

    # The postprocessor instance
    attr_accessor :post_processor

    # The device to run on
    attr_accessor :device

    # Device map for distributed inference
    attr_accessor :device_map

    # Additional model loading kwargs
    attr_accessor :model_kwargs

    # Hub loading kwargs
    attr_accessor :hub_kwargs

    # Create a new pipeline tool
    #
    # @param model [String, Object] Model name/checkpoint or loaded model
    # @param pre_processor [String, Object] Preprocessor name or instance
    # @param post_processor [String, Object] Postprocessor name or instance
    # @param device [String, Integer] Device to use
    # @param device_map [String, Hash] Device mapping for distributed inference
    # @param model_kwargs [Hash] Additional model loading arguments
    # @param token [String] HuggingFace token
    # @param hub_kwargs [Hash] Additional hub loading arguments
    def initialize(
      model: nil,
      pre_processor: nil,
      post_processor: nil,
      device: nil,
      device_map: nil,
      model_kwargs: nil,
      token: nil,
      **hub_kwargs
    )
      if model.nil?
        if self.class.default_checkpoint.nil?
          raise ArgumentError, "This tool does not implement a default checkpoint, you need to pass one."
        end
        model = self.class.default_checkpoint
      end

      pre_processor ||= model

      @model = model
      @pre_processor = pre_processor
      @post_processor = post_processor
      @device = device
      @device_map = device_map
      @model_kwargs = model_kwargs || {}
      @model_kwargs[:device_map] = device_map if device_map
      @hub_kwargs = hub_kwargs
      @hub_kwargs[:token] = token

      super()
    end

    # Setup the model and processors.
    # Called automatically on first use.
    def setup
      # Load pre_processor if it's a string (checkpoint name)
      if @pre_processor.is_a?(String)
        # In a full implementation, this would load from HuggingFace
        # For now, we just mark it as needing implementation
        warn "PipelineTool.setup: Loading preprocessor from '#{@pre_processor}' - " \
             "full implementation requires transformers gem"
      end

      # Load model if it's a string
      if @model.is_a?(String)
        warn "PipelineTool.setup: Loading model from '#{@model}' - " \
             "full implementation requires transformers gem"
      end

      # Use pre_processor as post_processor if not set
      @post_processor ||= @pre_processor

      super
    end

    # Encode/preprocess the input.
    #
    # @param raw_inputs [Object] Raw input data
    # @return [Object] Preprocessed inputs ready for the model
    def encode(raw_inputs)
      if @pre_processor.respond_to?(:call)
        @pre_processor.call(raw_inputs)
      else
        raw_inputs
      end
    end

    # Run the model forward pass.
    #
    # @param inputs [Object] Preprocessed inputs
    # @return [Object] Model outputs
    def forward(inputs)
      if @model.respond_to?(:call)
        @model.call(**inputs)
      elsif @model.respond_to?(:predict)
        @model.predict(inputs)
      else
        raise NotImplementedError, "Model must implement #call or #predict"
      end
    end

    # Decode/postprocess the model outputs.
    #
    # @param outputs [Object] Model outputs
    # @return [Object] Final decoded result
    def decode(outputs)
      if @post_processor.respond_to?(:decode)
        @post_processor.decode(outputs)
      elsif @post_processor.respond_to?(:call)
        @post_processor.call(outputs)
      else
        outputs
      end
    end

    # Execute the full pipeline.
    #
    # @param args [Array] Input arguments
    # @param sanitize_inputs_outputs [Boolean] Whether to handle agent types
    # @param kwargs [Hash] Keyword arguments
    # @return [Object] Pipeline result
    def call(*args, sanitize_inputs_outputs: false, **kwargs)
      setup unless @is_initialized

      if sanitize_inputs_outputs
        args, kwargs = handle_agent_input_types(*args, **kwargs)
      end

      encoded_inputs = encode(*args, **kwargs)
      outputs = forward(encoded_inputs)
      decoded_outputs = decode(outputs)

      if sanitize_inputs_outputs
        decoded_outputs = handle_agent_output_types(decoded_outputs, output_type)
      end

      decoded_outputs
    end
  end
end
