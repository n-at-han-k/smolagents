# frozen_string_literal: true

require_relative "memory_step"

module Smolagents
  # Represents a task step (new task assignment)
  class TaskStep < MemoryStep
    attr_accessor :task, :task_images

    # @param task [String] The task description
    # @param task_images [Array, nil] Images associated with the task
    def initialize(task:, task_images: nil)
      @task = task
      @task_images = task_images
    end

    # Convert step to chat messages
    # @param summary_mode [Boolean] Whether to use summary mode
    # @return [Array<ChatMessage>]
    def to_messages(summary_mode: false)
      content = [{ type: "text", text: "New task:\n#{@task}" }]

      if @task_images&.any?
        @task_images.each do |image|
          content << { type: "image", image: image }
        end
      end

      [ChatMessage.new(role: MessageRole::USER, content: content)]
    end
  end
end
