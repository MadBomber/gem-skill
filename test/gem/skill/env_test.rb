# frozen_string_literal: true

require "test_helper"
require "open3"

class EnvTest < Minitest::Test
  # --- integer ---

  def test_integer_returns_default_when_unset
    assert_equal 900, Gem::Skill::Env.integer("X", 900, {})
  end

  def test_integer_parses_decimal_value
    assert_equal 1800, Gem::Skill::Env.integer("X", 900, { "X" => "1800" })
  end

  def test_integer_falls_back_to_default_on_garbage
    assert_equal 900, quietly { Gem::Skill::Env.integer("X", 900, { "X" => "abc" }) }
  end

  def test_integer_rejects_non_decimal_forms
    assert_equal 900, quietly { Gem::Skill::Env.integer("X", 900, { "X" => "0x10" }) }
    assert_equal 900, quietly { Gem::Skill::Env.integer("X", 900, { "X" => "1.5" }) }
  end

  def test_integer_warns_naming_the_variable_on_garbage
    with_warnings do
      assert_output(nil, /GEMSKILL_REQUEST_TIMEOUT="abc".*900/) do
        Gem::Skill::Env.integer("GEMSKILL_REQUEST_TIMEOUT", 900, { "GEMSKILL_REQUEST_TIMEOUT" => "abc" })
      end
    end
  end

  def test_integer_does_not_warn_on_valid_value
    with_warnings do
      assert_output(nil, "") { Gem::Skill::Env.integer("X", 900, { "X" => "60" }) }
    end
  end

  # --- float ---

  def test_float_returns_default_when_unset
    assert_in_delta 0.2, Gem::Skill::Env.float("X", 0.2, {})
  end

  def test_float_parses_value
    assert_in_delta 0.7, Gem::Skill::Env.float("X", 0.2, { "X" => "0.7" })
  end

  def test_float_falls_back_to_default_on_garbage
    assert_in_delta 0.2, quietly { Gem::Skill::Env.float("X", 0.2, { "X" => "hot" }) }
  end

  def test_float_warns_naming_the_variable_on_garbage
    with_warnings do
      assert_output(nil, /GEMSKILL_TEMPERATURE="hot".*0\.2/) do
        Gem::Skill::Env.float("GEMSKILL_TEMPERATURE", 0.2, { "GEMSKILL_TEMPERATURE" => "hot" })
      end
    end
  end

  # --- the constants, read once at load time (#35) ---

  def test_unparseable_env_vars_keep_the_defaults
    env = {
      "GEMSKILL_REQUEST_TIMEOUT" => "abc",
      "GEMSKIL_MAX_TOKENS"       => "lots",
      "GEMSKILL_TEMPERATURE"     => "hot"
    }
    script = 'require "gem/skill"; ' \
             'print [Gem::Skill::REQUEST_TIMEOUT, Gem::Skill::Generator::MAX_TOKENS, ' \
             'Gem::Skill::Generator::DEFAULT_TEMPERATURE].inspect'
    lib = File.expand_path("../../../lib", __dir__)
    out, err, status = Open3.capture3(env, RbConfig.ruby, "-I", lib, "-e", script)

    assert status.success?, err
    assert_equal "[900, 32767, 0.2]", out
  end

  private

  # Kernel#warn is a no-op when $VERBOSE is nil (ruby -W0), so force it on.
  def with_warnings
    original = $VERBOSE
    $VERBOSE = false
    yield
  ensure
    $VERBOSE = original
  end

  def quietly(&block)
    result = nil
    with_warnings { capture_io { result = block.call } }
    result
  end
end
