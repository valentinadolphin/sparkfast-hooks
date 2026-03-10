# sparkfast-hooks

6 hooks for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that improve quality, safety, and session continuity. Works on any Flutter/Dart project.

## What do these hooks do?

| Hook | What it does |
|------|-------------|
| **Auto-format** | Formats your Dart code automatically every time Claude edits a file |
| **File size warning** | Warns Claude when a file gets too big (>500 lines) so it splits it |
| **Secret protection** | Stops Claude from accidentally committing passwords, API keys, or secret files |
| **Context monitor** | Warns Claude when the conversation is getting long so it doesn't lose track |
| **Pre-compact save** | Saves what Claude was working on before the conversation gets compressed |
| **Post-compact restore** | Restores that context after compression so Claude picks up where it left off |

## Installation

### Step 1: Make sure you have `jq` installed

Open Terminal and run:

```
brew install jq
```

If it says "already installed", you're good.

### Step 2: Go to your project folder

```
cd /path/to/your/project
```

Replace `/path/to/your/project` with the actual path. For example:

```
cd ~/development/MyApp
```

### Step 3: Run the installer

```
bash <(curl -sL https://raw.githubusercontent.com/valentinadolphin/sparkfast-hooks/main/install.sh)
```

You should see: **"Done! 6 hooks installed."**

### Step 4: Restart Claude Code

Close Claude Code and open it again. The hooks are now active.

## Uninstall

Delete the `.claude/hooks/` folder and `.claude/settings.json` from your project:

```
rm -rf .claude/hooks .claude/settings.json
```

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- `jq` (install with `brew install jq`)
- `dart` (for the auto-format hook — if not installed, that hook just skips silently)
