# Cache

## Location

The global skill cache lives at `~/.gem/skills` by default. Override with:

```bash
export GEMSKILL_DIR="/path/to/your/cache"
```

## Structure

```
~/.gem/skills/
├── debug_me/
│   └── 1.1.0/
│       ├── SKILL.md
│       └── metadata.json
├── faraday/
│   ├── 2.12.0/
│   │   ├── SKILL.md
│   │   └── metadata.json
│   └── 2.14.3/
│       ├── SKILL.md
│       └── metadata.json
└── zeitwerk/
    └── 2.8.2/
        ├── SKILL.md
        └── metadata.json
```

Each gem can have multiple cached versions. They coexist without conflict — two
projects pinning different versions of the same gem each get the correct skill.

## Files

### `SKILL.md`

The generated skill file. Contains structured documentation for AI coding
assistants (Claude Code, OpenAI Codex, and others). See
[Skill Files](skill-files.md) for the format.

### `metadata.json`

Stores provenance information:

```json
{
  "gem_name": "faraday",
  "version": "2.14.3",
  "model": "claude-sonnet-4-6",
  "generated_at": "2026-06-17T10:23:45Z",
  "sources": ["readme", "changelog", "rubygems"]
}
```

When a skill is generated with `--verify`, a `verification` block is added that
records that the gem's actual source code was consulted, exactly which files were
examined, and the issue-ready corrections that resulted:

```json
{
  "gem_name": "tty-spinner",
  "version": "0.9.3",
  "model": "gpt-5.5",
  "generated_at": "2026-06-17T10:23:45Z",
  "sources": ["metadata", "readme", "changelog"],
  "verification": {
    "verified": true,
    "verified_at": "2026-06-19T14:02:11Z",
    "model": "gpt-5.5",
    "used_source_code": true,
    "source": {
      "files": ["lib/tty/spinner.rb", "lib/tty/spinner/multi.rb", "lib/tty/spinner/formats.rb"],
      "file_count": 3,
      "chars": 26452,
      "truncated": false
    },
    "fixed": true,
    "change_count": 1,
    "changes": [
      {
        "category": "default_value",
        "symbol": "TTY::Spinner#stop",
        "skill_section": "Core API",
        "source_location": "lib/tty/spinner.rb:387",
        "was": "stop(message = nil)",
        "now": "stop(message = '')",
        "detail": "Default argument is an empty string, not nil; the README implied nil.",
        "source_evidence": "def stop(stop_message = '')"
      }
    ]
  }
}
```

Each entry in `changes` is detailed enough to open a documentation issue against
the gem: it names the affected symbol, where the skill was wrong, what it claimed
versus the truth, and the source snippet that proves it. When source isn't
available locally, `verification` instead records `"verified": false`,
`"used_source_code": false`, and a `"skipped_reason"`.

## Cache commands

```bash
# List everything in the cache
gem skill list

# Remove a specific version
gem skill purge faraday 2.12.0

# Remove all versions of a gem
gem skill purge faraday --all
```

## Sharing the cache

You can share a skill cache across machines by pointing `GEMSKILL_DIR` at a
shared location:

```bash
# Team-shared network drive
export GEMSKILL_DIR="/Volumes/team-shared/gem-skills"
```

All machines with the same `GEMSKILL_DIR` will read and write to the same cache.
Skills generated on one machine are immediately available on others.

## Project symlinks

Projects don't store skills locally — they hold symlinks into the global cache.
`bundle skill` writes these into the directory named by
[`GEMSKILL_PROJECT_DIR`](configuration.md#gemskill_project_dir), which defaults
to `.claude/skills/` (Claude Code's convention):

```
your-project/.claude/skills/
├── faraday  →  ~/.gem/skills/faraday/2.14.3/
└── zeitwerk →  ~/.gem/skills/zeitwerk/2.8.2/
```

Each symlink points to the **version directory**, and the assistant reads
`SKILL.md` from inside the linked directory.

`bundle skill refresh` updates symlinks when versions change after `bundle update`.
`bundle skill list` shows the status of all current symlinks.

### Other assistants

`SKILL.md` is a shared format and the cache is assistant-neutral. Assistants
other than Claude Code look in their own skill roots — for example, OpenAI Codex
uses `~/.codex/skills` and the vendor-neutral `~/.agents/skills` globally, or
project-local `.agents/` / `.codex/`.

For project links, set `GEMSKILL_PROJECT_DIR` so `bundle skill` writes straight
into the right directory:

```bash
export GEMSKILL_PROJECT_DIR=".agents"
bundle skill install
```

For a global, cross-project link, symlink a cached version directory into the
assistant's global root:

```bash
ln -s ~/.gem/skills/faraday/2.14.3 ~/.agents/skills/faraday
```

Note that linking only makes a skill *available*; some assistants (e.g. Codex)
won't *activate* it unless it's in the session's available-skills list or you
reference it explicitly. See
[Using with other assistants](skill-files.md#using-with-other-assistants).

## Regenerating skills

Skills do not auto-expire. Regenerate explicitly when you want updated content:

```bash
# Regenerate one gem
gem skill install faraday --force

# Regenerate all project gems with a better model
bundle skill install --force --model claude-opus-4-8
```
