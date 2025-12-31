#!/usr/bin/env ruby
# frozen_string_literal: true

# Agent Types Demo
#
# This example demonstrates the different agent types (AgentText, AgentImage, AgentAudio)
# which wrap tool outputs for consistent handling by the agent framework.

require_relative "../lib/smolagents"
require "tempfile"

include Smolagents

puts "=== AgentText Demo ==="
puts

# AgentText wraps string outputs and behaves like a String
text = AgentText.new("Hello, I am an AI assistant. How can I help you today?")

puts "Original text: #{text}"
puts "Uppercase: #{text.upcase}"
puts "Length: #{text.length}"
puts "Includes 'AI'?: #{text.include?('AI')}"
puts "Raw value: #{text.to_raw.inspect}"

# String concatenation
greeting = AgentText.new("Hello")
name = AgentText.new("World")
combined = greeting + ", " + name + "!"
puts "Combined: #{combined}"

puts
puts "=== AgentImage Demo ==="
puts

# Create a simple PNG file for demonstration
# (In production, this would be real image data from a tool)
def create_sample_png
  # Minimal valid PNG (1x1 red pixel)
  png_data = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  # PNG signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,  # IHDR chunk
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,  # IDAT chunk
    0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE,
    0xD4, 0xEF, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,  # IEND chunk
    0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
  ].pack("C*")

  Tempfile.new(["sample", ".png"]).tap do |f|
    f.binmode
    f.write(png_data)
    f.close
  end
end

# Create from file path
temp_file = create_sample_png
image_from_path = AgentImage.new(temp_file.path)
puts "Image from path: #{image_from_path.inspect}"
puts "Path: #{image_from_path.path}"
puts "Loaded?: #{image_from_path.loaded?}"

# Force load and check
raw_data = image_from_path.to_raw
puts "Data size: #{raw_data.bytesize} bytes"
puts "Loaded after to_raw?: #{image_from_path.loaded?}"

# Create from raw bytes
image_from_bytes = AgentImage.new(raw_data)
puts
puts "Image from bytes: #{image_from_bytes.inspect}"
puts "String path: #{image_from_bytes.to_string}"

# Save image
output_path = "/tmp/smolagents_demo_output.png"
image_from_bytes.save(output_path)
puts "Saved to: #{output_path}"

# Clean up temp file
temp_file.unlink

puts
puts "=== AgentAudio Demo ==="
puts

# Create AgentAudio from sample data
# Sample rate and audio samples
samplerate = 16000  # 16kHz
duration = 0.5      # 0.5 seconds

# Generate a simple sine wave (440 Hz - A4 note)
samples = (0...(samplerate * duration).to_i).map do |i|
  Math.sin(2 * Math::PI * 440 * i / samplerate)
end

audio = AgentAudio.new([samplerate, samples])
puts "Audio: #{audio.inspect}"
puts "Sample rate: #{audio.samplerate} Hz"
puts "Duration: #{audio.duration.round(3)} seconds"
puts "Sample count: #{audio.to_raw.length}"

# Save to WAV file
wav_path = audio.to_string
puts "WAV path: #{wav_path}"

# Load audio from file
audio_from_file = AgentAudio.new(wav_path)
puts "Loaded from file: #{audio_from_file.inspect}"

puts
puts "=== Type Handling in Tools ==="
puts

# Demonstrate how agent types help with tool input/output handling

# Simulated tool that returns an image
def generate_chart_tool(data:)
  # In production, this would generate an actual chart
  # For now, return a mock AgentImage
  AgentImage.new(create_sample_png.tap(&:close).path)
end

# Simulated tool that transcribes audio
def transcribe_audio_tool(audio:)
  # Accept AgentAudio and return AgentText
  raise ArgumentError, "Expected AgentAudio" unless audio.is_a?(AgentAudio)

  duration = audio.duration
  AgentText.new("Transcribed #{duration.round(2)} seconds of audio: 'Hello world'")
end

# Using handle_agent_input_types and handle_agent_output_types
original_text = AgentText.new("Test message")
original_audio = AgentAudio.new([16000, [0.0] * 1600])

# Convert agent types to raw values for processing
args, kwargs = Smolagents.handle_agent_input_types(original_text, audio: original_audio)
puts "Converted args: #{args.first.class}"        # String
puts "Converted kwargs audio: #{kwargs[:audio].class}"  # Array

# Convert output back to agent type
raw_output = "This is a generated response"
typed_output = Smolagents.handle_agent_output_types(raw_output, output_type: "text")
puts "Typed output: #{typed_output.class}"  # AgentText

puts
puts "=== Summary ==="
puts

puts "AgentType classes provide:"
puts "  - Type-safe wrappers for tool outputs"
puts "  - Automatic serialization/deserialization"
puts "  - Consistent interface for agents to handle different data types"
puts "  - Lazy loading for large data (images, audio)"
puts "  - Easy conversion between raw and typed representations"
