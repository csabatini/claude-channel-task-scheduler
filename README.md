# claude-channel-task-scheduler

Containerized app that uses an interactive Claude Code channel plugin (Telegram) with an MCP server and scheduled tasks.

## How It Works

The container runs an active Claude Code session with the Telegram channel plugin configured, and support for scheduled tasks and MCP server(s). All output from both scheduled tasks and interactive channel input then flows back out to Telegram.

## Prerequisites

1. **Claude Code** authentication should be present on the container host (`~/.claude` and `~/.claude.json` must exist).
2. **Telegram bot token** from [@BotFather](https://t.me/BotFather). Copy `.env.example` to `.env` and fill in `TELEGRAM_BOT_TOKEN`.
3. **Docker** with Compose v2 and BuildKit (default on modern Docker).

## Usage

```
# Build the image
docker compose build

# Start the container 
# This runs Claude with Telegram channel plugin installed and Telegram bot token passed through
docker compose up -d
```

### Attaching to Claude Code session in running container

The container's main process is an interactive Claude Code session. After messaging the bot on Telegram for the first time, confirm the pair request in Claude Code.

```
# Attach to the running container session
docker compose attach cc-task-scheduler

# Confirm the pair request from Telegram in Claude Code - one time setup
/telegram:access pair <code>
```

**Important:** to detach without killing the session, press `Ctrl-P` then `Ctrl-Q`. Using `Ctrl-C` will send SIGINT and terminate the active Claude session.

### Scheduling Tasks in the Claude Code session

```
# Attach to the running container session 
docker compose attach cc-task-scheduler

# Schedule a task to be messaged over the Telegram channel
/schedule create \
  --cron "0 16 * * 1-5" \
  --prompt "Send an end-of-day market recap for NVDA, SPY, AAPL to Telegram."
```

## Architecture

![Architecture](architecture.svg)
