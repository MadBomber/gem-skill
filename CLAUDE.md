# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this gem does

`gem-skill` generates `SKILL.md` files from Ruby gem documentation using an LLM (via RubyLLM), caches them globally at `~/.gem/skills/<gem_name>/<version>/SKILL.md`, and symlinks them into projects as directory links: `.claude/skills/<gem_name>/ → ~/.gem/skills/<gem_name>/<version>/`. It registers two CLI entry points: `gem skill` (global cache management) and `bundle skill` (project-aware, driven by `Gemfile.lock`), plus a `gem install --with-skill` flag.

## Commands

```bash
bundle install
bundle exec rake test                                 # run all tests (default task)
ruby -Ilib:test test/gem/skill/cache_test.rb          # run a single test file
bundle exec ruby scripts/e2e_test [GEM VERSION MODEL] # live LLM end-to-end test (needs a provider API key)
bin/dev_install                                       # point Bundler's plugin indexes at this source tree so
                                                      # `bundle skill` runs local code (no build/release needed)
bin/dev_install --reset                               # restore to the released gem install
```

Docs site is MkDocs (`mkdocs.yml`, `docs/`), deployed by `.github/workflows/deploy-github-pages.yml`.

## Architecture

### Entry points

- `lib/rubygems_plugin.rb` — loaded automatically by RubyGems; registers `gem skill` (`Gem::Commands::SkillCommand`) AND prepends `--with-skill` onto `gem install`, queuing installed gems and generating their skills in threads via a `Gem.post_install` hook + `at_exit`
- `plugins.rb` — Bundler plugin entry point; registers `bundle skill` via `Gem::Skill::BundlerPlugin` → `Gem::Skill::BundlerCommand`

### Core pipeline (in call order)

1. **`Lockfile`** (`lib/gem/skill/lockfile.rb`) — parses `Gemfile.lock`; extracts direct-dependency name→version pairs by cross-referencing the `DEPENDENCIES` and `specs:` sections
2. **`Fetcher`** (`lib/gem/skill/fetcher.rb`) — collects raw docs for a single gem/version in priority order: (1) local `Gem::Specification` gem_dir, (2) RubyGems API JSON, (3) GitHub raw README. Returns `{metadata:, readme:, changelog:}` with only populated keys
3. **`Generator`** (`lib/gem/skill/generator.rb`) — formats fetched sources into a prompt, calls RubyLLM, strips any wrapping code fence, runs `Frontmatter.build`, stores result via `Cache`. Supports streaming via block
4. **`Frontmatter`** (`lib/gem/skill/frontmatter.rb`) — deterministically (no LLM) builds/replaces the YAML frontmatter (`name` + `description`) that makes a SKILL.md discoverable by both Claude Code and Codex; enforces both assistants' name/description constraints
5. **`Cache`** (`lib/gem/skill/cache.rb`) — reads/writes `~/.gem/skills/<name>/<version>/SKILL.md` and `metadata.json`; `merge_metadata` string-normalizes keys
6. **`Verifier`** (`lib/gem/skill/verifier.rb`) — optional second LLM pass (`--verify` or `gem skill verify`) that re-checks a generated skill against the gem's actual installed source and corrects wrong signatures/claims. `changed?` is decided by a deterministic content diff, never the model's self-report; unverifiable (no local source) is recorded in metadata, not an error
7. **`Linker`** (`lib/gem/skill/linker.rb`) — creates/updates directory symlinks in the project skills dir pointing into the cache; `prune_dead_links` removes broken symlinks after a refresh

**`Runner`** (`lib/gem/skill/runner.rb`) is the shared generate+cache+link+verify orchestration used by both CLI commands; it returns a `Runner::Result` (`Data.define`) and drives a TTY spinner passed in by the caller.

### CLI layer

- `lib/gem/skill/cli/gem_command.rb` — `Gem::Commands::SkillCommand`; subcommands: `install`, `verify`, `list`, `purge`, `setup`. Multi-gem installs run concurrently with the `async` gem (`Async::Barrier`). `setup` registers the Bundler plugin and copies the bundled router skill (`ruby-gem-skills/SKILL.md` at repo root) into each detected assistant's global skill root
- `lib/gem/skill/cli/bundle_command.rb` — `Gem::Skill::BundlerCommand`; subcommands: `install`, `refresh`, `list`. `install` = generate + link all direct lockfile gems; `refresh` = skip gems already linked at the correct version. Parses its own flags (`--force`, `--verify`, `--model`, `--max-tokens`, `--temperature`, `--version`)

### LLM configuration

`Gem::Skill.configure_llm!` reads provider API keys from environment variables (see `ENV_KEY_MAP` in `lib/gem/skill.rb`) and configures RubyLLM. Called automatically by both CLI entry points. No-op if already configured.

## Key constants & environment variables

- `Cache::ROOT` = `~/.gem/skills` (override: `GEMSKILL_DIR`)
- `Linker::DEFAULT_PROJECT_DIR` = `.claude/skills` (override: `GEMSKILL_PROJECT_DIR`, re-read on every call — e.g. `.agents` for Codex)
- `Generator::DEFAULT_MODEL` = `"gpt-5.5"` (override: `GEMSKILL_MODEL` or `--model`)
- `Generator::MAX_TOKENS` = 32,767 (override: `GEMSKIL_MAX_TOKENS` — note the single-L spelling — or `--max-tokens`)
- `Generator::DEFAULT_TEMPERATURE` = 0.2 (override: `GEMSKILL_TEMPERATURE` or `--temperature`; skipped for models that reject temperature)
- `Generator::MAX_SOURCE_CHARS` = 60,000 (README truncation guard)
- `Gem::Skill::EXIT_VERIFY_FIXED` = 2 — grep-style exit status when `--verify` applied fixes (0 = clean, 1 = error)

## Testing

Uses Minitest (`Minitest::TestTask`). Unit tests live in `test/gem/skill/`; shared cache-sandboxing helpers in `test/support/cache_helpers.rb`. `scripts/e2e_test` runs a full live pipeline (fetch → generate → cache → link) against a real LLM and requires at least one provider API key.
