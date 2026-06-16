# frozen_string_literal: true

require "rubygems/command"
require "fileutils"
require "json"
require "gem_skills"

# Registered as `gem skill` via lib/rubygems_plugin.rb.
# Manages the global ~/.gem_skills cache.
class Gem::Commands::SkillCommand < Gem::Command
  def initialize
    super "skill", "Manage Claude Code AI skills for Ruby gems"

    add_option("-f", "--force",         "Regenerate even if already cached") { |_, o| o[:force] = true }
    add_option("-a", "--all",           "Purge all cached versions of a gem") { |_, o| o[:all] = true }
    add_option("-m", "--model MODEL",   "LLM model to use (default: #{GemSkills::Generator::DEFAULT_MODEL})") do |model, o|
      o[:model] = model
    end
  end

  def arguments
    "SUBCOMMAND  one of: install, list, purge"
  end

  def usage
    "#{program_name} install GEM_NAME [GEM_NAME ...]\n" \
    "       #{program_name} list\n" \
    "       #{program_name} purge GEM_NAME VERSION\n" \
    "       #{program_name} purge GEM_NAME --all"
  end

  def description
    <<~DESC
      install   Generate and cache a SKILL.md for a gem.
      list      Show all skills in the global cache (~/.gem_skills).
      purge     Remove a specific cached version.

      Use 'bundle skill install' (after: bundle plugin install gem_skills)
      to generate and link skills for an entire project from Gemfile.lock.
    DESC
  end

  def execute
    GemSkills.configure_llm!
    subcmd = options[:args].shift
    case subcmd
    when "install" then cmd_install
    when "list"    then cmd_list
    when "purge"   then cmd_purge
    when nil
      say usage
    else
      alert_error "Unknown subcommand: #{subcmd.inspect}"
      say usage
    end
  end

  private

  def cmd_install
    gem_names = options[:args].dup
    options[:args].clear

    if gem_names.empty?
      alert_error "gem_name required. Usage: gem skill install GEM_NAME [GEM_NAME ...]"
      return
    end

    force = options[:force]
    model = options[:model] || GemSkills::Generator::DEFAULT_MODEL

    gem_names.each { |name| install_one(name, force: force, model: model) }

    say "Tip: run 'bundle plugin install gem_skills' to enable 'bundle skill'."
  end

  def install_one(gem_name, force:, model:)
    version = resolve_installed_version(gem_name)

    if version.nil?
      say "gem '#{gem_name}' is not installed locally. Installing..."
      version = install_gem(gem_name)
    end

    if GemSkills::Cache.cached?(gem_name, version) && !force
      say "Already cached: #{GemSkills::Cache.skill_path(gem_name, version)}"
      say "Use --force to regenerate."
      return
    end

    say "Generating skill for #{gem_name} #{version} (#{model})..."
    say "-" * 60

    generator = GemSkills::Generator.new(gem_name, version, model: model)
    generator.generate(force: force) { |chunk| print chunk; $stdout.flush }

    say ""
    say "-" * 60
    say "Cached: #{GemSkills::Cache.skill_path(gem_name, version)}"
    say ""
  rescue GemSkills::Error => e
    alert_error "#{gem_name}: #{e.message}"
  end

  def cmd_list
    gems = GemSkills::Cache.all_gems
    if gems.empty?
      say "No skills cached yet."
      say "Run: gem skill install GEM_NAME"
      return
    end

    say "Cached skills in #{GemSkills::Cache.root}:"
    say ""
    gems.each do |name|
      versions = GemSkills::Cache.versions(name)
      say "  %-30s %s" % [name, versions.join(", ")]
    end
    say ""
    say "#{gems.size} gem(s), #{gems.sum { |n| GemSkills::Cache.versions(n).size }} version(s) total."
  end

  def cmd_purge
    gem_name = options[:args].shift
    unless gem_name
      alert_error "Usage: gem skill purge GEM_NAME VERSION\n       gem skill purge GEM_NAME --all"
      return
    end

    if options[:all]
      versions = GemSkills::Cache.versions(gem_name)
      if versions.empty?
        alert_error "No cached versions for '#{gem_name}'"
        return
      end
      versions.each { |v| GemSkills::Cache.purge(gem_name, v) }
      say "Purged #{versions.size} version(s) of #{gem_name}"
      return
    end

    version = options[:args].shift
    unless version
      alert_error "Usage: gem skill purge GEM_NAME VERSION\n       gem skill purge GEM_NAME --all"
      return
    end

    unless GemSkills::Cache.cached?(gem_name, version)
      alert_error "Not cached: #{gem_name} #{version}"
      return
    end

    GemSkills::Cache.purge(gem_name, version)
    say "Purged: #{gem_name} #{version}"
  end

  def resolve_installed_version(gem_name)
    Gem::Specification.find_by_name(gem_name)&.version&.to_s
  rescue Gem::MissingSpecError
    nil
  end

  def install_gem(gem_name, version = nil)
    req   = version ? Gem::Requirement.new("= #{version}") : Gem::Requirement.default
    specs = Gem.install(gem_name, req)
    specs.find { |s| s.name == gem_name }&.version&.to_s
  rescue Gem::InstallError, Gem::GemNotFoundException, StandardError => e
    raise GemSkills::Error, "Could not install '#{gem_name}': #{e.message}"
  end
end
