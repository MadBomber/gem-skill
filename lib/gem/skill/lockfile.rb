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
      direct = parse_direct_names(content) + parse_path_dep_names(content)
      direct.uniq.each_with_object({}) do |name, hash|
        hash[name] = specs[name] if specs.key?(name)
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
