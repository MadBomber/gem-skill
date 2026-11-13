# frozen_string_literal: true

# gem/skill first — see gem_command.rb: activation must resolve json < 3
# before a bare `require "json"` can activate a newer version.
require "gem/skill"
require "async"
require "fileutils"
require "json"
require "optparse"
require "tty-spinner"

module Gem::Skill
  # Handles `bundle skill SUBCOMMAND` via Bundler's plugin API (plugins.rb).
  # Project-aware: reads Gemfile.lock and manages project skill symlinks
  # (directory set by GEMSKILL_PROJECT_DIR, default .claude/skills/).
  module BundlerCommand
    SUBCOMMANDS = %w[install refresh list].freeze

    def self.run(args)
      begin
        opts, rest = parse_options(args)
      rescue OptionParser::ParseError => e
        abort_with_usage(e.message)
      end
      subcmd = rest.shift

      if opts[:version]
        puts Gem::Skill::VERSION
        return
      end
      return puts(usage) if opts[:help] || [nil, "help"].include?(subcmd)

      Gem::Skill.configure_llm!
      case subcmd
      when "install" then install(opts)
      when "refresh" then refresh(opts)
      when "list"    then list
      else
        abort_with_usage("unknown subcommand #{subcmd.inspect}")
      end
    rescue Gem::Skill::Error => e
      warn "gem-skill: #{e.message}"
      exit 1
    end

    def self.install(opts = {})
      gems = Lockfile.gems
      if gems.empty?
        puts "No gems found in Gemfile.lock."
        return
      end

      force       = opts[:force]
      verify      = opts[:verify]
      model       = opts[:model] || Generator::DEFAULT_MODEL
      max_tokens  = opts[:max_tokens] || Generator::MAX_TOKENS
      temperature = opts[:temperature] || Generator::DEFAULT_TEMPERATURE
      errors      = []
      results     = []

      multi = TTY::Spinner::Multi.new(
        "[:spinner] Installing skills (#{model})",
        format: :dots,
        output: $stderr
      )

      Async do
        barrier = Async::Barrier.new
        gems.each do |gem_name, version|
          sp = multi.register("  [:spinner] :title")
          sp.update(title: "#{gem_name} #{version}")
          barrier.async do
            result = install_one(gem_name, version, sp, force:, model:, verify:, max_tokens:, temperature:)
            results << result
            errors << "#{gem_name} #{version}: #{result.error}" if result.error
          end
        end
        barrier.wait
      ensure
        barrier.stop
      end

      Linker.prune_dead_links
      report_errors(errors)
      report_verify(results, verify)
    end

    def self.refresh(opts = {})
      gems   = Lockfile.gems
      linked  = Linker.linked_gems.to_h { |e| [e[:gem_name], e[:version]] }
      force       = opts[:force]
      verify      = opts[:verify]
      model       = opts[:model] || Generator::DEFAULT_MODEL
      max_tokens  = opts[:max_tokens] || Generator::MAX_TOKENS
      temperature = opts[:temperature] || Generator::DEFAULT_TEMPERATURE
      errors      = []
      results     = []

      multi = TTY::Spinner::Multi.new(
        "[:spinner] Refreshing skills (#{model})",
        format: :dots,
        output: $stderr
      )

      Async do
        barrier = Async::Barrier.new
        gems.each do |gem_name, version|
          sp = multi.register("  [:spinner] :title")
          sp.update(title: "#{gem_name} #{version}")
          barrier.async do
            result = if !force && linked[gem_name] == version
              sp.auto_spin
              sp.success("up to date")
              Runner::Result.success
            else
              install_one(gem_name, version, sp, force:, model:, verify:, max_tokens:, temperature:)
            end
            results << result
            errors << "#{gem_name} #{version}: #{result.error}" if result.error
          end
        end
        barrier.wait
      ensure
        barrier.stop
      end

      Linker.prune_dead_links
      report_errors(errors)
      report_verify(results, verify)
    end

    def self.list
      entries = Linker.linked_gems
      if entries.empty?
        puts "No skills linked in this project."
        puts "Run: bundle skill install"
        return
      end

      ok     = entries.count { |e| e[:valid] }
      broken = entries.size - ok

      puts "Skills linked in #{Linker.project_dir}/  (#{ok} ok#{broken > 0 ? ", #{broken} broken" : ""}):"
      puts ""
      entries.each do |e|
        status = e[:valid] ? "ok    " : "BROKEN"
        puts "  [#{status}]  %-30s %s" % [e[:gem_name], e[:version]]
      end
    end

    # --- private ---

    def self.install_one(gem_name, version, spinner, force:, model:, verify: false,
                         max_tokens: Generator::MAX_TOKENS, temperature: Generator::DEFAULT_TEMPERATURE)
      spinner.auto_spin
      Runner.install_skill(gem_name, version, spinner, force:, model:, verify:, max_tokens:, temperature:)
    end
    private_class_method :install_one

    def self.report_errors(errors)
      return if errors.empty?
      warn ""
      warn "Errors (#{errors.size}):"
      errors.each { |e| warn "  #{e}" }
    end
    private_class_method :report_errors

    # When --verify applied fixes, report and exit non-zero so callers/CI can
    # detect that the README-derived skill disagreed with the source.
    def self.report_verify(results, verify)
      return unless verify

      fixed = results.count(&:verify_fixed)
      return if fixed.zero?

      warn ""
      warn "Verify corrected #{fixed} skill(s) against gem source."
      exit Gem::Skill::EXIT_VERIFY_FIXED
    end
    private_class_method :report_verify

    # Returns [opts, remaining_args]. Flags may come before or after the
    # subcommand, whatever POSIXLY_CORRECT says. Raises OptionParser::ParseError
    # on an unknown or abbreviated flag, or a missing or malformed value.
    # -h/--help is defined so OptionParser's built-in help never replaces
    # `usage`; on the command line Bundler intercepts it, and `bundle skill
    # help` is the way in.
    def self.parse_options(args)
      opts   = {}
      parser = OptionParser.new do |flags|
        flags.require_exact = true
        flags.on("-f", "--force")                                     { opts[:force] = true }
        flags.on("--verify")                                          { opts[:verify] = true }
        flags.on("-v", "--version")                                   { opts[:version] = true }
        flags.on("-h", "--help")                                      { opts[:help] = true }
        flags.on("-m", "--model MODEL")                               { opts[:model] = it }
        flags.on("--max-tokens TOKENS", OptionParser::DecimalInteger) { opts[:max_tokens] = it }
        flags.on("--temperature TEMP", Float)                         { opts[:temperature] = it }
      end

      [opts, parser.permute(args)]
    end
    private_class_method :parse_options

    def self.abort_with_usage(message)
      warn "gem-skill: #{message}"
      warn usage
      exit 1
    end
    private_class_method :abort_with_usage

    def self.usage
      <<~USAGE
        Usage: bundle skill SUBCOMMAND [OPTIONS]

        Subcommands:
          install   Generate and link skills for all gems in Gemfile.lock
          refresh   Re-sync the project skill directory after bundle update
          list      Show skills linked in this project

        Options:
          --force, -f            Regenerate even if already cached
          --verify               Verify generated skills against gem source and fix mismatches
          --model, -m MODEL      LLM model to use (default: #{Generator::DEFAULT_MODEL})
          --max-tokens TOKENS    Max output tokens (overrides GEMSKIL_MAX_TOKENS; default: #{Generator::MAX_TOKENS})
          --temperature TEMP     Sampling temperature; ignored by reasoning models (overrides GEMSKILL_TEMPERATURE; default: #{Generator::DEFAULT_TEMPERATURE})
          --version, -v          Print gem-skill version and exit

        Env:
          GEMSKILL_PROJECT_DIR   Project dir for symlinks (default: .claude/skills)
      USAGE
    end
    private_class_method :usage
  end
end
