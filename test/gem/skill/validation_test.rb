# frozen_string_literal: true

require "test_helper"

class ValidationTest < Minitest::Test
  def test_accepts_plain_gem_names
    assert Gem::Skill::Validation.valid_gem_name?("my_gem")
    assert Gem::Skill::Validation.valid_gem_name?("faraday-net_http")
    assert Gem::Skill::Validation.valid_gem_name?("ruby_llm")
  end

  def test_rejects_names_that_are_not_plain_gem_names
    refute Gem::Skill::Validation.valid_gem_name?("foo/bar")
    refute Gem::Skill::Validation.valid_gem_name?(".")
    refute Gem::Skill::Validation.valid_gem_name?("..")
    refute Gem::Skill::Validation.valid_gem_name?("")
    refute Gem::Skill::Validation.valid_gem_name?("-leading-dash")
  end

  def test_accepts_well_formed_versions
    assert Gem::Skill::Validation.valid_version?("1.2.3")
    assert Gem::Skill::Validation.valid_version?("0.1.0.beta3")
  end

  def test_rejects_non_version_strings
    refute Gem::Skill::Validation.valid_version?("not a version")
    refute Gem::Skill::Validation.valid_version?("1.0/../etc")
    refute Gem::Skill::Validation.valid_version?("")
    refute Gem::Skill::Validation.valid_version?(nil)
  end

  def test_validate_gem_name_raises_on_invalid_name
    assert_raises(Gem::Skill::Error) { Gem::Skill::Validation.validate_gem_name!("foo/bar") }
  end

  def test_validate_version_raises_on_invalid_version
    assert_raises(Gem::Skill::Error) { Gem::Skill::Validation.validate_version!("not a version") }
  end
end
