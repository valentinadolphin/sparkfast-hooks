#!/bin/bash
# ============================================================
# Claude Code Hooks Installer
# ============================================================
# Run this from the root of any project to install Claude Code
# hooks that improve quality, safety, and session continuity.
#
# Usage:
#   bash install.sh
#
# What it installs:
#   1. format-dart.sh      — Auto-formats Dart files after edits
#   2. check-file-size.sh  — Warns when files exceed 500 lines
#   3. protect-files.sh    — Blocks staging of secrets (.env, keys, etc.)
#   4. context-monitor.sh  — Warns when context window is filling up
#   5. pre-compact.sh      — Saves state before auto-compaction
#   6. post-compact-restore.sh — Restores state after compaction
#
# Safe to re-run — overwrites existing hooks with latest version.
# ============================================================

set -euo pipefail

PROJECT_DIR="$(pwd)"
HOOKS_DIR="$PROJECT_DIR/.claude/hooks"
SETTINGS_FILE="$PROJECT_DIR/.claude/settings.json"

echo ""
echo "============================================"
echo "  Claude Code Hooks Installer"
echo "============================================"
echo ""
echo "Installing to: $PROJECT_DIR/.claude/"
echo ""

# Check for jq (required by hooks at runtime)
if ! command -v jq &>/dev/null; then
  echo "WARNING: 'jq' is not installed. Hooks need it at runtime."
  echo "  Install with: brew install jq"
  echo ""
fi

# Create hooks directory
mkdir -p "$HOOKS_DIR"

# ----- Hook 1: format-dart.sh -----
cat > "$HOOKS_DIR/format-dart.sh" << 'HOOKEOF'
#!/bin/bash
# Auto-format Dart files after Claude edits/writes them.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only format .dart files
if [[ "$FILE_PATH" != *.dart ]]; then
  exit 0
fi

# Only format if file exists (Write might have been to a new path)
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

dart format "$FILE_PATH" > /dev/null 2>&1
exit 0
HOOKEOF

# ----- Hook 2: check-file-size.sh -----
cat > "$HOOKS_DIR/check-file-size.sh" << 'HOOKEOF'
#!/bin/bash
# Warns Claude when an edited file exceeds 500 lines,
# so files can be split proactively during the session.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

LINES=$(wc -l < "$FILE_PATH" | tr -d ' ')

if [ "$LINES" -gt 500 ]; then
  BASENAME=$(basename "$FILE_PATH")
  echo "WARNING: $BASENAME is now $LINES lines. Consider splitting it into smaller files to keep the codebase maintainable." >&2
fi

exit 0
HOOKEOF

# ----- Hook 3: protect-files.sh -----
cat > "$HOOKS_DIR/protect-files.sh" << 'HOOKEOF'
#!/bin/bash
# Block Claude from staging sensitive files via git add.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check git add commands
if ! echo "$COMMAND" | grep -qE 'git\s+add'; then
  exit 0
fi

# Protected file patterns
PROTECTED=(
  ".env"
  "google-services.json"
  "GoogleService-Info.plist"
  ".jks"
  ".keystore"
  ".p8"
  ".p12"
  "credentials.json"
  "service-account"
)

for pattern in "${PROTECTED[@]}"; do
  if echo "$COMMAND" | grep -qi "$pattern"; then
    echo "BLOCKED: Command would stage a sensitive file matching '$pattern'." >&2
    echo "These files should stay in .gitignore, not in version control." >&2
    exit 2
  fi
done

exit 0
HOOKEOF

# ----- Hook 4: context-monitor.sh -----
cat > "$HOOKS_DIR/context-monitor.sh" << 'HOOKEOF'
#!/bin/bash
# Monitors context window usage and warns before auto-compaction hits.
# Warns at ~80%, alerts at ~90%.
# Non-blocking — only advises, never blocks.

INPUT=$(cat)
TOKENS_USED=$(echo "$INPUT" | jq -r '.context_tokens_used // 0')

