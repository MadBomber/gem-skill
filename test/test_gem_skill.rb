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
end
