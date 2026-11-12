# frozen_string_literal: true

require "test_helper"

class TestGemSkill < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Gem::Skill::VERSION
  end

  def test_cache_root_is_in_home_dir
    assert_match(%r{\.gem/skills}, Gem::Skill::Cache::ROOT)
  end

  def test_provider_plugins_are_registered
    assert_includes RubyLLM::Provider.providers.keys, :lms
    assert_includes RubyLLM::Provider.providers.keys, :apfel
  end

  def test_parse_model_extracts_registered_provider_prefix
    assert_equal ["qwen/qwen3.8-27b", :lms], Gem::Skill.parse_model("lms/qwen/qwen3.8-27b")
  end

  def test_parse_model_passes_through_bare_model_ids
    assert_equal ["gpt-5.5", nil], Gem::Skill.parse_model("gpt-5.5")
  end

  def test_parse_model_ignores_non_provider_prefixes
    assert_equal ["qwen/qwen3.8-27b", nil], Gem::Skill.parse_model("qwen/qwen3.8-27b")
  end

  def test_configure_llm_applies_ollama_api_base
    url      = "http://127.0.0.1:9/v1"
    original = ENV["OLLAMA_API_BASE"]
    saved    = RubyLLM.config.ollama_api_base
    ENV["OLLAMA_API_BASE"] = url
    Gem::Skill.configure_llm!

    assert_equal url, RubyLLM.config.ollama_api_base
  ensure
    original.nil? ? ENV.delete("OLLAMA_API_BASE") : ENV["OLLAMA_API_BASE"] = original
    RubyLLM.config.ollama_api_base = saved
  end
end
