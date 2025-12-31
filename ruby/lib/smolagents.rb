# frozen_string_literal: true

# Copyright 2024 HuggingFace Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative "smolagents/version"
require_relative "smolagents/errors"
require_relative "smolagents/utils"
require_relative "smolagents/monitoring"
require_relative "smolagents/models"
require_relative "smolagents/agent_types"
require_relative "smolagents/memory"
require_relative "smolagents/tools"
require_relative "smolagents/tool_validation"
require_relative "smolagents/agents"
require_relative "smolagents/model_clients"
require_relative "smolagents/default_tools"
require_relative "smolagents/mcp_client"
require_relative "smolagents/cli"

# Smolagents - A lightweight agent framework for building AI agents
#
# This is the Ruby port of the HuggingFace smolagents library.
# It provides tools for creating AI agents with tools and memory.
#
# @example Basic usage
#   require "smolagents"
#
#   # Create an agent memory
#   memory = Smolagents::AgentMemory.new(system_prompt: "You are a helpful assistant.")
#
#   # Track token usage
#   usage = Smolagents::TokenUsage.new(input_tokens: 100, output_tokens: 50)
#
#   # Create timing info
#   timing = Smolagents::Timing.start_now
#   # ... do work ...
#   timing.stop!
#
module Smolagents
  class Error < StandardError; end

  # Module-level methods for convenience
  module_function

  # Create a new agent memory with the given system prompt
  #
  # @param system_prompt [String] System prompt for the agent
  # @return [AgentMemory]
  def create_memory(system_prompt:)
    AgentMemory.new(system_prompt: system_prompt)
  end

  # Create a new agent logger
  #
  # @param level [Integer] Log level (default: LogLevel::INFO)
  # @return [AgentLogger]
  def create_logger(level: LogLevel::INFO)
    AgentLogger.new(level: level)
  end
end
