# frozen_string_literal: true

require "test_helper"

# Every environment variable the gem reads must be documented, so a new
# setting can't ship invisible to users.
class DocsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_every_env_var_is_documented
    vars = env_vars_read_by_lib
    %w[README.md docs/configuration.md].each do |doc|
      text    = read(doc)
      missing = vars.reject { |var| text.include?("`#{var}`") }

      assert_empty missing, "#{doc} does not document: #{missing.join(', ')}"
    end
  end

  def test_installation_doc_matches_gemspec_ruby_floor
    floor = Gem::Specification.load(File.join(ROOT, "gem-skill.gemspec")).required_ruby_version.to_s

    assert read("docs/installation.md").include?("Ruby #{floor}"), "docs/installation.md should say Ruby #{floor}"
  end

  private

  def read(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def env_vars_read_by_lib
    fetched = Dir["lib/**/*.rb", base: ROOT].flat_map do |file|
      read(file).scan(/ENV(?:\.fetch\(|\.key\?\(|\[)\s*["']([A-Z0-9_]+)["']/).flatten
    end
    (fetched + Gem::Skill::ENV_KEY_MAP.values).uniq.sort
  end
end
