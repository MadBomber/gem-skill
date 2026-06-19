# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Gem::Skill
  # Manages the global ~/.gem/skills cache.
  # Structure: ~/.gem/skills/<gem_name>/<version>/SKILL.md
  module Cache
    ROOT = File.expand_path(ENV.fetch("GEMSKILL_DIR", "~/.gem/skills")).freeze

    def self.root = ROOT

    def self.skill_path(gem_name, version)
      File.join(ROOT, gem_name, version, "SKILL.md")
    end

    def self.metadata_path(gem_name, version)
      File.join(ROOT, gem_name, version, "metadata.json")
    end

    def self.cached?(gem_name, version)
      File.exist?(skill_path(gem_name, version))
    end

    def self.store(gem_name, version, skill_content, metadata = {})
      dir = File.join(ROOT, gem_name, version)
      FileUtils.mkdir_p(dir)
      File.write(skill_path(gem_name, version), skill_content)
      File.write(metadata_path(gem_name, version), JSON.generate(metadata.merge(
        gem_name: gem_name,
        version: version,
        generated_at: Time.now.iso8601
      )))
    end

    def self.read(gem_name, version)
      path = skill_path(gem_name, version)
      raise Error, "No cached skill for #{gem_name} #{version}" unless File.exist?(path)

      File.read(path)
    end

    # Read metadata.json back as a Hash with string keys. Returns {} if absent
    # or unparseable.
    def self.read_metadata(gem_name, version)
      path = metadata_path(gem_name, version)
      return {} unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    # Overwrite just the SKILL.md content, leaving metadata untouched.
    def self.write_skill(gem_name, version, skill_content)
      File.write(skill_path(gem_name, version), skill_content)
    end

    # Merge additional keys into the existing metadata.json, preserving
    # generated_at, model, sources, etc. Keys are normalized to strings so a
    # symbol key never collides with its string twin.
    def self.merge_metadata(gem_name, version, extra)
      data = read_metadata(gem_name, version).merge(extra.transform_keys(&:to_s))
      File.write(metadata_path(gem_name, version), JSON.generate(data))
    end

    def self.versions(gem_name)
      dir = File.join(ROOT, gem_name)
      return [] unless Dir.exist?(dir)

      Dir.children(dir).sort
    end

    def self.all_gems
      return [] unless Dir.exist?(ROOT)

      Dir.children(ROOT).sort
    end

    def self.purge(gem_name, version)
      dir = File.join(ROOT, gem_name, version)
      FileUtils.rm_rf(dir)
      parent = File.join(ROOT, gem_name)
      Dir.rmdir(parent) if Dir.exist?(parent) && Dir.empty?(parent)
    end
  end
end