if [ "$TOKENS_USED" -eq 0 ] 2>/dev/null; then
  exit 0
fi

# Claude's context window is 200k tokens.
# Auto-compaction fires at (200k - 33k buffer) = ~167k tokens.
COMPACTION_THRESHOLD=167000

PCT=$(( TOKENS_USED * 100 / COMPACTION_THRESHOLD ))

if [ "$PCT" -ge 90 ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[context] Usage at ~'"$PCT"'% — Wrap up your current task. Auto-compaction will trigger soon."}}'
elif [ "$PCT" -ge 80 ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[context] Usage at ~'"$PCT"'% — Consider finishing the current task before context runs low."}}'
fi

exit 0
HOOKEOF

# ----- Hook 5: pre-compact.sh -----
cat > "$HOOKS_DIR/pre-compact.sh" << 'HOOKEOF'
#!/bin/bash
# Saves session state before auto-compaction so it can be restored after.
# Captures: working directory, session ID, and timestamp.

STATE_DIR="$HOME/.claude/devflow/state/${CLAUDE_SESSION_ID:-default}"
mkdir -p "$STATE_DIR"

STATE_FILE="$STATE_DIR/pre-compact.json"

CWD=$(pwd)
SESSION_ID="${CLAUDE_SESSION_ID:-default}"

cat > "$STATE_FILE" << JSONEOF
{
  "session_id": "$SESSION_ID",
  "cwd": "$CWD",
  "timestamp": $(date +%s)
}
JSONEOF

echo "[pre-compact] State saved before compaction" >&2
exit 0
HOOKEOF

# ----- Hook 6: post-compact-restore.sh -----
cat > "$HOOKS_DIR/post-compact-restore.sh" << 'HOOKEOF'
#!/bin/bash
# Restores session state after auto-compaction.
# Reads state saved by pre-compact.sh and injects it into context
# so Claude knows what it was working on.

STATE_DIR="$HOME/.claude/devflow/state/${CLAUDE_SESSION_ID:-default}"
STATE_FILE="$STATE_DIR/pre-compact.json"

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

CWD=$(jq -r '.cwd // empty' "$STATE_FILE" 2>/dev/null)

LINES="[Context Restored After Compaction]"

if [ -n "$CWD" ]; then
  LINES="$LINES
Working directory: $CWD"
fi

LINES="$LINES
Check MEMORY.md and CLAUDE.md for project context.
Resume from where you left off."

# Clean up state file after restoring
rm -f "$STATE_FILE"

echo "$LINES"
exit 0
HOOKEOF

# Make all hooks executable
chmod +x "$HOOKS_DIR"/*.sh
echo "Created 6 hooks in .claude/hooks/"

# ----- Write settings.json -----
if [ -f "$SETTINGS_FILE" ]; then
  if jq -e '.hooks' "$SETTINGS_FILE" >/dev/null 2>&1; then
    echo ""
    echo "WARNING: $SETTINGS_FILE already exists with hooks configured."
    echo "Backing up to .claude/settings.json.backup"
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"
  fi
fi

cat > "$SETTINGS_FILE" << 'SETTINGSEOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-compact-restore.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/format-dart.sh",
            "timeout": 30
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-file-size.sh",
            "timeout": 10
          }
        ]
      },
      {
        "matcher": "Read|Write|Edit|Bash|Glob|Grep",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/context-monitor.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-compact.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
SETTINGSEOF

echo "Created .claude/settings.json"

echo ""
echo "============================================"
echo "  Done! 6 hooks installed."
echo "============================================"
echo ""
echo "  What's active:"
echo "  - Auto-format Dart files on edit"
echo "  - File size warning (>500 lines)"
echo "  - Secret file staging protection"
echo "  - Context window usage monitor"
echo "  - Session state preservation on compaction"
echo ""
echo "  Start a new Claude Code session to activate."
echo "============================================"
echo ""
