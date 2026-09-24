# frozen_string_literal: true

require_relative "skill/version"
require_relative "skill/cache"
require_relative "skill/fetcher"
require_relative "skill/frontmatter"
require_relative "skill/generator"
require_relative "skill/verifier"
require_relative "skill/linker"
require_relative "skill/lockfile"
require_relative "skill/runner"

module Gem::Skill
  class Error < StandardError; end

  # Exit status used when --verify found and corrected mistakes in a generated
  # skill (grep-style: 0 = clean, 1 = error, 2 = verify applied fixes).
  EXIT_VERIFY_FIXED = 2

  # The bundled "router" skill that teaches assistants how to find cached gem
  # skills in ~/.gem/skills. `gem skill setup` copies it into the assistants'
  # default skill roots. Lives at the repo/gem root, beside README/CHANGELOG.
  ROUTER_SKILL_NAME = "ruby-gem-skills"
  ROUTER_SKILL_DIR  = File.expand_path("../../#{ROUTER_SKILL_NAME}", __dir__)

  ENV_KEY_MAP = {
    anthropic_api_key:  "ANTHROPIC_API_KEY",
    openai_api_key:     "OPENAI_API_KEY",
    gemini_api_key:     "GEMINI_API_KEY",
    mistral_api_key:    "MISTRAL_API_KEY",
    deepseek_api_key:   "DEEPSEEK_API_KEY",
    openrouter_api_key: "OPENROUTER_API_KEY",
    xai_api_key:        "XAI_API_KEY",
    lms_api_base:       "LMS_API_BASE",
    lms_api_key:        "LMS_API_KEY",
    apfel_api_base:     "APFEL_API_BASE",
    apfel_api_key:      "APFEL_API_KEY"
  }.freeze

  # Split a "provider/model" string into [model_id, provider_symbol] when the
  # prefix names a registered RubyLLM provider, e.g.
  #   "lms/qwen/qwen3.8-27b" -> ["qwen/qwen3.8-27b", :lms]
  # Otherwise the string is a bare model id: ["gpt-5.5", nil]. A bare id is
  # resolved by RubyLLM's own provider preference, so ids that contain a "/"
  # but don't start with a provider slug (e.g. "qwen/...") pass through intact.
  def self.parse_model(model_string)
    prefix, rest = model_string.to_s.split("/", 2)
    return [model_string, nil] unless rest && RubyLLM::Provider.providers.key?(prefix.to_sym)

    [rest, prefix.to_sym]
  end

  # HTTP read timeout in seconds (GEMSKILL_REQUEST_TIMEOUT to override).
  # RubyLLM's default of 300 is tuned for hosted APIs; a local model (lms/apfel)
  # can legitimately take longer than that to finish one skill generation.
  REQUEST_TIMEOUT = ENV.fetch("GEMSKILL_REQUEST_TIMEOUT", 900).to_i

  # Configure RubyLLM from environment variables. Called automatically by the
  # CLI commands so users don't need a separate initializer for standalone use.
  # No-op if RubyLLM is already configured (e.g. in a Rails app).
  def self.configure_llm!
    RubyLLM.configure do |config|
      config.request_timeout = REQUEST_TIMEOUT
      ENV_KEY_MAP.each do |attr, env_var|
        value = ENV[env_var]
        config.public_send(:"#{attr}=", value) if value
      end
    end
  end
end
