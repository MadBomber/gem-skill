# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

class TestGemSkill < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Gem::Skill::VERSION
  end

  def test_cache_root_defaults_to_home_dir
    assert_equal File.expand_path("~/.gem/skills"), cache_root_loaded_with("GEMSKILL_DIR" => nil)
  end

  def test_cache_root_honors_gemskill_dir
    dir = File.join(Dir.tmpdir, "gemskill-cache")
    assert_equal dir, cache_root_loaded_with("GEMSKILL_DIR" => dir)
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

  def test_parse_model_extracts_ollama_prefix
    assert_equal ["llama3.2", :ollama], Gem::Skill.parse_model("ollama/llama3.2")
  end

  def test_apply_env_sets_ollama_settings
    config = RubyLLM::Configuration.new
    Gem::Skill.apply_env(config, "OLLAMA_API_BASE" => "http://127.0.0.1:9/v1", "OLLAMA_API_KEY" => "token")

    assert_equal "http://127.0.0.1:9/v1", config.ollama_api_base
    assert_equal "token", config.ollama_api_key
  end

  def test_apply_env_leaves_unset_variables_alone
    config = RubyLLM::Configuration.new
    config.anthropic_api_key = "from-app"
    Gem::Skill.apply_env(config, {})

    assert_equal "from-app", config.anthropic_api_key
  end

  def test_configure_llm_sets_timeout_and_applies_env
    config  = RubyLLM::Configuration.new
    applied = nil
    RubyLLM.stub(:configure, ->(&block) { block.call(config) }) do
      Gem::Skill.stub(:apply_env, ->(c) { applied = c }) { Gem::Skill.configure_llm! }
    end

    assert_equal Gem::Skill::REQUEST_TIMEOUT, config.request_timeout
    assert_same config, applied
  end

  private

  # ROOT is fixed when the gem loads, so read it from a fresh Ruby with env.
  def cache_root_loaded_with(env)
    lib = File.expand_path("../lib", __dir__)
    out, err, status = Open3.capture3(env, RbConfig.ruby, "-I", lib, "-e",
                                      'require "gem/skill"; print Gem::Skill::Cache::ROOT')
    assert status.success?, err
    out
  end
end
