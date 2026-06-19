# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RunnerTest < Minitest::Test
  def setup
    @tmpdir   = Dir.mktmpdir
    @gem_name = "tty-spinner"
    @version  = "0.9.3"
    stub_cache_root(@tmpdir)
    Gem::Skill::Cache.store(@gem_name, @version, "old skill", { model: "m" })
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    restore_cache_root
  end

  def test_without_verify_skips_verifier_and_reports_success
    stub_linker do
      # Verifier must not be constructed when verify is off
      Gem::Skill::Verifier.stub(:new, ->(*) { raise "should not verify" }) do
        result = install(verify: false)
        assert result.ok?
        refute result.verify_fixed
        assert_equal "old skill", Gem::Skill::Cache.read(@gem_name, @version)
      end
    end
  end

  CHANGE = {
    "category"        => "default_value",
    "symbol"          => "TTY::Spinner#stop",
    "skill_section"   => "Core API",
    "source_location" => "lib/tty/spinner.rb:387",
    "was"             => "stop(message = nil)",
    "now"             => "stop(message = '')",
    "detail"          => "Default argument is an empty string, not nil.",
    "source_evidence" => "def stop(stop_message = '')"
  }.freeze

  MANIFEST = { files: ["lib/tty/spinner.rb", "lib/tty/spinner/multi.rb"], chars: 26_452, truncated: false }.freeze

  def test_verify_applies_fixes_rewrites_cache_and_records_provenance
    fixed = verifier_result(content: "new skill", changes: [CHANGE], changed: true,
                            verifiable: true, source: MANIFEST, model: "verify-model")
    stub_linker do
      stub_verifier(fixed) do
        result = install(verify: true)
        assert result.verify_fixed
        assert_equal 1, result.change_count
        assert_equal "new skill", Gem::Skill::Cache.read(@gem_name, @version)

        meta = Gem::Skill::Cache.read_metadata(@gem_name, @version)
        assert_equal "m", meta["model"], "top-level generation metadata is preserved"

        v = meta["verification"]
        assert_equal true,  v["verified"]
        assert_equal true,  v["used_source_code"]
        assert_equal true,  v["fixed"]
        assert_equal 1,     v["change_count"]
        assert_equal "verify-model", v["model"]
        assert v["verified_at"]

        # source provenance: which files were actually examined
        assert_equal 2, v.dig("source", "file_count")
        assert_equal MANIFEST[:files], v.dig("source", "files")
        assert_equal false, v.dig("source", "truncated")

        # issue-ready structured change
        change = v["changes"].first
        assert_equal CHANGE, change
        assert_equal "TTY::Spinner#stop", change["symbol"]
        assert_equal "lib/tty/spinner.rb:387", change["source_location"]
      end
    end
  end

  def test_verify_clean_marks_verified_with_no_changes
    clean = verifier_result(content: "old skill", changes: [], changed: false,
                            verifiable: true, source: MANIFEST, model: "m")
    stub_linker do
      stub_verifier(clean) do
        result = install(verify: true)
        refute result.verify_fixed
        assert_equal "old skill", Gem::Skill::Cache.read(@gem_name, @version)

        v = Gem::Skill::Cache.read_metadata(@gem_name, @version)["verification"]
        assert_equal true,  v["verified"]
        assert_equal true,  v["used_source_code"]
        assert_equal false, v["fixed"]
        assert_equal 0,     v["change_count"]
        assert_empty v["changes"]
      end
    end
  end

  def test_verify_without_source_records_skip_and_no_source_use
    no_source = verifier_result(content: "old skill", changes: [], changed: false,
                                verifiable: false, source: nil, model: "m")
    stub_linker do
      stub_verifier(no_source) do
        result = install(verify: true)
        refute result.verify_fixed

        v = Gem::Skill::Cache.read_metadata(@gem_name, @version)["verification"]
        assert_equal false, v["verified"]
        assert_equal false, v["used_source_code"]
        assert_equal "no installed source available", v["skipped_reason"]
      end
    end
  end

  def test_returns_failure_when_generation_raises
    # Force the uncached/generate path and make generation blow up
    Gem::Skill::Cache.purge(@gem_name, @version)
    failing = Object.new
    failing.define_singleton_method(:generate) { |*| raise Gem::Skill::Error, "boom" }
    stub_linker do
      Gem::Skill::Generator.stub(:new, ->(*, **) { failing }) do
        result = install(verify: false)
        refute result.ok?
        assert_match "boom", result.error
      end
    end
  end

  private

  def install(verify:)
    Gem::Skill::Runner.install_skill(@gem_name, @version, fake_spinner, force: false, model: "m", verify: verify)
  end

  def verifier_result(**attrs)
    Gem::Skill::Verifier::Result.new(**attrs)
  end

  def stub_verifier(result)
    obj = Object.new
    obj.define_singleton_method(:verify) { |_| result }
    Gem::Skill::Verifier.stub(:new, ->(*, **) { obj }) { yield }
  end

  def stub_linker
    Gem::Skill::Linker.stub(:link, ->(*) {}) { yield }
  end

  def fake_spinner
    spinner = Object.new
    spinner.define_singleton_method(:success) { |*| }
    spinner.define_singleton_method(:error)   { |*| }
    spinner.define_singleton_method(:update)  { |*| }
    spinner.define_singleton_method(:auto_spin) {}
    spinner
  end
end
