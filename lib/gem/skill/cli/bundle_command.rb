# frozen_string_literal: true

require "async"
require "fileutils"
require "json"
require "tty-spinner"
require "gem/skill"

module Gem::Skill
  # Handles `bundle skill SUBCOMMAND` via Bundler's plugin API (plugins.rb).
  # Project-aware: reads Gemfile.lock and manages project skill symlinks
  # (directory set by GEMSKILL_PROJECT_DIR, default .claude/skills/).
  module BundlerCommand
    SUBCOMMANDS = %w[install refresh list].freeze

    def self.run(args)
      Gem::Skill.configure_llm!
      opts, rest = parse_options(args)
      subcmd = rest.shift

      if opts[:version]
        puts Gem::Skill::VERSION
        return
      end

      case subcmd
      when "install" then install(opts)
      when "refresh" then refresh(opts)
      when "list"    then list
      when nil, "help", "--help"
        puts usage
      else
        warn "gem-skill: unknown subcommand #{subcmd.inspect}"
        warn usage
        exit 1
      end
    end

    def self.install(opts = {})
      gems = Lockfile.gems
      if gems.empty?
        puts "No gems found in Gemfile.lock."
        return
      end

      force      = opts[:force]
      verify     = opts[:verify]
      model      = opts[:model] || Generator::DEFAULT_MODEL
      max_tokens = opts[:max_tokens] || Generator::MAX_TOKENS
      errors     = []
      results    = []

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
            result = install_one(gem_name, version, sp, force: force, model: model, verify: verify, max_tokens: max_tokens)
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
      force      = opts[:force]
      verify     = opts[:verify]
      model      = opts[:model] || Generator::DEFAULT_MODEL
      max_tokens = opts[:max_tokens] || Generator::MAX_TOKENS
      errors     = []
      results    = []

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
              install_one(gem_name, version, sp, force: force, model: model, verify: verify, max_tokens: max_tokens)
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

    def self.install_one(gem_name, version, spinner, force:, model:, verify: false, max_tokens: Generator::MAX_TOKENS)
      spinner.auto_spin
      Runner.install_skill(gem_name, version, spinner, force: force, model: model, verify: verify, max_tokens: max_tokens)
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

    def self.parse_options(args)
      opts      = {}
      remaining = []

      args.each do |arg|
        case arg
        when "--force"           then opts[:force] = true
        when "--verify"          then opts[:verify] = true
        when "--version", "-v"   then opts[:version] = true
        when /\A--model(?:=(.+))?\z/
          opts[:model] = $1 || args[args.index(arg) + 1]
        when /\A--max-tokens(?:=(.+))?\z/
          opts[:max_tokens] = ($1 || args[args.index(arg) + 1]).to_i
        else
          remaining << arg unless opts[:model].nil? && arg !~ /\A--/
          remaining << arg if arg !~ /\A--/
        end
      end

      [opts, remaining]
    end
    private_class_method :parse_options

    def self.usage
      <<~USAGE
        Usage: bundle skill SUBCOMMAND [OPTIONS]

        Subcommands:
          install   Generate and link skills for all gems in Gemfile.lock
          refresh   Re-sync the project skill directory after bundle update
          list      Show skills linked in this project

        Options:
          --force                Regenerate even if already cached
          --verify               Verify generated skills against gem source and fix mismatches
          --model MODEL          LLM model to use (default: #{Generator::DEFAULT_MODEL})
          --max-tokens TOKENS    Max output tokens (overrides GEMSKIL_MAX_TOKENS; default: #{Generator::MAX_TOKENS})
          --version, -v          Print gem-skill version and exit

        Env:
          GEMSKILL_PROJECT_DIR   Project dir for symlinks (default: .claude/skills)
      USAGE
    end
    private_class_method :usage
  end
end
