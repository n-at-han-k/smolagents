# frozen_string_literal: true

require "optparse"
require "io/console"

module Smolagents
  # Command-line interface for smolagents.
  #
  # This module provides a CLI for running agents interactively
  # or with command-line arguments.
  #
  # @example Running from command line
  #   ruby -r smolagents -e "Smolagents::CLI.run"
  #   # or
  #   smolagents "What is 2+2?"
  #
  module CLI
    # Default prompt for demo
    LEOPARD_PROMPT = "How many seconds would it take for a leopard at full speed to run through Pont des Arts?"

    # CLI options
    Options = Struct.new(
      :prompt, :model_type, :action_type, :model_id, :imports,
      :tools, :verbosity_level, :provider, :api_base, :api_key,
      keyword_init: true
    )

    class << self
      # Run the CLI
      def run(args = ARGV)
        options = parse_arguments(args)

        if options.prompt.nil?
          run_interactive_mode
        else
          run_agent(options)
        end
      end

      # Parse command line arguments
      # @param args [Array<String>] Command line arguments
      # @return [Options] Parsed options
      def parse_arguments(args)
        options = Options.new(
          prompt: nil,
          model_type: "OpenAIModel",
          action_type: "code",
          model_id: "gpt-4",
          imports: [],
          tools: ["web_search"],
          verbosity_level: 1,
          provider: nil,
          api_base: nil,
          api_key: nil
        )

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: smolagents [options] [prompt]"
          opts.separator ""
          opts.separator "Run a CodeAgent or ToolCallingAgent with the specified parameters."
          opts.separator ""
          opts.separator "Options:"

          opts.on("--model-type TYPE", "Model type (OpenAIModel, AnthropicModel)") do |v|
            options.model_type = v
          end

          opts.on("--action-type TYPE", "Action type (code, tool_calling)") do |v|
            options.action_type = v
          end

          opts.on("--model-id ID", "Model ID to use") do |v|
            options.model_id = v
          end

          opts.on("--imports x,y,z", Array, "Comma-separated list of imports to authorize") do |v|
            options.imports = v
          end

          opts.on("--tools x,y,z", Array, "Comma-separated list of tools") do |v|
            options.tools = v
          end

          opts.on("--verbosity-level LEVEL", Integer, "Verbosity level (0-2)") do |v|
            options.verbosity_level = v
          end

          opts.on("--provider PROVIDER", "Inference provider") do |v|
            options.provider = v
          end

          opts.on("--api-base URL", "Base URL for the API") do |v|
            options.api_base = v
          end

          opts.on("--api-key KEY", "API key for authentication") do |v|
            options.api_key = v
          end

          opts.on("-h", "--help", "Show this help message") do
            puts opts
            exit
          end

          opts.on("-v", "--version", "Show version") do
            puts "smolagents #{Smolagents::VERSION}"
            exit
          end
        end

        remaining = parser.parse(args)
        options.prompt = remaining.first unless remaining.empty?

        options
      end

      # Run in interactive mode
      def run_interactive_mode
        print_header

        puts "\n\e[33mWelcome to smolagents!\e[0m Let's set up your agent step by step.\n\n"

        # Get action type
        puts "\e[33m═══ Configuration ═══\e[0m"
        action_type = prompt_with_default(
          "What action type would you like to use? (code/tool_calling)",
          "code"
        )

        # Show available tools
        show_tools_table

        tools_input = prompt_with_default(
          "Select tools for your agent (space-separated)",
          "web_search"
        )
        tools = tools_input.split

        # Get model configuration
        puts "\n\e[33mModel Configuration:\e[0m"
        model_type = prompt_with_default(
          "Model type",
          "OpenAIModel"
        )

        model_id = prompt_with_default(
          "Model ID",
          "gpt-4"
        )

        # Optional advanced configuration
        provider = nil
        api_base = nil
        api_key = nil
        imports = []

        if confirm?("Configure advanced options?", false)
          provider = prompt_with_default("Provider", "")
          api_base = prompt_with_default("API Base URL", "")
          api_key = prompt_password("API Key (hidden)")

          imports_input = prompt_with_default("Additional imports (space-separated)", "")
          imports = imports_input.split unless imports_input.empty?
        end

        # Get prompt
        prompt = prompt_with_default(
          "What task would you like the agent to perform?",
          LEOPARD_PROMPT
        )

        options = Options.new(
          prompt: prompt,
          model_type: model_type,
          action_type: action_type,
          model_id: model_id,
          imports: imports,
          tools: tools,
          verbosity_level: 1,
          provider: provider.to_s.empty? ? nil : provider,
          api_base: api_base.to_s.empty? ? nil : api_base,
          api_key: api_key.to_s.empty? ? nil : api_key
        )

        run_agent(options)
      end

      # Run the agent with the given options
      # @param options [Options] CLI options
      def run_agent(options)
        puts "\n\e[36m═══ Starting Agent ═══\e[0m\n\n"

        model = load_model(
          options.model_type,
          options.model_id,
          api_base: options.api_base,
          api_key: options.api_key,
          provider: options.provider
        )

        available_tools = load_tools(options.tools)

        agent = if options.action_type == "code"
                  CodeAgent.new(
                    tools: available_tools,
                    model: model,
                    additional_authorized_imports: options.imports,
                    verbosity_level: options.verbosity_level
                  )
                else
                  ToolCallingAgent.new(
                    tools: available_tools,
                    model: model,
                    verbosity_level: options.verbosity_level
                  )
                end

        result = agent.run(task: options.prompt)

        puts "\n\e[32m═══ Result ═══\e[0m"
        puts result
      rescue StandardError => e
        puts "\e[31mError: #{e.message}\e[0m"
        puts e.backtrace.first(5).join("\n") if options.verbosity_level > 1
        exit 1
      end

      private

      def print_header
        puts "\e[35m╔════════════════════════════════╗\e[0m"
        puts "\e[35m║  \e[1m🤖 Smolagents CLI\e[0m\e[35m             ║\e[0m"
        puts "\e[35m║  \e[2mIntelligent agents at service\e[0m\e[35m ║\e[0m"
        puts "\e[35m╚════════════════════════════════╝\e[0m"
      end

      def show_tools_table
        puts "\n\e[33m🛠️  Available Tools:\e[0m"
        puts "┌─────────────────────┬────────────────────────────────────────────────┐"
        puts "│ \e[1mTool Name\e[0m           │ \e[1mDescription\e[0m                                    │"
        puts "├─────────────────────┼────────────────────────────────────────────────┤"

        TOOL_MAPPING.each do |name, klass|
          desc = begin
            klass.tool_description.to_s[0, 45]
          rescue StandardError
            "Built-in tool"
          end
          puts "│ #{name.ljust(19)} │ #{desc.ljust(46)} │"
        end

        puts "└─────────────────────┴────────────────────────────────────────────────┘"
        puts "\n\e[2mEnter tool names separated by spaces\e[0m"
      end

      def prompt_with_default(message, default)
        print "\e[1m#{message}\e[0m [#{default}]: "
        input = gets.chomp
        input.empty? ? default : input
      end

      def prompt_password(message)
        print "\e[1m#{message}\e[0m: "
        password = $stdin.noecho(&:gets).chomp
        puts
        password
      rescue StandardError
        gets.chomp
      end

      def confirm?(message, default = true)
        default_str = default ? "Y/n" : "y/N"
        print "\e[1m#{message}\e[0m [#{default_str}]: "
        input = gets.chomp.downcase
        return default if input.empty?

        %w[y yes true 1].include?(input)
      end

      def load_model(model_type, model_id, api_base: nil, api_key: nil, provider: nil)
        case model_type
        when "OpenAIModel"
          OpenAIModel.new(
            model_id: model_id,
            api_base: api_base,
            api_key: api_key || ENV["OPENAI_API_KEY"]
          )
        when "AnthropicModel"
          AnthropicModel.new(
            model_id: model_id,
            api_key: api_key || ENV["ANTHROPIC_API_KEY"]
          )
        else
          raise ArgumentError, "Unsupported model type: #{model_type}"
        end
      end

      def load_tools(tool_names)
        tool_names.map do |name|
          if TOOL_MAPPING.key?(name)
            TOOL_MAPPING[name].new
          else
            raise ArgumentError, "Unknown tool: #{name}. Available: #{TOOL_MAPPING.keys.join(', ')}"
          end
        end
      end
    end
  end
end
