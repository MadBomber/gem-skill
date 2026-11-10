# frozen_string_literal: true

module Gem::Skill
  # Validates gem names and versions before they are used as filesystem path
  # components in the cache (~/.gem/skills/<name>/<version>/) and project
  # symlinks. Names and versions can originate from a Gemfile.lock or the CLI,
  # so only well-formed values are allowed to reach File.join-based path
  # builders.
  module Validation
    # A gem name is one or more characters from the RubyGems-allowed set, and
    # must start with a letter or digit. "." and ".." are rejected outright.
    GEM_NAME_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/

    def self.valid_gem_name?(name)
      name = name.to_s
      return false if name == "." || name == ".."

      GEM_NAME_PATTERN.match?(name)
    end

    def self.valid_version?(version)
      version = version.to_s
      return false if version.empty?

      !!Gem::Version.correct?(version)
    end

    def self.validate_gem_name!(name)
      raise Error, "Invalid gem name: #{name.inspect}" unless valid_gem_name?(name)

      name
    end

    def self.validate_version!(version)
      raise Error, "Invalid gem version: #{version.inspect}" unless valid_version?(version)

      version
    end

    # Convenience for the common path-building boundary: validate both a gem
    # name and a version in one call.
    def self.validate!(name, version)
      validate_gem_name!(name)
      validate_version!(version)
    end
  end
end
