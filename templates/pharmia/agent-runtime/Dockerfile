# Pharmia agent runtime — the deterministic image Daytona uses as its snapshot.
# Bakes: toolchain + the Bento CLI toolkit (SSOT) + the coding agents. Credentials
# are NOT baked — they are injected at runtime (env today, Vaultwarden later),
# dev/qa read-write + prod read-only + comp read-write (see README.md "Access set").
#
# Build (context = templates/pharmia so the CLI toolkit is in scope):
#   docker build -f templates/pharmia/agent-runtime/Dockerfile -t pharmia-agent-runtime templates/pharmia
FROM node:22-bookworm-slim

# System deps the CLI toolkit + the Pharmia dev loop need (clone/typecheck/test/push).
# No docker-in-docker: the agent ships to the dev env via push, it doesn't run the
# full stack locally — add it later only if an agent needs `docker:dev` in-sandbox.
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash curl jq git openssh-client postgresql-client ca-certificates \
      python3 python3-pip ripgrep less \
    && rm -rf /var/lib/apt/lists/*

# Coding agents. API-key auth at runtime (ANTHROPIC_API_KEY / codex key) — never an
# interactive login, so the image is reproducible. Pin exact versions when we lock it.
RUN npm install -g @anthropic-ai/claude-code @openai/codex

# The Bento/Pharmia CLI toolkit (source of truth = this repo's templates/pharmia/cli).
COPY cli /opt/bento-cli
RUN CLI_INSTALL_DIR=/usr/local/bin sh /opt/bento-cli/install.sh

# Non-root agent user; work happens under /home/agent (per-issue worktree at runtime).
RUN useradd -m -s /bin/bash agent
USER agent
WORKDIR /home/agent

# Injected at runtime by Daytona/Paperclip (NOT baked):
#   GITHUB_APP_* (or a git token), ANTHROPIC_API_KEY,
#   LOKI_{DEV,QA,CANARY}_TOKEN, PG_{DEV,QA}_* (rw) + PG_CANARY_* (READ-ONLY role),
#   ~/.config/<tool>/ for ol, langfuse, twenty, comp (read-write), dokploy (bento dev/qa only).
# Workflow: clone PharmaMate → `npm install` (arms the .husky CONFIRM hook) → per-issue
# worktree → push dev/qa freely; main/canary blocked by the hook (agents never set CONFIRM_DEPLOY).
CMD ["bash"]
