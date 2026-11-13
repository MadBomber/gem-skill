# frozen_string_literal: true

module Gem::Skill
  # Parses Gemfile.lock to extract direct dependency gem name/version pairs.
  # Direct deps are listed in the DEPENDENCIES section; versions come from specs.
  module Lockfile
    def self.gems(lockfile_path = "Gemfile.lock")
      raise Error, "Gemfile.lock not found at #{lockfile_path}" unless File.exist?(lockfile_path)

      parse(File.read(lockfile_path))
    end

    def self.parse(content)
      specs  = parse_specs(content)
      git    = parse_git_spec_names(content)
      direct = parse_direct_names(content).map { |name| strip_git_bang(name, git) } +
               parse_path_dep_names(content)
      direct.uniq.each_with_object({}) do |name, hash|
        version = specs[name]
        hash[name] = version if version && Validation.valid_gem_name?(name) && Validation.valid_version?(version)
      end
    end

    def self.parse_specs(content)
      in_specs = false
      specs    = {}

      content.each_line do |line|
        if line.strip == "specs:"
          in_specs = true
          next
        elsif in_specs && line =~ /\A {4}(\S+) \(([^)]+)\)/
          specs[Regexp.last_match(1)] = Regexp.last_match(2)
        elsif in_specs && line !~ /\A /
          in_specs = false
        end
      end

      specs
    end

    # Bundler marks gems from a git: source as `foo!` in DEPENDENCIES. Strip the
    # bang only for those, so the project's own path gem (`name!`) stays skipped.
    def self.strip_git_bang(name, git_names)
      bare = name.delete_suffix("!")
      name.end_with?("!") && git_names.include?(bare) ? bare : name
    end

    def self.parse_git_spec_names(content)
      in_git   = false
      in_specs = false
      names    = []

      content.each_line do |line|
        if line.strip == "GIT"
          in_git   = true
          in_specs = false
        elsif in_git && line.strip == "specs:"
          in_specs = true
        elsif in_git && in_specs && line =~ /\A {4}(\S+) \(/
          names << Regexp.last_match(1)
        elsif in_git && !line.start_with?(" ") && !line.strip.empty?
          in_git   = false
          in_specs = false
        end
      end

      names
    end

    def self.parse_path_dep_names(content)
      in_path  = false
      in_specs = false
      in_gem   = false
      names    = []

      content.each_line do |line|
        if line.strip == "PATH"
          in_path = true
          in_specs = false
          in_gem   = false
        elsif in_path && line.strip == "specs:"
          in_specs = true
        elsif in_path && in_specs && line =~ /\A {4}\S/
          in_gem = true
        elsif in_path && in_specs && in_gem && line =~ /\A {6}(\S+)/
          names << Regexp.last_match(1)
        elsif in_path && !line.start_with?(" ") && !line.strip.empty?
          in_path  = false
          in_specs = false
          in_gem   = false
        end
      end

      names
    end

    def self.parse_direct_names(content)
      in_deps = false
      names   = []

      content.each_line do |line|
        if line.strip == "DEPENDENCIES"
          in_deps = true
          next
        elsif in_deps && line =~ /\A  (\S+)/
          # Strip version constraints from dep names like "ruby_llm (>= 1.0)"
          names << Regexp.last_match(1)
        elsif in_deps && !line.strip.empty?
          in_deps = false
        end
      end

      names
    end
  end
end
