# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "gem/skill/cli/bundle_command"

class BundlerCommandTest < Minitest::Test
  FAKE_GEMS = { "my_gem" => "1.0.0", "other_gem" => "2.1.0" }.freeze

  def setup
    @tmpdir = Dir.mktmpdir
    stub_cache_root(@tmpdir)
    @output = StringIO.new
    @errors = StringIO.new
    $stdout = @output
    $stderr = @errors
  end

  def teardown
    $stdout = STDOUT
    $stderr = STDERR
    FileUtils.rm_rf(@tmpdir)
    restore_cache_root
  end

  # --- option parsing ---

  def test_parse_options_force_flag
    opts, remaining = call_parse_options(%w[install --force])
    assert opts[:force]
    assert_equal %w[install], remaining
  end

  def test_parse_options_model_flag
    opts, _rest = call_parse_options(%w[install --model claude-haiku-4-5])
    assert_equal "claude-haiku-4-5", opts[:model]
  end

  def test_parse_options_no_flags
    opts, rest = call_parse_options(%w[install])
    refute opts[:force]
    assert_nil opts[:model]
    assert_nil opts[:max_tokens]
    assert_equal %w[install], rest
  end

  def test_parse_options_max_tokens_flag
    opts, _rest = call_parse_options(%w[install --max-tokens 65536])
    assert_equal 65_536, opts[:max_tokens]
  end

  def test_parse_options_consumes_value_flags_before_subcommand
    opts, rest = call_parse_options(%w[--model gpt-x --max-tokens 100 install])
    assert_equal "gpt-x", opts[:model]
    assert_equal 100, opts[:max_tokens]
    assert_equal %w[install], rest
  end

  def test_parse_options_consumes_value_flag_after_subcommand
    opts, rest = call_parse_options(%w[install --model gpt-x])
    assert_equal "gpt-x", opts[:model]
    assert_equal %w[install], rest
  end

  def test_parse_options_accepts_equals_form
    opts, rest = call_parse_options(%w[install --model=gpt-x --max-tokens=100 --temperature=0.7])
    assert_equal({ model: "gpt-x", max_tokens: 100, temperature: 0.7 }, opts)
    assert_equal %w[install], rest
  end

  def test_parse_options_temperature_flag
    opts, rest = call_parse_options(%w[install --temperature 0.5])
    assert_in_delta 0.5, opts[:temperature]
    assert_equal %w[install], rest
  end

  def test_parse_options_rejects_unknown_flag
    assert_raises(OptionParser::InvalidOption) { call_parse_options(%w[install --bogus]) }
  end

  def test_parse_options_rejects_non_numeric_max_tokens
    assert_raises(OptionParser::InvalidArgument) { call_parse_options(%w[install --max-tokens lots]) }
  end

  def test_parse_options_rejects_abbreviated_flag
    assert_raises(OptionParser::InvalidOption) { call_parse_options(%w[install --mod gpt-x]) }
  end

  def test_parse_options_rejects_non_decimal_max_tokens
    assert_raises(OptionParser::InvalidArgument) { call_parse_options(%w[install --max-tokens 0x10]) }
  end

  def test_parse_options_short_flags_match_gem_skill
    opts, rest = call_parse_options(%w[install -f -m gpt-x])
    assert_equal({ force: true, model: "gpt-x" }, opts)
    assert_equal %w[install], rest
  end

  def test_parse_options_permutes_even_when_posixly_correct
    saved = ENV.fetch("POSIXLY_CORRECT", nil)
    ENV["POSIXLY_CORRECT"] = "1"
    opts, rest = call_parse_options(%w[install --model gpt-x])
    assert_equal "gpt-x", opts[:model]
    assert_equal %w[install], rest
  ensure
    ENV["POSIXLY_CORRECT"] = saved
  end

  def test_run_bad_option_exits_before_configuring_llm
    Gem::Skill.stub(:configure_llm!, -> { flunk "configured LLM" }) do
      assert_raises(SystemExit) { Gem::Skill::BundlerCommand.run(%w[install --bogus]) }
    end
  end

  def test_run_reports_bad_option_and_exits
    Gem::Skill.stub(:configure_llm!, nil) do
      error = assert_raises(SystemExit) { Gem::Skill::BundlerCommand.run(%w[install --model]) }
      assert_equal 1, error.status
    end
    assert_match "missing argument: --model", @errors.string
  end

  def test_run_help_flag_prints_usage_instead_of_running_subcommand
    Gem::Skill.stub(:configure_llm!, -> { flunk "configured LLM" }) do
      Gem::Skill::BundlerCommand.stub(:install, ->(*) { flunk "install ran" }) do
        Gem::Skill::BundlerCommand.run(%w[install --help])
      end
    end
    assert_match "Usage: bundle skill", @output.string
  end

  def test_run_with_model_before_subcommand_runs_subcommand
    stub_linker(linked: {}) do
      Gem::Skill.stub(:configure_llm!, nil) do
        Gem::Skill::BundlerCommand.run(%w[--model gpt-x list])
      end
    end
    assert_match "No skills linked", @output.string
  end

  # --- install ---

  def test_install_skips_generation_when_already_cached
    pre_cache_gems
    generated = []
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        stub_generator(generated) { Gem::Skill::BundlerCommand.install }
      end
    end
    assert_empty generated
  end

  def test_install_generates_uncached_gems
    generated = []
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        stub_generator(generated) { Gem::Skill::BundlerCommand.install }
      end
    end
    assert_equal FAKE_GEMS.keys.sort, generated.sort
  end

  def test_install_generates_multiple_gems_concurrently
    generated = []
    gems = { "gem_a" => "1.0.0", "gem_b" => "2.0.0", "gem_c" => "3.0.0" }
    stub_lockfile(gems) do
      stub_linker do
        stub_generator(generated) { Gem::Skill::BundlerCommand.install }
      end
    end
    assert_equal gems.keys.sort, generated.sort
  end

  def test_install_force_regenerates_cached_gems
    pre_cache_gems
    generated = []
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        stub_generator(generated) { Gem::Skill::BundlerCommand.install(force: true) }
      end
    end
    assert_equal FAKE_GEMS.keys.sort, generated.sort
  end

  def test_install_continues_after_one_gem_fails
    generated = []
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        Gem::Skill::Generator.stub(:new, ->(name, *) {
          name == "my_gem" ? failing_gen : fake_gen(generated, name)
        }) { Gem::Skill::BundlerCommand.install }
      end
    end
    assert_includes generated, "other_gem"
    assert_match "my_gem", @errors.string
  end

  def test_install_reports_errors_to_stderr
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        Gem::Skill::Generator.stub(:new, ->(*) { failing_gen }) do
          Gem::Skill::BundlerCommand.install
        end
      end
    end
    assert_match "Errors", @errors.string
  end

  def test_install_passes_custom_model_to_generator
    captured = {}
    stub_lockfile({ "my_gem" => "1.0.0" }) do
      stub_linker do
        capture_generator_kwargs(captured) { Gem::Skill::BundlerCommand.install(model: "claude-haiku-4-5") }
      end
    end
    assert_equal "claude-haiku-4-5", captured[:model]
  end

  def test_install_passes_max_tokens_to_generator
    captured = {}
    stub_lockfile({ "my_gem" => "1.0.0" }) do
      stub_linker do
        capture_generator_kwargs(captured) { Gem::Skill::BundlerCommand.install(max_tokens: 65_536) }
      end
    end
    assert_equal 65_536, captured[:max_tokens]
  end

  def test_install_passes_temperature_to_generator
    captured = {}
    stub_lockfile({ "my_gem" => "1.0.0" }) do
      stub_linker do
        capture_generator_kwargs(captured) { Gem::Skill::BundlerCommand.install(temperature: 0.7) }
      end
    end
    assert_in_delta 0.7, captured[:temperature]
  end

  def test_refresh_passes_temperature_to_generator
    captured = {}
    stub_lockfile({ "my_gem" => "1.0.0" }) do
      stub_linker(linked: {}) do
        capture_generator_kwargs(captured) { Gem::Skill::BundlerCommand.refresh(temperature: 0.7) }
      end
    end
    assert_in_delta 0.7, captured[:temperature]
  end

  def test_refresh_passes_max_tokens_to_generator
    captured = {}
    stub_lockfile({ "my_gem" => "1.0.0" }) do
      stub_linker(linked: {}) do
        capture_generator_kwargs(captured) { Gem::Skill::BundlerCommand.refresh(max_tokens: 65_536) }
      end
    end
    assert_equal 65_536, captured[:max_tokens]
  end

  # --- refresh ---

  def test_refresh_skips_gems_already_at_correct_version
    pre_cache_gems
    generated = []
    stub_lockfile(FAKE_GEMS) do
      stub_linker(linked: FAKE_GEMS) do
        stub_generator(generated) { Gem::Skill::BundlerCommand.refresh }
      end
    end
    assert_empty generated
  end

  def test_refresh_updates_gems_with_changed_version
    stub_cache("my_gem", "1.0.0", "old skill")
    generated = []
    stub_lockfile({ "my_gem" => "1.1.0" }) do
      stub_linker(linked: { "my_gem" => "1.0.0" }) do
        stub_generator(generated) { Gem::Skill::BundlerCommand.refresh }
      end
    end
    assert_includes generated, "my_gem"
  end

  def test_refresh_generates_new_gems_not_yet_linked
    generated = []
    stub_lockfile({ "new_gem" => "1.0.0" }) do
      stub_linker(linked: {}) do
        stub_generator(generated) { Gem::Skill::BundlerCommand.refresh }
      end
    end
    assert_includes generated, "new_gem"
  end

  # --- list ---

  def test_list_shows_linked_gems
    stub_linker(linked: FAKE_GEMS) do
      Gem::Skill::BundlerCommand.list
    end
    assert_match "my_gem", @output.string
    assert_match "other_gem", @output.string
  end

  def test_list_shows_empty_message_when_none_linked
    stub_linker(linked: {}) do
      Gem::Skill::BundlerCommand.list
    end
    assert_match "No skills linked", @output.string
  end

  private

  def call_parse_options(args)
    Gem::Skill::BundlerCommand.send(:parse_options, args)
  end

  def pre_cache_gems
    FAKE_GEMS.each { |name, ver| stub_cache(name, ver, "# #{name} skill") }
  end

  def stub_cache(name, ver, content)
    dir = File.join(@tmpdir, name, ver)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"), content)
  end

  def stub_lockfile(gems)
    Gem::Skill::Lockfile.stub(:gems, gems) { yield }
  end

  def stub_linker(linked: {})
    entries = linked.map { |name, ver| { gem_name: name, version: ver, valid: true } }
    Gem::Skill::Linker.stub(:link,             ->(*) {}) do
      Gem::Skill::Linker.stub(:prune_dead_links, ->(*) {}) do
        Gem::Skill::Linker.stub(:linked_gems,    entries) do
          yield
        end
      end
    end
  end

  def capture_generator_kwargs(captured, &)
    gen_obj = fake_gen([], "my_gem")
    capture = lambda do |*, **kwargs|
      captured.merge!(kwargs)
      gen_obj
    end
    Gem::Skill::Generator.stub(:new, capture, &)
  end

  def stub_generator(generated)
    Gem::Skill::Generator.stub(:new, ->(name, *) { fake_gen(generated, name) }) { yield }
  end

  def fake_gen(log, gem_name)
    obj = Object.new
    obj.define_singleton_method(:generate) { |**| log << gem_name; "# #{gem_name} skill" }
    obj
  end

  def failing_gen
    obj = Object.new
    obj.define_singleton_method(:generate) { |**| raise Gem::Skill::Error, "no docs found" }
    obj
  end

end
