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
#   1.  dart-fix.sh             — Auto-applies dart fixes after edits
#   2.  format-dart.sh          — Auto-formats Dart files after edits
#   3.  print-catcher.sh        — Catches print() and suggests SecureLogger
#   4.  check-file-size.sh      — Warns when files exceed 500 lines
#   5.  test-reminder.sh        — Reminds to write tests for business logic
#   6.  pubspec-alert.sh        — Dependency update protocol reminder
#   7.  protect-files.sh        — Blocks staging of secrets (.env, keys, etc.)
#   8.  pre-push-gate.sh        — Runs flutter analyze before git push
#   9.  context-monitor.sh      — Warns when context window is filling up
#   10. pre-compact.sh          — Saves state before auto-compaction
#   11. post-compact-restore.sh — Restores state after compaction
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

# ----- Hook 1: dart-fix.sh -----
cat > "$HOOKS_DIR/dart-fix.sh" << 'HOOKEOF'
#!/bin/bash
# Runs `dart fix --apply` on Dart files after edits to auto-clean
# unused imports and deprecated APIs. Runs BEFORE format-dart.sh.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only fix .dart files
if [[ "$FILE_PATH" != *.dart ]]; then
  exit 0
fi

# Skip generated files
if [[ "$FILE_PATH" == *.g.dart ]] || [[ "$FILE_PATH" == *.freezed.dart ]]; then
  exit 0
fi

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

dart fix --apply "$FILE_PATH" > /dev/null 2>&1
exit 0
HOOKEOF

# ----- Hook 2: format-dart.sh -----
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

# ----- Hook 3: print-catcher.sh -----
cat > "$HOOKS_DIR/print-catcher.sh" << 'HOOKEOF'
#!/bin/bash
# Catches print() statements in Dart files immediately after edit.
# Warns Claude to use SecureLogger instead.
# Skips test files (print in tests is fine).

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check .dart files
if [[ "$FILE_PATH" != *.dart ]]; then
  exit 0
fi

