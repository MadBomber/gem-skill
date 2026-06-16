# frozen_string_literal: true

require_relative "gem_skills/cli/gem_command"
Gem::CommandManager.instance.register_command :skill

# ---------------------------------------------------------------------------
# gem install GEM_NAME --with-skill
#
# Prepend an option onto the built-in install command so that passing
# --with-skill generates (and caches) a SKILL.md immediately after the gem
# is installed. The flag is stored in the installer's options hash and read
# by the post_install hook, which is the only RubyGems-supported way to act
# after a successful install without monkey-patching execute.
# ---------------------------------------------------------------------------
require "rubygems/commands/install_command"

module GemSkills
  module InstallSkillOption
    def initialize
      super
      add_option("--with-skill", "Generate a Claude Code SKILL.md after installation") do |_, opts|
        opts[:generate_skill] = true
      end
    end
  end
end

Gem::Commands::InstallCommand.prepend(GemSkills::InstallSkillOption)

Gem.post_install do |installer|
  next unless installer.options[:generate_skill]

  name    = installer.spec.name
  version = installer.spec.version.to_s

  begin
    GemSkills.configure_llm!
    Gem.ui.say "  gem_skills: generating skill for #{name} #{version}..."
    GemSkills::Generator.new(name, version).generate { |chunk| print chunk; $stdout.flush }
    Gem.ui.say "\n  gem_skills: cached at #{GemSkills::Cache.skill_path(name, version)}"
  rescue GemSkills::Error => e
    Gem.ui.alert_warning "gem_skills: #{e.message}"
  end
end
