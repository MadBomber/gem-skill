# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class LinkerTest < Minitest::Test
  def setup
    @project_dir  = Dir.mktmpdir
    @cache_dir    = Dir.mktmpdir
    stub_cache_root(@cache_dir)

    # Pre-populate a cached skill
    @gem_name = "my_gem"
    @version  = "1.0.0"
    skill_dir = File.join(@cache_dir, @gem_name, @version)
    FileUtils.mkdir_p(skill_dir)
    File.write(File.join(skill_dir, "SKILL.md"), "# My Gem Skill")
  end

  def teardown
    FileUtils.rm_rf(@project_dir)
    FileUtils.rm_rf(@cache_dir)
    restore_cache_root
  end

  def test_link_creates_directory_symlink_in_claude_skills
    Gem::Skill::Linker.link(@gem_name, @version, @project_dir)
    link = File.join(@project_dir, ".claude", "skills", @gem_name)
    assert File.symlink?(link), "expected a symlink at #{link}"
    assert File.directory?(link), "expected symlink to resolve to a directory"
    assert File.exist?(File.join(link, "SKILL.md")), "expected SKILL.md inside linked directory"
  end

  def test_link_replaces_existing_symlink
    Gem::Skill::Linker.link(@gem_name, @version, @project_dir)
    Gem::Skill::Linker.link(@gem_name, @version, @project_dir) # idempotent
    link = File.join(@project_dir, ".claude", "skills", @gem_name)
    assert File.symlink?(link)
  end

  def test_unlink_removes_symlink
    Gem::Skill::Linker.link(@gem_name, @version, @project_dir)
    Gem::Skill::Linker.unlink(@gem_name, @project_dir)
    link = File.join(@project_dir, ".claude", "skills", @gem_name)
    refute File.exist?(link)
  end

  def test_linked_gems_returns_entry
    Gem::Skill::Linker.link(@gem_name, @version, @project_dir)
    entries = Gem::Skill::Linker.linked_gems(@project_dir)
    assert_equal 1, entries.size
    assert_equal @gem_name, entries.first[:gem_name]
    assert_equal @version,  entries.first[:version]
    assert entries.first[:valid]
  end

  def test_prune_dead_links_removes_broken_symlinks
    Gem::Skill::Linker.link(@gem_name, @version, @project_dir)
    # Delete the cached skill to simulate a broken link
    FileUtils.rm_rf(File.join(@cache_dir, @gem_name))
    Gem::Skill::Linker.prune_dead_links(@project_dir)
    assert_empty Gem::Skill::Linker.linked_gems(@project_dir)
  end

  # --- GEMSKILL_PROJECT_DIR ---

  def test_project_dir_defaults_to_claude_skills
    with_env("GEMSKILL_PROJECT_DIR", nil) do
      assert_equal ".claude/skills", Gem::Skill::Linker.project_dir
    end
  end

  def test_project_dir_honors_env_override
    with_env("GEMSKILL_PROJECT_DIR", ".agents") do
      assert_equal ".agents", Gem::Skill::Linker.project_dir
    end
  end

  def test_project_dir_falls_back_to_default_when_blank
    with_env("GEMSKILL_PROJECT_DIR", "  ") do
      assert_equal ".claude/skills", Gem::Skill::Linker.project_dir
    end
  end

  def test_link_writes_into_custom_project_dir
    with_env("GEMSKILL_PROJECT_DIR", ".codex") do
      Gem::Skill::Linker.link(@gem_name, @version, @project_dir)
      link = File.join(@project_dir, ".codex", @gem_name)
      assert File.symlink?(link), "expected symlink under custom project dir"
      assert File.exist?(File.join(link, "SKILL.md"))
      # and round-trips through linked_gems
      entries = Gem::Skill::Linker.linked_gems(@project_dir)
      assert_equal @gem_name, entries.first[:gem_name]
    end
  end

  private

  def with_env(key, value)
    original = ENV[key]
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end
    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

end
