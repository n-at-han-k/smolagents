# frozen_string_literal: true

require_relative "lib/smolagents/version"

Gem::Specification.new do |spec|
  spec.name = "smolagents"
  spec.version = Smolagents::VERSION
  spec.authors = ["HuggingFace"]
  spec.email = ["info@huggingface.co"]

  spec.summary = "A lightweight agent framework for building AI agents"
  spec.description = "Ruby port of the smolagents library for creating AI agents with tools and memory"
  spec.homepage = "https://github.com/huggingface/smolagents"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "chunky_png", "~> 1.4"
  spec.add_dependency "faraday", "~> 2.7"
  spec.add_dependency "tty-logger", "~> 0.6"
  spec.add_dependency "tty-table", "~> 0.12"
end
