# Changelog

All notable changes to gem-skill are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Changed
- Validate gem names and versions before building cache paths. A gem name must be a plain RubyGems name and a version must parse as a `Gem::Version`; malformed values from a `Gemfile.lock` are dropped by `Lockfile.parse`, and the `Cache`/`Linker` path builders raise `Gem::Skill::Error` for them.

### Added
- Bundled `ruby-gem-skills` "router" skill (shipped at the gem root) that teaches assistants how to find cached gem skills in `~/.gem/skills` — a directory neither Claude Code nor Codex scans by default. `gem skill setup` now also copies this skill into each detected assistant's default root (`~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills`), creating none that don't already exist. `Gem::Skill::ROUTER_SKILL_NAME` / `ROUTER_SKILL_DIR` locate the bundled template.
- `GEMSKIL_MAX_TOKENS` environment variable (default `32767`) — caps the number of output tokens the LLM may generate per skill file. Raise this if generated `SKILL.md` files are being truncated.
- `--max-tokens TOKENS` CLI flag on `gem skill install`, `bundle skill install`, and `bundle skill refresh` — overrides `GEMSKIL_MAX_TOKENS` for a single invocation. Provider-correct parameter name is selected automatically (`max_completion_tokens` for OpenAI models, `max_tokens` for all others).
- `GEMSKILL_TEMPERATURE` environment variable (default `0.2`) — sampling temperature for generation. Lower values produce more consistent, less variable output, appropriate for factual reference docs. Applied only to models that support a temperature parameter; reasoning models (e.g. `gpt-5.5`) report `temperature: false` in their RubyLLM metadata and the value is silently skipped for them.
- `--temperature TEMP` CLI flag on `gem skill install` — overrides `GEMSKILL_TEMPERATURE` for a single invocation.
- `documentation_uri` and `bug_tracker_uri` gemspec metadata, so RubyGems.org links to the docs site and the issue tracker.

