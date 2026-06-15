# syntax=docker/dockerfile:1.20
FROM node:lts-trixie-slim AS base
ARG USER_UID=1000
ARG USER_GID=1000
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates gosu curl gh git wget ripgrep python3 \
  && rm -rf /var/lib/apt/lists/* \
  && corepack enable

# Modify the existing node user/group to have the specified UID/GID to match host user
RUN usermod -u $USER_UID --non-unique node \
  && groupmod -g $USER_GID --non-unique node \
  && usermod -g $USER_GID -d /paperclip node

FROM base AS deps
WORKDIR /app
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml .npmrc ./
COPY cli/package.json cli/
COPY server/package.json server/
COPY ui/package.json ui/
COPY packages/shared/package.json packages/shared/
COPY packages/db/package.json packages/db/
COPY packages/adapter-utils/package.json packages/adapter-utils/
COPY packages/mcp-server/package.json packages/mcp-server/
COPY packages/skills-catalog/package.json packages/skills-catalog/
COPY packages/teams-catalog/package.json packages/teams-catalog/
COPY packages/adapters/acpx-local/package.json packages/adapters/acpx-local/
COPY packages/adapters/claude-local/package.json packages/adapters/claude-local/
COPY packages/adapters/codex-local/package.json packages/adapters/codex-local/
COPY packages/adapters/cursor-cloud/package.json packages/adapters/cursor-cloud/
COPY packages/adapters/cursor-local/package.json packages/adapters/cursor-local/
COPY packages/adapters/gemini-local/package.json packages/adapters/gemini-local/
COPY packages/adapters/grok-local/package.json packages/adapters/grok-local/
COPY packages/adapters/openclaw-gateway/package.json packages/adapters/openclaw-gateway/
COPY packages/adapters/opencode-local/package.json packages/adapters/opencode-local/
COPY packages/adapters/pi-local/package.json packages/adapters/pi-local/
COPY packages/plugins/sdk/package.json packages/plugins/sdk/
COPY --parents packages/plugins/sandbox-providers/./*/package.json packages/plugins/sandbox-providers/
COPY packages/plugins/paperclip-plugin-fake-sandbox/package.json packages/plugins/paperclip-plugin-fake-sandbox/
COPY packages/plugins/plugin-llm-wiki/package.json packages/plugins/plugin-llm-wiki/
COPY packages/plugins/plugin-workspace-diff/package.json packages/plugins/plugin-workspace-diff/
COPY packages/plugins/plugin-chat/package.json packages/plugins/plugin-chat/
COPY packages/plugins/plugin-email-responder/package.json packages/plugins/plugin-email-responder/
COPY patches/ patches/
COPY scripts/link-plugin-dev-sdk.mjs scripts/

RUN pnpm install --frozen-lockfile

FROM base AS build
ARG VITE_POCKET_ID_ENABLED=false
ARG VITE_DISABLE_SIGNUP=false
ENV VITE_POCKET_ID_ENABLED=${VITE_POCKET_ID_ENABLED}
ENV VITE_DISABLE_SIGNUP=${VITE_DISABLE_SIGNUP}
WORKDIR /app
COPY --from=deps /app /app
COPY . .
RUN pnpm --filter @paperclipai/ui build
RUN pnpm --filter @paperclipai/plugin-sdk build
# Bundled in-repo plugins: build their dist/ so the running server can install
# them from /app/packages/plugins/<name> via a local-path install. Depends on
# the plugin-sdk build above.
RUN pnpm --filter @paperclipai/plugin-llm-wiki build
RUN pnpm --filter @paperclipai/plugin-workspace-diff build
RUN pnpm --filter @paperclipai/plugin-chat build
RUN pnpm --filter @paperclipai/plugin-email-responder build
# Daytona sandbox-provider plugin: excluded from the pnpm workspace (see
# pnpm-workspace.yaml "!packages/plugins/sandbox-providers/**") so it is NOT
# installed/built by the frozen workspace install above. Install its standalone
# third-party deps (@daytonaio/sdk) into its own node_modules — the postinstall
# (link-plugin-dev-sdk.mjs) symlinks the workspace @paperclipai/plugin-sdk built
# just above — then compile its dist/. Baking dist + node_modules into the image
# makes activation survive container restarts/redeploys (previously the dist was
# hand-built inside the running container and wiped on recreate).
RUN cd packages/plugins/sandbox-providers/daytona \
  && pnpm install --ignore-workspace \
  && pnpm run build \
  && test -f dist/manifest.js || (echo "ERROR: daytona plugin manifest build output missing" && exit 1)
RUN pnpm --filter @paperclipai/server build
RUN test -f server/dist/index.js || (echo "ERROR: server build output missing" && exit 1)

FROM base AS production
ARG USER_UID=1000
ARG USER_GID=1000
WORKDIR /app
COPY --chown=node:node --from=build /app /app

# Install apt deps + npm globals + logcli (Loki query CLI used by the `loki` wrapper)
RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest @openai/codex@latest opencode-ai langfuse-cli \
  && apt-get update \
  && apt-get install -y --no-install-recommends openssh-client jq \
  && LOGCLI_VERSION="3.7.2" \
  && curl -fsSL "https://github.com/grafana/loki/releases/download/v${LOGCLI_VERSION}/logcli_${LOGCLI_VERSION}_amd64.deb" \
       -o /tmp/logcli.deb \
  && dpkg -i /tmp/logcli.deb \
  && rm /tmp/logcli.deb \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /paperclip \
  && chown node:node /paperclip

# Copy Pharmia HTTP-API CLIs into the image
COPY tools/clis/ /usr/local/bin/
RUN chmod +x /usr/local/bin/loki \
              /usr/local/bin/tempo \
              /usr/local/bin/prom \
              /usr/local/bin/langfuse \
              /usr/local/bin/autumn \
              /usr/local/bin/cfdns \
              /usr/local/bin/ol \
              /usr/local/bin/shlink \
              /usr/local/bin/git-credential-github-app

# Configure git to use the GitHub App credential helper for github.com clones.
# Use --system so the config lands in /etc/gitconfig and applies to all users
# regardless of HOME (the node user runs with HOME=/paperclip which is a volume).
RUN git config --system credential.https://github.com.helper /usr/local/bin/git-credential-github-app

COPY scripts/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV NODE_ENV=production \
  HOME=/paperclip \
  HOST=0.0.0.0 \
  PORT=3100 \
  SERVE_UI=true \
  PAPERCLIP_HOME=/paperclip \
  PAPERCLIP_INSTANCE_ID=default \
  USER_UID=${USER_UID} \
  USER_GID=${USER_GID} \
  PAPERCLIP_CONFIG=/paperclip/instances/default/config.json \
  PAPERCLIP_DEPLOYMENT_MODE=authenticated \
  PAPERCLIP_DEPLOYMENT_EXPOSURE=private \
  OPENCODE_ALLOW_ALL_MODELS=true

VOLUME ["/paperclip"]
EXPOSE 3100

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "--import", "./server/node_modules/tsx/dist/loader.mjs", "server/dist/index.js"]
