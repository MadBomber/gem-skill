# bundle skill

The `bundle skill` command is project-aware: it reads `Gemfile.lock` to
determine which gems and versions are in use, generates skills for all of them,
and links the results into `.claude/skills/` (Claude Code's skill directory) in
the project root. The generated `SKILL.md` files are a shared format that other
assistants read too — see [Using with other assistants](../skill-files.md#using-with-other-assistants).

## Global options

These flags work without a subcommand:

```bash
bundle skill --version    # print installed version and exit
bundle skill -v           # same
```

## Prerequisites

Run once after installing gem-skill:

```bash
gem skill setup
```

Or add to the project `Gemfile`:

```ruby
plugin "gem-skill"
```

## Subcommands

### `bundle skill install`

Generate and link skills for all direct dependencies in `Gemfile.lock`.

```bash
bundle skill install [OPTIONS]
```

**Options:**

| Flag | Description |
|------|-------------|
| `--force` | Regenerate even if skills are already cached |
| `--verify` | Verify generated skills against each gem's source and fix mismatches (exit `2` if any fixes applied) |
| `--model MODEL` | LLM model to use (overrides `GEMSKILL_MODEL`) |
| `--max-tokens TOKENS` | Max output tokens per skill (overrides `GEMSKIL_MAX_TOKENS`; default: 32767) |
| `--version`, `-v` | Print the installed gem-skill version and exit |

**Example:**

```bash
cd your-project
bundle skill install
```

**What it processes:**

- All gems listed in the `DEPENDENCIES` section of `Gemfile.lock`
- Runtime dependencies declared in any `gemspec` referenced by the `Gemfile` (via `gemspec` directive)

All gems are processed concurrently:

```
⠋ Installing skills (claude-sonnet-4-6)
  ✓ rake 13.4.2 already cached
  ✓ zeitwerk 2.8.2 done
  ✓ ruby_llm 1.16.0 done
```

After completion, each skill is symlinked into the project skill directory
(`.claude/skills/` by default; set
[`GEMSKILL_PROJECT_DIR`](../configuration.md#gemskill_project_dir) to change it,
e.g. `.agents` for Codex):

```
your-project/.claude/skills/
├── rake     →  ~/.gem/skills/rake/13.4.2/
├── ruby_llm →  ~/.gem/skills/ruby_llm/1.16.0/
└── zeitwerk →  ~/.gem/skills/zeitwerk/2.8.2/
```

The assistant automatically reads `SKILL.md` from each linked directory (Claude
Code reads `.claude/skills/`; other assistants use their own roots).

---

### `bundle skill refresh`

Re-sync `.claude/skills/` after `bundle update`.

```bash
bundle skill refresh [OPTIONS]
```

| Flag | Description |
|------|-------------|
| `--force` | Regenerate all skills, even those already at the correct version |
| `--model MODEL` | LLM model to use |
| `--max-tokens TOKENS` | Max output tokens per skill (overrides `GEMSKIL_MAX_TOKENS`; default: 32767) |

`refresh` skips gems that are already linked at the correct version (shows
`up to date`), regenerates gems whose version changed, and removes dead symlinks
for gems no longer in `Gemfile.lock`.

**Typical workflow:**

```bash
bundle update
bundle skill refresh
```

---

### `bundle skill list`

Show all skills currently linked in this project.

```bash
bundle skill list
```

**Example output:**

```
Skills linked in .claude/skills/  (3 ok):

  [ok    ]  rake                           13.4.2
  [ok    ]  ruby_llm                       1.16.0
  [ok    ]  zeitwerk                       2.8.2
```

A `BROKEN` status means the symlink target no longer exists in the cache —
run `bundle skill install` to regenerate.

---

## Typical project workflow

```bash
# First time setup
bundle install
bundle skill install

# After bundle update
bundle update
bundle skill refresh

# Check what's linked
bundle skill list

# Force full regeneration (e.g. after model upgrade)
bundle skill install --force --model claude-opus-4-8
```
