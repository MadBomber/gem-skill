# Configuration

## LLM provider API keys

gem-skill uses [RubyLLM](https://github.com/crmne/ruby_llm) to generate skills.
Set at least one provider API key, or use a [local model](#local-models),
before running any `install` command:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."   # Claude models
export OPENAI_API_KEY="sk-..."          # GPT models
export GEMINI_API_KEY="..."             # Gemini models
```

Other supported providers:

| Environment variable    | Provider     |
|------------------------|--------------|
| `ANTHROPIC_API_KEY`    | Anthropic    |
| `OPENAI_API_KEY`       | OpenAI       |
| `GEMINI_API_KEY`       | Google Gemini|
| `MISTRAL_API_KEY`      | Mistral      |
| `DEEPSEEK_API_KEY`     | DeepSeek     |
| `OPENROUTER_API_KEY`   | OpenRouter   |
| `XAI_API_KEY`          | xAI (Grok)   |

## Local models

gem-skill can generate skills with a model running on your own machine, with
no API key and no per-token cost. Prefix the model name with the provider:

| Prefix   | Provider | Server URL (default) | Token, only if the server requires one |
|----------|----------|----------------------|----------------------------------------|
| `lms/`   | [LM Studio](https://lmstudio.ai) | `LMS_API_BASE` (`http://localhost:1234/v1`) | `LMS_API_KEY` |
| `apfel/` | [Apfel](https://apfel.franzai.com/) (Apple's on-device model; Apple Silicon, macOS 26+, Apple Intelligence enabled) | `APFEL_API_BASE` (`http://127.0.0.1:11434/v1`) | `APFEL_API_KEY` (set with `apfel --serve --token`) |
| `ollama/` | [Ollama](https://ollama.com) | `OLLAMA_API_BASE` (no default; usually `http://localhost:11434/v1`) | _(not needed)_ |

```bash
gem skill install faraday --model lms/qwen/qwen3-4b
export GEMSKILL_MODEL="lms/qwen/qwen3-4b"   # or make it the default
```

The prefix is split off only when the text before the first `/` names a
provider registered with RubyLLM (`lms`, `apfel`, `openai`, `anthropic`, and so
on), so `lms/qwen/qwen3-4b` sends `qwen/qwen3-4b` to LM Studio. A model whose
first segment is not a provider name is passed to RubyLLM unchanged.

!!! warning "Apfel's context window is small"
    Apple's on-device model has a combined input and output context of 4,096
    tokens. A skill prompt carries the gem's README and other docs (and
    `--verify` adds its source code), so most gems won't fit and the output
    will be cut short or rejected. If you try it anyway, lower
    [`GEMSKIL_MAX_TOKENS`](#gemskil_max_tokens) from its 32767 default to fit
    the window, and skip `--verify`: the verify pass has no output cap.
    LM Studio, with a model that has a large context window, is the better
    local choice.

Local models can be slow to produce a full skill; see
[`GEMSKILL_REQUEST_TIMEOUT`](#gemskill_request_timeout).

## gem-skill environment variables

### `GEMSKILL_DIR`

Controls where generated skills are cached.

| | |
|---|---|
| **Default** | `~/.gem/skills` |
| **Example** | `export GEMSKILL_DIR="/Volumes/shared/gem-skills"` |

Useful for sharing a skill cache across machines via a network drive, or for
keeping skills in a non-standard location.

### `GEMSKILL_PROJECT_DIR`

The project-relative directory where `bundle skill` writes its symlinks into the
cache. Change it to match whichever assistant you use.

| | |
|---|---|
| **Default** | `.claude/skills` (Claude Code) |
| **Example** | `export GEMSKILL_PROJECT_DIR=".agents"` |

`SKILL.md` is a shared format, but each assistant looks for skills in its own
project directory:

| Assistant    | Suggested `GEMSKILL_PROJECT_DIR` |
|--------------|----------------------------------|
| Claude Code  | `.claude/skills` (default)       |
| OpenAI Codex | `.agents` or `.codex`            |

```bash
# Claude Code (default — no need to set anything)
bundle skill install

# OpenAI Codex — link into a Codex project root instead
export GEMSKILL_PROJECT_DIR=".agents"
bundle skill install        # symlinks now land in .agents/
```

A blank or unset value falls back to the `.claude/skills` default.

!!! note "Availability is not activation"
    Setting `GEMSKILL_PROJECT_DIR` controls *where the symlinks are written*. It
    does not change how an assistant decides a skill is active. Claude Code
    activates every `SKILL.md` under `.claude/skills/` automatically; other
    assistants (e.g. Codex) may require the skill to be in the session's
    available-skills list or referenced explicitly. See
    [Using with other assistants](skill-files.md#using-with-other-assistants).

### `GEMSKIL_MAX_TOKENS`

Controls the maximum number of output tokens the LLM may generate for each skill file.
Increase this if generated `SKILL.md` files are being truncated.

| | |
|---|---|
| **Default** | `32767` |
| **Example** | `export GEMSKIL_MAX_TOKENS=65536` |

### `GEMSKILL_TEMPERATURE`

Sampling temperature for generation. Lower values produce more consistent,
deterministic output — appropriate for factual reference documentation.

| | |
|---|---|
| **Default** | `0.2` |
| **Example** | `export GEMSKILL_TEMPERATURE=0.0` |

Only applied to models that support a temperature parameter. Reasoning models
(e.g. `gpt-5.5`) reject it, so the value is silently skipped for them — switch to
a temperature-supporting model (Claude, Gemini, older GPT) to benefit.

### `GEMSKILL_MODEL`

Controls which LLM model is used when generating skills.

| | |
|---|---|
| **Default** | `gpt-5.5` |
| **Example** | `export GEMSKILL_MODEL="claude-opus-4-8"` |

The `--model` flag on any command overrides `GEMSKILL_MODEL` for that single
invocation only. Use a `lms/` or `apfel/` prefix to pick a
[local model](#local-models).

### `GEMSKILL_REQUEST_TIMEOUT`

HTTP timeout, in seconds, for each LLM request.

| | |
|---|---|
| **Default** | `900` |
| **Example** | `export GEMSKILL_REQUEST_TIMEOUT=1800` |

RubyLLM's own default (300 seconds) suits hosted APIs; gem-skill raises it
because a local model can be slow to respond. `gem skill install` and
`bundle skill` stream generation, so the timeout mostly covers the wait before
output starts. `--verify`, `gem skill verify` and `gem install --with-skill`
wait for the whole response, so they need the most headroom. RubyLLM retries
a request that times out before any output arrives (3 retries by default), so
a stuck request can take several times this long to fail.

## Recommended shell configuration

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export GEMSKILL_MODEL="claude-sonnet-4-6"   # or whichever model you prefer
```

## Model selection guidance

| Model | Best for |
|-------|----------|
| Claude Opus 4.8 | Highest quality skills; comprehensive coverage |
| Claude Sonnet 4.6 | Good balance of quality and speed |
| Claude Haiku 4.5 | Fast, cheap; good for simple gems |
| GPT-5.5 | Default; strong general-purpose coverage |

Pass `--model MODEL` to any install command to override for one run:

```bash
gem skill install rails --model claude-opus-4-8
bundle skill install --model claude-haiku-4-5
```
