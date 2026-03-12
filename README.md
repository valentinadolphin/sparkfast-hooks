# sparkfast-hooks

11 hooks for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that improve code quality, safety, and session continuity. Works on any Flutter/Dart project.

## What do these hooks do?

### Code Quality (run on every edit)

| Hook | What it does |
|------|-------------|
| **Auto-fix** | Runs `dart fix --apply` to clean unused imports and deprecated APIs |
| **Auto-format** | Formats your Dart code with `dart format` after every edit |
| **print() catcher** | Catches `print()` statements and reminds Claude to use SecureLogger |
| **File size warning** | Warns Claude when a file gets too big (>500 lines) so it splits it |
| **Test reminder** | Checks if business logic files have a matching test file |
| **Dependency alert** | Reminds Claude of the dependency update protocol when editing pubspec.yaml |

### Safety (prevent mistakes)

| Hook | What it does |
|------|-------------|
| **Secret protection** | Blocks Claude from accidentally committing passwords, API keys, or secret files |
| **Pre-push gate** | Runs `flutter analyze` before every `git push` — blocks if there are issues |

### Session Continuity (survive context compaction)

| Hook | What it does |
|------|-------------|
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

You should see: **"Done! 11 hooks installed."**

### Step 4: Restart Claude Code

Close Claude Code and open it again. The hooks are now active.

## Hook Execution Order

When Claude edits or writes a file, hooks run in this order:

1. `dart-fix.sh` — clean up code
2. `format-dart.sh` — format after fixes
3. `print-catcher.sh` — check for print()
4. `check-file-size.sh` — warn if too large
5. `test-reminder.sh` — remind about tests
6. `pubspec-alert.sh` — dependency protocol

When Claude runs a bash command:

1. `protect-files.sh` — block secret staging
2. `pre-push-gate.sh` — analyze before push

## Uninstall

Delete the `.claude/hooks/` folder and `.claude/settings.json` from your project:

```
rm -rf .claude/hooks .claude/settings.json
```

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- `jq` (install with `brew install jq`)
- `dart` (for the auto-fix and auto-format hooks — if not installed, those hooks just skip silently)
- `flutter` (for the pre-push gate hook — if not installed, that hook just skips)
