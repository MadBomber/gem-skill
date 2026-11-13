# frozen_string_literal: true

require "test_helper"

class LockfileTest < Minitest::Test
  SAMPLE_LOCKFILE = <<~LOCKFILE
    GEM
      remote: https://rubygems.org/
      specs:
        debug_me (1.3.4)
        faraday (2.9.0)
          faraday-net_http (>= 2.0, < 3.2)
        faraday-net_http (3.1.0)
          net-http
        ruby_llm (1.2.0)
          faraday (~> 2.0)
        thor (1.3.2)

    PLATFORMS
      arm64-darwin-24

    DEPENDENCIES
      debug_me
      ruby_llm (~> 1.0)
      thor (~> 1.0)
  LOCKFILE

  def test_parse_extracts_direct_dependencies
    gems = Gem::Skill::Lockfile.parse(SAMPLE_LOCKFILE)
    assert_equal "1.3.4", gems["debug_me"]
    assert_equal "1.2.0", gems["ruby_llm"]
    assert_equal "1.3.2", gems["thor"]
  end

  def test_parse_excludes_transitive_dependencies
    gems = Gem::Skill::Lockfile.parse(SAMPLE_LOCKFILE)
    refute gems.key?("faraday")
    refute gems.key?("faraday-net_http")
  end

  def test_gems_raises_when_lockfile_missing
    assert_raises(Gem::Skill::Error) do
      Gem::Skill::Lockfile.gems("/nonexistent/Gemfile.lock")
    end
  end

  def test_parse_with_real_lockfile
    gems = Gem::Skill::Lockfile.gems(File.expand_path("../../../Gemfile.lock", __dir__))
    # Dev deps (irb, minitest, rake) are direct in DEPENDENCIES; gem-skill! is the path gem
    assert gems.key?("rake")
    assert gems.key?("minitest")
    refute gems.empty?
  end

  GIT_LOCKFILE = <<~LOCKFILE
    GIT
      remote: https://github.com/example/foo.git
      revision: 0123456789abcdef0123456789abcdef01234567
      specs:
        foo (1.2.3)

    PATH
      remote: .
      specs:
        my_project (0.1.0)

    GEM
      remote: https://rubygems.org/
      specs:
        rake (13.2.1)

    PLATFORMS
      arm64-darwin-24

    DEPENDENCIES
      foo!
      my_project!
      rake
  LOCKFILE

  def test_parse_includes_git_sourced_gems
    gems = Gem::Skill::Lockfile.parse(GIT_LOCKFILE)
    assert_equal({ "foo" => "1.2.3", "rake" => "13.2.1" }, gems)
  end

  MALFORMED_LOCKFILE = <<~LOCKFILE
    GEM
      remote: https://rubygems.org/
      specs:
        good_gem (1.0.0)
        bad_name (not a version)
        thor (1.3.2)

    PLATFORMS
      arm64-darwin-24

    DEPENDENCIES
      good_gem
      bad_name
      thor (~> 1.0)
  LOCKFILE

  def test_parse_drops_an_entry_with_a_malformed_version
    gems = Gem::Skill::Lockfile.parse(MALFORMED_LOCKFILE)
    assert_equal "1.0.0", gems["good_gem"]
    refute gems.key?("bad_name")
  end
end
