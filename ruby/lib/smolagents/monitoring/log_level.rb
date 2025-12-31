# frozen_string_literal: true

module Smolagents
  # Log levels for agent output control
  module LogLevel
    OFF = -1   # No output
    ERROR = 0  # Only errors
    INFO = 1   # Normal output (default)
    DEBUG = 2  # Detailed output

    def self.from_string(str)
      const_get(str.upcase)
    rescue NameError
      INFO
    end
  end
end
