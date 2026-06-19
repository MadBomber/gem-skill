# Skill Files

A `SKILL.md` is a structured Markdown document that gives an AI coding assistant
deep, practical knowledge about a Ruby gem. It's a shared format — assistants
such as Claude Code and OpenAI Codex read it automatically when it is present in
the skills directory they look in (Claude Code uses `.claude/skills/`; see
[Using the cache with other assistants](#using-with-other-assistants)).

## Format

Every generated skill starts with a top-level heading identifying the gem and
version, then covers seven sections:

```markdown
# faraday v2.14.3

## Overview
What the gem does and when to reach for it.

## Installation
Exact Gemfile/gemspec lines and any required post-install steps.

## Core API
Key classes, methods, and options with real method signatures and return values.

## Common Patterns
The 3–5 most frequent real-world usage patterns with working code examples.

## Gotchas & Edge Cases
Surprising defaults, version-specific behavior, thread safety, encoding issues.

## Configuration
Initializer patterns, environment variables, defaults worth knowing.

## Testing
How to test code that uses this gem: mocks, fakes, fixtures, VCR patterns.
```

## What an assistant does with it

When an assistant opens a project whose skills directory contains `SKILL.md`
files, it reads every one it finds (Claude Code, for instance, reads everything
in `.claude/skills/`). This means:

- The assistant knows the correct API for the exact version you're using
- No token cost re-deriving usage from READMEs mid-conversation
- The knowledge persists across conversation turns
- Multiple gems can be in scope simultaneously

## Sources used to generate

The LLM is given up to three sources per gem (in priority order):

1. **Local README + CHANGELOG** — from the gem's install directory
2. **RubyGems API** — summary, dependencies, source URI
3. **GitHub raw README** — fetched when not installed locally

Content is synthesized, not copied verbatim. The model is instructed to write
as a knowledgeable colleague, not a marketing document.

## Quality and regeneration

Skill quality depends on the documentation available for the gem and the model
used. For gems with poor upstream documentation, results will reflect that.

To improve a skill:

```bash
# Use a more capable model
gem skill install my_gem --force --model claude-opus-4-8

# Or set it as the default
export GEMSKILL_MODEL="claude-opus-4-8"
gem skill install my_gem --force
```

## Version specificity

Skills are cached per version. `faraday 2.12.0` and `faraday 2.14.3` each get
their own `SKILL.md`. Symlinks in `.claude/skills/` point to the version
matching your `Gemfile.lock`, so the assistant always has the right version
context.

## Using with other assistants

`SKILL.md` is not specific to one assistant. The `~/.gem/skills` cache is
assistant-neutral; `bundle skill` links skills into `.claude/skills/`, which
Claude Code reads automatically. Other assistants discover skills in their own
roots:

| Assistant | Global roots | Project-local roots |
|---|---|---|
| Claude Code | `~/.claude/skills/` | `.claude/skills/` |
| OpenAI Codex | `~/.codex/skills`, `~/.agents/skills` | `.agents/`, `.codex/` |

**Project-local (recommended):** point `bundle skill` at the right directory with
the `GEMSKILL_PROJECT_DIR` environment variable (default `.claude/skills`):

```bash
export GEMSKILL_PROJECT_DIR=".agents"   # or ".codex"
bundle skill install                    # symlinks now land in .agents/
```

See [`GEMSKILL_PROJECT_DIR`](configuration.md#gemskill_project_dir) for the full
table of suggested values.

**Global:** to share cached skills across all projects for an assistant, symlink
a cached version directory into its global root:

```bash
ln -s ~/.gem/skills/faraday/2.14.3 ~/.agents/skills/faraday
```

!!! note "Availability is not the same as activation"
    Assistants differ in how a present `SKILL.md` becomes active. **Claude Code**
    treats every `SKILL.md` under `.claude/skills/` as active automatically.
    **OpenAI Codex** does *not* auto-activate a skill just because the file
    exists — it must appear in the session's available-skills list, or you must
    explicitly point Codex at it. So linking a skill into a Codex root makes it
    *available* but may not make it *active* on its own; check your assistant's
    skill-discovery rules.
