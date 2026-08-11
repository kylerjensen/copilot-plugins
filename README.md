# kylerjensen/copilot-plugins

A GitHub Copilot CLI plugin marketplace holding Kyler Jensen's plugins.

## Install

```bash
copilot plugin marketplace add kylerjensen/copilot-plugins
copilot plugin install self-learning-memory@kylerjensen
```

## Plugins

### self-learning-memory

Gives Copilot a memory that improves itself. A `caveman-memory` skill defines the terse, indexed format the agent uses when writing lessons to its own memory (and how to keep that memory pruned), while three hooks close the loop deterministically: every failed tool call is logged to `~/.copilot-lessons/lessons.jsonl`, a distillery condenses repeat failures into one-line caveman lessons, and a `SessionStart` hook injects those lessons back into each new session so known-bad invocations aren't retried.

See [plugins/self-learning-memory/README.md](plugins/self-learning-memory/README.md) for the distillery cron setup and the 200-line memory-index design.

## License

MIT — see [LICENSE](LICENSE).
