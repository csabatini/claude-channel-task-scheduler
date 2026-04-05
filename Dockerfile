# syntax=docker/dockerfile:1
FROM alpine:latest

ARG USERNAME
ARG UID
ARG GID

# System packages (root)
RUN apk add --no-cache python3 py3-pip git gcc musl-dev python3-dev curl bash ripgrep jq
RUN pip3 install --no-cache --upgrade --break-system-packages pip setuptools

# Non-root user whose home matches the host path used by the bind mounts
RUN addgroup -g ${GID} ${USERNAME} \
 && adduser -D -u ${UID} -G ${USERNAME} -h /home/${USERNAME} ${USERNAME}

RUN mkdir /app && chown ${UID}:${GID} /app

# Staging directory for build-time plugin/MCP install. Lives outside any
# bind mount so image-baked artifacts survive at runtime. Owned by the
# runtime user so the install step (run as that user) can write here.
RUN mkdir -p /opt/claude-template/.claude && chown -R ${UID}:${GID} /opt/claude-template

COPY --chmod=755 scripts/claude-bootstrap.sh /usr/local/bin/claude-bootstrap.sh

USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV PATH="/home/${USERNAME}/.bun/bin:/home/${USERNAME}/.local/bin:${PATH}"
ENV USE_BUILTIN_RIPGREP=0

# Install uv and Claude Code as the runtime user — lands in ~/.local
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install Bun (required runtime for the Telegram plugin) — lands in ~/.bun
RUN curl -fsSL https://bun.sh/install | bash

# Install the Telegram plugin and Yahoo Finance MCP into the staging
# directory, using host credentials exposed via a BuildKit secret mount.
# The credential copy inside the staging dir is scrubbed before the layer
# commits, so no host credentials end up in any image layer. Runtime
# credentials still come from the host bind mount at $HOME/.claude/.credentials.json.
RUN --mount=type=secret,id=claude_creds,uid=${UID},gid=${GID},mode=0400 \
    export HOME=/opt/claude-template && \
    mkdir -p "$HOME/.claude" && \
    cp /run/secrets/claude_creds "$HOME/.claude/.credentials.json" && \
    chmod 600 "$HOME/.claude/.credentials.json" && \
    claude plugin marketplace add anthropics/claude-plugins-official && \
    claude plugin install telegram@claude-plugins-official --scope user && \
    claude mcp add --scope user yahoo-finance -- uvx --from git+https://github.com/Alex2Yang97/yahoo-finance-mcp yahoo-finance-mcp && \
    rm -f "$HOME/.claude/.credentials.json"

WORKDIR /app

ENTRYPOINT ["/usr/local/bin/claude-bootstrap.sh"]
CMD ["claude", "--dangerously-skip-permissions", "--channels", "plugin:telegram@claude-plugins-official"]
