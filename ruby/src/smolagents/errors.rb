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

module Smolagents
  # Base class for agent-related exceptions
  #
  # All agent errors inherit from this class and automatically log
  # the error message when created
  class AgentError < StandardError
    attr_reader :original_message

    # @param message [String] Error message
    # @param logger [AgentLogger] Logger to log the error
    def initialize(message, logger: nil)
      @original_message = message
      logger&.log_error(message)
      super(message)
    end

    # Convert to hash representation
    # @return [Hash] Hash with error type and message
    def to_h
      {
        type: self.class.name.split("::").last,
        message: @original_message
      }
    end

    alias to_hash to_h
  end

  # Exception raised for errors in parsing agent output
  class AgentParsingError < AgentError; end

  # Exception raised for errors in agent execution
  class AgentExecutionError < AgentError; end

  # Exception raised when agent exceeds maximum steps
  class AgentMaxStepsError < AgentError; end

  # Exception raised when incorrect arguments are passed to a tool
  class AgentToolCallError < AgentExecutionError; end

  # Exception raised when executing a tool fails
  class AgentToolExecutionError < AgentExecutionError; end

  # Exception raised for errors in LLM generation
  class AgentGenerationError < AgentError; end

  # Exception raised when the Python interpreter encounters an error
  class InterpreterError < AgentError; end
end
