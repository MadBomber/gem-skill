# frozen_string_literal: true

require "fileutils"

module Gem::Skill
  # Manages per-project skill symlinks pointing into the ~/.gem/skills cache.
  # Each symlink is a directory link: <gem_name> -> ~/.gem/skills/<gem>/<version>/
  # The assistant discovers skills by reading SKILL.md inside each linked directory.
  #
  # The project-relative directory is configurable via GEMSKILL_PROJECT_DIR
  # (default ".claude/skills" for Claude Code). Codex users might set it to
  # ".agents" or ".codex"; see the configuration docs.
  module Linker
    DEFAULT_PROJECT_DIR = ".claude/skills"

    # Project-relative directory where skill symlinks are written. Read from the
    # environment each call so a changed GEMSKILL_PROJECT_DIR takes effect without
    # reloading.
    def self.project_dir
      value = ENV.fetch("GEMSKILL_PROJECT_DIR", DEFAULT_PROJECT_DIR).to_s.strip
      value.empty? ? DEFAULT_PROJECT_DIR : value
    end

    def self.skills_dir(project_root = Dir.pwd)
      File.join(project_root, project_dir)
    end

    def self.link(gem_name, version, project_root = Dir.pwd)
      target_dir = File.dirname(Cache.skill_path(gem_name, version))
      raise Error, "No cached skill for #{gem_name} #{version}. Run: gem skill install #{gem_name}" \
        unless File.exist?(Cache.skill_path(gem_name, version))

      dir = skills_dir(project_root)
      FileUtils.mkdir_p(dir)

      link_path = File.join(dir, gem_name)
      File.unlink(link_path) if File.symlink?(link_path)
      File.symlink(target_dir, link_path)
    end

    def self.unlink(gem_name, project_root = Dir.pwd)
      link_path = File.join(skills_dir(project_root), gem_name)
      File.unlink(link_path) if File.symlink?(link_path)
    end

    def self.linked_gems(project_root = Dir.pwd)
      dir = skills_dir(project_root)
      return [] unless Dir.exist?(dir)

      Dir.glob(File.join(dir, "*")).filter_map do |path|
        next unless File.symlink?(path)

        gem_name   = File.basename(path)
        target_dir = File.readlink(path)
        version    = target_dir.match(%r{/([^/]+)$})&.captures&.first
        skill_file = File.join(target_dir, "SKILL.md")
        { gem_name: gem_name, version: version, target: target_dir, valid: File.exist?(skill_file) }
      end
    end

    def self.prune_dead_links(project_root = Dir.pwd)
      linked_gems(project_root)
        .reject { |entry| entry[:valid] }
        .each   { |entry| unlink(entry[:gem_name], project_root) }
    end
  end
end
