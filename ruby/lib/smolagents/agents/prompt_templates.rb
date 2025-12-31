# frozen_string_literal: true

module Smolagents
  # Prompt templates for the planning step.
  class PlanningPromptTemplate
    # @return [String] Initial plan prompt
    attr_accessor :initial_plan

    # @return [String] Update plan pre-messages prompt
    attr_accessor :update_plan_pre_messages

    # @return [String] Update plan post-messages prompt
    attr_accessor :update_plan_post_messages

    def initialize(initial_plan: "", update_plan_pre_messages: "", update_plan_post_messages: "")
      @initial_plan = initial_plan
      @update_plan_pre_messages = update_plan_pre_messages
      @update_plan_post_messages = update_plan_post_messages
    end

    def to_h
      {
        initial_plan: @initial_plan,
        update_plan_pre_messages: @update_plan_pre_messages,
        update_plan_post_messages: @update_plan_post_messages
      }
    end

    def [](key)
      to_h[key.to_sym]
    end
  end

  # Prompt templates for managed agents.
  class ManagedAgentPromptTemplate
    # @return [String] Task prompt
    attr_accessor :task

    # @return [String] Report prompt
    attr_accessor :report

    def initialize(task: "", report: "")
      @task = task
      @report = report
    end

    def to_h
      { task: @task, report: @report }
    end

    def [](key)
      to_h[key.to_sym]
    end
  end

  # Prompt templates for the final answer.
  class FinalAnswerPromptTemplate
    # @return [String] Pre-messages prompt
    attr_accessor :pre_messages

    # @return [String] Post-messages prompt
    attr_accessor :post_messages

    def initialize(pre_messages: "", post_messages: "")
      @pre_messages = pre_messages
      @post_messages = post_messages
    end

    def to_h
      { pre_messages: @pre_messages, post_messages: @post_messages }
    end

    def [](key)
      to_h[key.to_sym]
    end
  end

  # Main prompt templates container for agents.
  class PromptTemplates
    # @return [String] System prompt
    attr_accessor :system_prompt

    # @return [PlanningPromptTemplate] Planning prompt templates
    attr_accessor :planning

    # @return [ManagedAgentPromptTemplate] Managed agent prompt templates
    attr_accessor :managed_agent

    # @return [FinalAnswerPromptTemplate] Final answer prompt templates
    attr_accessor :final_answer

    def initialize(
      system_prompt: "",
      planning: nil,
      managed_agent: nil,
      final_answer: nil
    )
      @system_prompt = system_prompt
      @planning = planning || PlanningPromptTemplate.new
      @managed_agent = managed_agent || ManagedAgentPromptTemplate.new
      @final_answer = final_answer || FinalAnswerPromptTemplate.new
    end

    def to_h
      {
        system_prompt: @system_prompt,
        planning: @planning.to_h,
        managed_agent: @managed_agent.to_h,
        final_answer: @final_answer.to_h
      }
    end

    def [](key)
      case key.to_sym
      when :system_prompt then @system_prompt
      when :planning then @planning
      when :managed_agent then @managed_agent
      when :final_answer then @final_answer
      end
    end

    def []=(key, value)
      case key.to_sym
      when :system_prompt then @system_prompt = value
      when :planning then @planning = value
      when :managed_agent then @managed_agent = value
      when :final_answer then @final_answer = value
      end
    end

    def keys
      %i[system_prompt planning managed_agent final_answer]
    end

    # Create from a hash (e.g., from YAML)
    # @param hash [Hash] The hash to convert
    # @return [PromptTemplates]
    def self.from_hash(hash)
      return new if hash.nil?

      hash = hash.transform_keys(&:to_sym)

      planning = if hash[:planning]
                   ph = hash[:planning].transform_keys(&:to_sym)
                   PlanningPromptTemplate.new(**ph)
                 end

      managed_agent = if hash[:managed_agent]
                        mh = hash[:managed_agent].transform_keys(&:to_sym)
                        ManagedAgentPromptTemplate.new(**mh)
                      end

      final_answer = if hash[:final_answer]
                       fh = hash[:final_answer].transform_keys(&:to_sym)
                       FinalAnswerPromptTemplate.new(**fh)
                     end

      new(
        system_prompt: hash[:system_prompt] || "",
        planning: planning,
        managed_agent: managed_agent,
        final_answer: final_answer
      )
    end
  end

  # Empty prompt templates constant
  EMPTY_PROMPT_TEMPLATES = PromptTemplates.new.freeze
end