### Fixed
- `gem skill setup` now exits `1` when registering the Bundler plugin fails or the bundled router skill is missing, instead of always exiting `0`. A failed plugin registration no longer stops it from installing the router skill. Finding no assistant directory is still a success. (#29)
- `--max-tokens` and `GEMSKIL_MAX_TOKENS` now cap the verify pass (`--verify` and `gem skill verify`) as well as generation; verification previously sent no output limit.
- `gem skill` now rejects a non-numeric `--max-tokens` or `--temperature` value with an error, as `bundle skill` does, instead of silently sending `0` / `0.0`. (#18)
- `bundle skill install` and `bundle skill refresh` now exit `1` when any gem fails, instead of `0` (or `2` when `--verify` also fixed another gem). They follow the same rule as `gem skill`: an error (`1`) takes precedence over verify-fixed (`2`), which takes precedence over `0`. (#17)
- Stray non-gem entries no longer crash cache listing or link pruning. A `.DS_Store` in the skills cache (at the root or inside a gem folder) made `gem skill list` raise `Invalid gem name`/`Invalid gem version`, and a broken non-gem symlink in the project skills dir made `bundle skill install`/`refresh` raise at the prune step. `Cache.all_gems`, `Cache.versions` and `Linker.linked_gems` now skip entries that are not valid gem names or versions, so prune also leaves a user's own links alone. (#16)
- `docs/cache.md` and `docs/how-it-works.md` now describe the `verification` metadata and the `Verifier::Result` / `Runner::Result` fields the code actually writes; they still listed the removed `used_source_code`, `source`, `change_count` and `changes` fields and `Fetcher#source_manifest`. (#14)
- `bundle skill` no longer skips gems from a `git:` source. Bundler lists them as `foo!` in `DEPENDENCIES`; `Lockfile.parse` now strips the `!` for names found under a `GIT` section, so they match their spec. The project's own `path:` gem stays skipped. (#8)
- `ollama/...` models can now be configured: `OLLAMA_API_BASE` and `OLLAMA_API_KEY` are applied to RubyLLM's `ollama_api_base` and `ollama_api_key`. (#15)
- `gem skill` now exits `1` on error paths (unknown subcommand, missing gem name, and any failed per-gem install/verify) instead of always exiting `0`, so scripts and CI can detect failures as the docs and CHANGELOG already promised. An error (`1`) takes precedence over a verify-fixed result (`2`). (#7)
- `bundle skill` now consumes flag values (`--model gpt-x install` no longer fails as "unknown subcommand"), accepts the documented `--temperature TEMP` and `gem skill`'s `-f`/`-m` short flags, and rejects unknown or abbreviated flags and non-decimal `--max-tokens` instead of ignoring or guessing.
- `gem skill verify` no longer overwrites a cached skill with a truncated reply. When the model's response opened `===BEGIN SKILL===` but was cut off before `===END SKILL===`, the verifier accepted the partial tail and wrote it over the cache; it now falls back to the original skill whenever the end marker is missing, as the method already promised.
- `bundle install` no longer prints `Error loading RubyGems plugin ... uninitialized constant Gem::CommandManager (NameError)` for gem-skill. Bundler loads RubyGems plugins without the command manager, so `lib/rubygems_plugin.rb` now requires `rubygems/command_manager` itself.
- `lms/` and `apfel/` models that are not in RubyLLM's static model registry (every `apfel/` model and most `lms/` models) no longer fail with `RubyLLM::ModelNotFoundError` before any request is sent. A model with no registry entry is treated as supporting temperature.
- `strip_wrapper_fence` no longer deletes the closing ``` of a skill that legitimately ends with a code block. The trailing wrapper fence is now stripped only when a matching opening wrapper fence (```` ```markdown ```` / ```` ``` ```` at the very start) was present. Previously the final ``` was removed unconditionally, leaving the last code block open at end-of-file — which looked like the LLM truncating its output but was entirely a post-processing bug. Regenerate affected skills with `gem skill install GEM --force`.
- `docs/installation.md` now gives the Ruby requirement as >= 3.4, matching the gemspec (it said >= 3.2.0).
- The "Cache layout" link in `docs/commands/gem-skill.md` now points at `../cache.md#metadatajson`; the broken relative link made `mkdocs build --strict` abort.
- `bundle skill install` and `refresh` with no `Gemfile.lock` now print `gem-skill: Gemfile.lock not found at Gemfile.lock` and exit `1`, instead of Bundler's error-report template and a backtrace. (#28)

### Changed
- `Generator::MAX_TOKENS` constant reads from `GEMSKIL_MAX_TOKENS` and is passed via `with_params` to every `RubyLLM.chat` call, covering both streaming and non-streaming paths.
- `Generator#initialize` now accepts `max_tokens:` and `temperature:` keywords so callers can override the token cap and sampling temperature per-instance without touching the environment.
- `Generator` sets `with_temperature` only when the model's RubyLLM metadata does not mark temperature unsupported, avoiding API errors on reasoning models.
- `Runner.install_skill` accepts and forwards `max_tokens:` and `temperature:` to `Generator.new`.
- `README.md` Configuration section now lists all environment variables (gem-skill-specific and provider API keys) in a single reference table.
- `docs/configuration.md` documents the new `GEMSKIL_MAX_TOKENS` and `GEMSKILL_TEMPERATURE` variables alongside the existing `GEMSKILL_MODEL` entry.
- `docs/commands/gem-skill.md` and `docs/commands/bundle-skill.md` option tables updated with `--max-tokens` and `--temperature`.
- Documented local-model support (`lms/` and `apfel/` model prefixes) and `GEMSKILL_REQUEST_TIMEOUT` in the README and `docs/configuration.md`.

## [0.2.0] - 2026-06-19

### Added
- `--verify` flag for `gem skill install` and `bundle skill install`/`refresh` — runs a second LLM pass that checks the generated skill's code against the gem's **actual source code** (the source of truth) and corrects mismatched method signatures, default argument values, visibility, return values, and behavioral claims. READMEs and docstrings are frequently stale; this catches it.
- `gem skill verify GEM_NAME [GEM_NAME ...]` subcommand — verify an already-cached skill in place (never generates; errors if the gem isn't installed or the skill isn't cached).
- `gem skill list` flags verified versions with a green checkmark (`✓`); unverified versions show no mark. The checkmark is colored only for interactive terminals.
- `GEMSKILL_PROJECT_DIR` env var (default `.claude/skills`) — controls the project-relative directory `bundle skill` writes symlinks into. Codex users can set it to `.agents` or `.codex` to link skills into a Codex project root.
- `Gem::Skill::Verifier` — the verification pass. Whether the skill changed is decided by a deterministic diff (not the model's self-report), so the result is trustworthy.
- `Gem::Skill::Frontmatter` — deterministic, idempotent frontmatter builder shared by the generator and verifier, so a skill always carries valid frontmatter even if the model omits it.
- `Fetcher#source_code` — concatenates the gem's `lib/**/*.rb` (size-capped) as the ground truth the verifier checks against.
- `Cache.read_metadata`, `Cache.write_skill`, `Cache.merge_metadata` — support verifying/rewriting a cached skill without clobbering `generated_at`/`model`/`sources`.
- Verified skills gain a `verification` block in `metadata.json` recording that the skill was checked against the gem's actual source: `verified`, `verified_at`, `model`, and `fixed` (whether the check changed anything). When no installed source is available to check against, it records `verified: false` with a `skipped_reason`.
- Exit status `2` (`Gem::Skill::EXIT_VERIFY_FIXED`) when `--verify` found and corrected problems, so CI can detect README/source drift. `0` = clean, `1` = error.

### Changed
- `Runner.install_skill` now accepts `verify:` and returns a `Runner::Result` (`error`, `verify_fixed`) instead of a nil/error-string.
- Documentation reworded to be assistant-neutral: `SKILL.md` is a shared format read by Claude Code, OpenAI Codex, and other AI coding assistants. Added guidance for pointing non-Claude assistants (e.g. Codex's `~/.codex/skills`, the vendor-neutral `~/.agents/skills`) at the shared cache. `bundle skill` still links into `.claude/skills/` (Claude Code's convention).

### Fixed
- `bundle skill install` and `bundle skill refresh` now exit `1` when any gem fails, instead of `0` (or `2` when `--verify` also fixed another gem). They follow the same rule as `gem skill`: an error (`1`) takes precedence over verify-fixed (`2`), which takes precedence over `0`. (#17)
- Generated `SKILL.md` files now include the required YAML frontmatter (`name` + `description`). Without it, the files were never registered/triggered as skills by Claude Code or OpenAI Codex — they were just markdown in a skills folder. `name` is the gem name normalized to hyphen-case (e.g. `ruby_llm` → `ruby-llm`); `description` is a trigger-oriented one-liner derived from the Overview (sanitized for both assistants: single line, no angle brackets). Verified against Claude Code's skill validator and OpenAI's Codex skill spec.

### Note
- Skills cached before this change lack frontmatter; regenerate them with `gem skill install GEM --force` (or `bundle skill refresh --force`) to add it.

## [0.1.3] - 2026-06-17

### Added
- `gem skill setup` subcommand — registers gem-skill as a Bundler plugin in one step
- `--version` / `-v` flag for both `gem skill` and `bundle skill`
- `post_install_message` guiding users to run `gem skill setup` after install
- `async` gem dependency — concurrent fiber-based LLM calls replace threads
- `Gem::Skill::Runner` module — shared `install_skill` core extracted from both CLI commands
- `test/support/cache_helpers.rb` — shared `stub_cache_root`/`restore_cache_root` test helpers
- MkDocs documentation site (`docs/`) with full reference for all commands, cache layout, skill file format, and architecture

### Changed
- `bundle skill install` and `bundle skill refresh` now run all gems concurrently via `Async::Barrier` (previously sequential)
- `gem skill install` also migrated from threads to async fibers
- `Lockfile.gems` now includes runtime dependencies declared in gemspec files (via `gemspec` in `Gemfile`), not just direct `Gemfile` entries
- `.claude/skills/` symlinks now point to version directories (e.g. `~/.gem/skills/faraday/2.14.3/`) instead of individual `SKILL.md` files
- `GEMSKILL_DIR` environment variable controls the cache root (default: `~/.gem/skills`)
- `GEMSKILL_MODEL` environment variable controls the default LLM model
- `scripts/e2e_test` updated to exercise the full pipeline: Fetch → Runner → Cache → Linker

### Removed
- `thor` runtime dependency (was declared but never used)

## [0.1.0] - 2026-06-16

- Initial release