# Skip test files — print() is fine in tests
if [[ "$FILE_PATH" == *_test.dart ]] || [[ "$FILE_PATH" == */test/* ]]; then
  exit 0
fi

# Skip generated files
if [[ "$FILE_PATH" == *.g.dart ]] || [[ "$FILE_PATH" == *.freezed.dart ]]; then
  exit 0
fi

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# Look for print( but filter out false positives:
# fingerprint, blueprint, debugPrint, printError (Flutter), Sprint, etc.
MATCHES=$(grep -n 'print(' "$FILE_PATH" | grep -vE '(fingerprint|blueprint|footprint|debugPrint|printError|Sprint|\/\/.*print\()')

if [ -n "$MATCHES" ]; then
  BASENAME=$(basename "$FILE_PATH")
  echo "WARNING: Found print() in $BASENAME. Use SecureLogger instead (.debug(), .info(), .warning(), .error()). Lines:" >&2
  echo "$MATCHES" >&2
fi

exit 0
HOOKEOF

# ----- Hook 4: check-file-size.sh -----
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

# ----- Hook 5: test-reminder.sh -----
cat > "$HOOKS_DIR/test-reminder.sh" << 'HOOKEOF'
#!/bin/bash
# Reminds Claude to write tests when editing business logic files.
# Checks lib/services/, lib/providers/, lib/repositories/, lib/models/
# and looks for a corresponding test file.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check .dart files
if [[ "$FILE_PATH" != *.dart ]]; then
  exit 0
fi

# Skip test files, generated files, main.dart
if [[ "$FILE_PATH" == *_test.dart ]] || [[ "$FILE_PATH" == */test/* ]]; then
  exit 0
fi
if [[ "$FILE_PATH" == *.g.dart ]] || [[ "$FILE_PATH" == *.freezed.dart ]]; then
  exit 0
fi
if [[ "$(basename "$FILE_PATH")" == "main.dart" ]]; then
  exit 0
fi

# Only check files in testable directories
TESTABLE_DIRS="lib/services/ lib/providers/ lib/repositories/ lib/models/"
IS_TESTABLE=false
for dir in $TESTABLE_DIRS; do
  if [[ "$FILE_PATH" == *"$dir"* ]]; then
    IS_TESTABLE=true
    break
  fi
done

if [ "$IS_TESTABLE" = false ]; then
  exit 0
fi

# Derive expected test file path: lib/X/foo.dart → test/X/foo_test.dart
TEST_PATH=$(echo "$FILE_PATH" | sed 's|lib/|test/|' | sed 's|\.dart$|_test.dart|')

if [[ ! -f "$TEST_PATH" ]]; then
  BASENAME=$(basename "$FILE_PATH")
  EXPECTED=$(basename "$TEST_PATH")
  echo "REMINDER: No test file found for $BASENAME. Expected: $TEST_PATH — consider creating $EXPECTED to cover this code." >&2
fi

exit 0
HOOKEOF

# ----- Hook 6: pubspec-alert.sh -----
cat > "$HOOKS_DIR/pubspec-alert.sh" << 'HOOKEOF'
#!/bin/bash
# Reminds Claude of the dependency update protocol when pubspec.yaml is edited.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only trigger for pubspec.yaml
if [[ "$(basename "$FILE_PATH")" != "pubspec.yaml" ]]; then
  exit 0
fi

cat >&2 << 'MSG'
REMINDER — Dependency Update Protocol:
  1. Check changelogs on pub.dev before upgrading
  2. Apply patches first, then minor, then major (one at a time)
  3. Firebase packages must be upgraded together as a group
  4. Run flutter analyze and tests after changes
  5. Commit pubspec.lock alongside pubspec.yaml
  6. Flag any new permissions or breaking changes
MSG

exit 0
HOOKEOF

# ----- Hook 7: protect-files.sh -----
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

# ----- Hook 8: pre-push-gate.sh -----
cat > "$HOOKS_DIR/pre-push-gate.sh" << 'HOOKEOF'
#!/bin/bash
# Intercepts git push commands and runs flutter analyze first.
# Blocks the push if analyze finds issues — last safety net before GitHub.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept git push commands
if ! echo "$COMMAND" | grep -qE 'git\s+push'; then
  exit 0
fi

echo "Running flutter analyze before push..." >&2

ANALYZE_OUTPUT=$(flutter analyze 2>&1)
ANALYZE_EXIT=$?

if [ $ANALYZE_EXIT -ne 0 ]; then
  echo "BLOCKED: flutter analyze found issues. Fix them before pushing:" >&2
  echo "$ANALYZE_OUTPUT" | tail -20 >&2
  exit 2
fi

echo "flutter analyze passed — push allowed." >&2
exit 0
HOOKEOF

# ----- Hook 9: context-monitor.sh -----
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

# ----- Hook 10: pre-compact.sh -----
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

# ----- Hook 11: post-compact-restore.sh -----
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
echo "Created 11 hooks in .claude/hooks/"

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
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/dart-fix.sh",
            "timeout": 30
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/format-dart.sh",
            "timeout": 30
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/print-catcher.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-file-size.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/test-reminder.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pubspec-alert.sh",
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
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-push-gate.sh",
            "timeout": 120
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
echo "  Done! 11 hooks installed."
echo "============================================"
echo ""
echo "  What's active:"
echo "  - Auto-fix Dart code (unused imports, deprecated APIs)"
echo "  - Auto-format Dart files on edit"
echo "  - print() catcher (use SecureLogger instead)"
echo "  - File size warning (>500 lines)"
echo "  - Test reminder for business logic files"
echo "  - Dependency update protocol reminder"
echo "  - Secret file staging protection"
echo "  - Pre-push flutter analyze gate"
echo "  - Context window usage monitor"
echo "  - Session state preservation on compaction"
echo ""
echo "  Start a new Claude Code session to activate."
echo "============================================"
echo ""
