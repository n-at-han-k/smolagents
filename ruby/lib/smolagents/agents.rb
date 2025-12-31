# frozen_string_literal: true

require_relative "agents/action_output"
require_relative "agents/tool_output"
require_relative "agents/prompt_templates"
require_relative "agents/run_result"
require_relative "agents/multi_step_agent"
require_relative "agents/tool_calling_agent"
require_relative "agents/code_agent"

module Smolagents
  # Populate a template string with variables
  #
  # @param template [String] The template string with {{variable}} placeholders
  # @param variables [Hash] Variables to substitute
  # @return [String] The populated template
  def self.populate_template(template, **variables)
    return template if template.nil? || template.empty?

    result = template.dup
    variables.each do |key, value|
      result.gsub!(/\{\{\s*#{key}\s*\}\}/, value.to_s)
    end
    result
  end
end
