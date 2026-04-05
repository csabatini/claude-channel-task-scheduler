#!/bin/sh
set -eu

TEMPLATE_CLAUDE_DIR=/opt/claude-template/.claude
TEMPLATE_CLAUDE_JSON=/opt/claude-template/.claude.json
TARGET_CLAUDE_DIR="$HOME/.claude"
TARGET_CLAUDE_JSON="$HOME/.claude.json"

merge_json_host_wins() {
    # $1 = host file, $2 = template file
    # Deep merge, host keys take precedence.
    # Write in place via `cat >`, not `mv`, because the host file may be a
    # single-file bind mount — rename(2) against those fails with EBUSY.
    tmp=$(mktemp)
    if jq -s '.[1] * .[0]' "$1" "$2" > "$tmp"; then
        cat "$tmp" > "$1"
        rm -f "$tmp"
    else
        rm -f "$tmp"
        echo "claude-bootstrap: failed to merge $1 with $2" >&2
        return 1
    fi
}

# --- Plugins ---------------------------------------------------------------
if [ -d "$TEMPLATE_CLAUDE_DIR/plugins" ]; then
    mkdir -p "$TARGET_CLAUDE_DIR/plugins"

    # Copy plugin subdirectories if missing on the host.
    for src in "$TEMPLATE_CLAUDE_DIR/plugins"/*; do
        [ -e "$src" ] || continue
        [ -d "$src" ] || continue
        name=$(basename "$src")
        dest="$TARGET_CLAUDE_DIR/plugins/$name"
        if [ ! -e "$dest" ]; then
            cp -a "$src" "$dest"
        fi
    done

    # Merge index files (installed_plugins.json, known_marketplaces.json).
    for idx in installed_plugins.json known_marketplaces.json; do
        t="$TEMPLATE_CLAUDE_DIR/plugins/$idx"
        h="$TARGET_CLAUDE_DIR/plugins/$idx"
        [ -f "$t" ] || continue
        if [ -f "$h" ]; then
            merge_json_host_wins "$h" "$t"
        else
            cp "$t" "$h"
        fi
    done
fi

# --- MCP servers (merged into $HOME/.claude.json) -------------------------
if [ -f "$TEMPLATE_CLAUDE_JSON" ]; then
    if [ -f "$TARGET_CLAUDE_JSON" ]; then
        tmp=$(mktemp)
        # Preserve all host top-level keys; for mcpServers specifically,
        # overlay template then host so host entries win but template
        # entries fill gaps.
        if jq -s '
            .[0] * {
                mcpServers: (((.[1].mcpServers // {}) * (.[0].mcpServers // {})))
            }
        ' "$TARGET_CLAUDE_JSON" "$TEMPLATE_CLAUDE_JSON" > "$tmp"; then
            # Write in place; $TARGET_CLAUDE_JSON is a single-file bind mount
            # and `mv` would fail with EBUSY.
            cat "$tmp" > "$TARGET_CLAUDE_JSON"
            rm -f "$tmp"
        else
            rm -f "$tmp"
            echo "claude-bootstrap: failed to merge mcpServers into $TARGET_CLAUDE_JSON" >&2
            exit 1
        fi
    else
        cp "$TEMPLATE_CLAUDE_JSON" "$TARGET_CLAUDE_JSON"
    fi
fi

# --- Workspace trust ------------------------------------------------------
# Claude shows an interactive trust dialog for the working directory on every
# new session. The trust state lives in $HOME/.claude.json under
# projects.<cwd>.hasTrustDialogAccepted. Pre-accept it so the headless
# container session starts without blocking on a prompt.
if [ -f "$TARGET_CLAUDE_JSON" ] && command -v jq >/dev/null 2>&1; then
    cwd="$(pwd)"
    accepted=$(jq -r --arg p "$cwd" '.projects[$p].hasTrustDialogAccepted // false' "$TARGET_CLAUDE_JSON" 2>/dev/null)
    if [ "$accepted" != "true" ]; then
        tmp=$(mktemp)
        if jq --arg p "$cwd" '.projects[$p].hasTrustDialogAccepted = true' "$TARGET_CLAUDE_JSON" > "$tmp"; then
            cat "$tmp" > "$TARGET_CLAUDE_JSON"
            rm -f "$tmp"
        else
            rm -f "$tmp"
        fi
    fi
fi

# --- Telegram plugin dependencies -----------------------------------------
# The plugin's start script runs `bun install` before `bun server.ts`. On a
# cold start that means downloading npm deps, which takes long enough that
# Claude's MCP health check times out. Pre-installing here so the plugin
# starts instantly when Claude spawns it.
tg_plugin="$TARGET_CLAUDE_DIR/plugins/marketplaces/claude-plugins-official/external_plugins/telegram"
if [ -d "$tg_plugin" ] && command -v bun >/dev/null 2>&1; then
    bun install --cwd "$tg_plugin" --no-summary || true
fi

# --- Telegram plugin token ------------------------------------------------
# The plugin reads its config from $HOME/.claude/channels/telegram/.env.
# We rewrite this file on every start when TELEGRAM_BOT_TOKEN is set so the
# single source of truth for the token is the repo's .env (passed through
# docker-compose), and rotation is just `edit .env && compose up --force-recreate`.
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    tg_dir="$HOME/.claude/channels/telegram"
    tg_env="$tg_dir/.env"
    mkdir -p "$tg_dir"
    umask 077
    printf 'TELEGRAM_BOT_TOKEN=%s\n' "$TELEGRAM_BOT_TOKEN" > "$tg_env"
    chmod 600 "$tg_env"
fi

exec "$@"
