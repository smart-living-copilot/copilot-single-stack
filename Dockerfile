FROM node:25-trixie-slim AS chat-ui-build
WORKDIR /app
COPY upstream/copilot/chat-ui/package.json upstream/copilot/chat-ui/package-lock.json ./
RUN npm ci
COPY upstream/copilot/chat-ui/src ./src
COPY upstream/copilot/chat-ui/public ./public
COPY upstream/copilot/chat-ui/scripts ./scripts
COPY upstream/copilot/chat-ui/next.config.ts ./next.config.ts
COPY upstream/copilot/chat-ui/postcss.config.mjs ./postcss.config.mjs
COPY upstream/copilot/chat-ui/tsconfig.json ./tsconfig.json
COPY upstream/copilot/chat-ui/components.json ./components.json
ENV NEXT_TELEMETRY_DISABLED=1
RUN mkdir -p /app/data && npm run build

FROM node:25-trixie-slim AS chat-ui-runtime-deps
WORKDIR /app
COPY upstream/copilot/chat-ui/package.json upstream/copilot/chat-ui/package-lock.json ./
RUN npm ci --omit=dev

FROM node:22-bookworm AS wot-runtime-build
WORKDIR /app
COPY upstream/wot-registry/wot_runtime/package.json upstream/wot-registry/wot_runtime/package-lock.json ./
RUN npm ci
COPY upstream/wot-registry/wot_runtime/src ./src
COPY upstream/wot-registry/wot_runtime/tsconfig.json ./tsconfig.json
RUN npm run build

FROM python:3.12-slim AS production

ARG APP_UID=10001
ARG APP_GID=10001

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    valkey-server \
    && groupadd --system --gid "${APP_GID}" app \
    && useradd --system --uid "${APP_UID}" --gid "${APP_GID}" --create-home --home-dir /home/app app \
    && mkdir -p \
    /data/chat-ui \
    /data/copilot \
    /data/registry/search-index \
    /data/valkey \
    /tmp/code-executor-artifacts \
    && chown -R app:app /data /home/app /tmp/code-executor-artifacts \
    && rm -rf /var/lib/apt/lists/*

ARG S6_OVERLAY_VERSION=3.2.0.2
ARG TARGETARCH

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp/s6-overlay-noarch.tar.xz
RUN python3 -c "import tarfile; tarfile.open('/tmp/s6-overlay-noarch.tar.xz', 'r:xz').extractall('/')" \
    && rm /tmp/s6-overlay-noarch.tar.xz

RUN python3 -c "import os, urllib.request; arch = {'amd64': 'x86_64', 'arm64': 'aarch64'}.get(os.environ.get('TARGETARCH', ''), 'x86_64'); version = os.environ['S6_OVERLAY_VERSION']; url = f'https://github.com/just-containers/s6-overlay/releases/download/v{version}/s6-overlay-{arch}.tar.xz'; urllib.request.urlretrieve(url, '/tmp/s6-overlay-arch.tar.xz')" \
    && python3 -c "import tarfile; tarfile.open('/tmp/s6-overlay-arch.tar.xz', 'r:xz').extractall('/')" \
    && rm /tmp/s6-overlay-arch.tar.xz

WORKDIR /app

COPY --from=chat-ui-build /usr/local/bin/node /usr/local/bin/node
COPY --from=wot-runtime-build /usr/local/bin/node /usr/local/bin/node-wot-runtime
COPY --from=chat-ui-runtime-deps /app/node_modules /app/chat-ui/node_modules
COPY --from=chat-ui-build /app/.next /app/chat-ui/.next
COPY --from=chat-ui-build /app/public /app/chat-ui/public
COPY --from=chat-ui-build /app/scripts /app/chat-ui/scripts
COPY --from=chat-ui-build /app/next.config.ts /app/chat-ui/next.config.ts
COPY --from=chat-ui-build /app/package.json /app/chat-ui/package.json
COPY --from=chat-ui-build /app/package-lock.json /app/chat-ui/package-lock.json

COPY --from=wot-runtime-build /app/node_modules /app/wot-registry/wot_runtime/node_modules
COPY --from=wot-runtime-build /app/dist /app/wot-registry/wot_runtime/dist
COPY --from=wot-runtime-build /app/package.json /app/wot-registry/wot_runtime/package.json
COPY --from=wot-runtime-build /app/package-lock.json /app/wot-registry/wot_runtime/package-lock.json

COPY upstream/wot-registry/backend /app/wot-registry/backend
COPY upstream/copilot/copilot /app/copilot
COPY upstream/copilot/code-executor /app/code-executor

RUN python3 -m venv /opt/wot-registry-venv \
    && /opt/wot-registry-venv/bin/pip install --no-cache-dir /app/wot-registry/backend \
    && python3 -m venv /opt/copilot-venv \
    && /opt/copilot-venv/bin/pip install --no-cache-dir /app/copilot \
    && python3 -m venv /opt/code-executor-venv \
    && /opt/code-executor-venv/bin/pip install --no-cache-dir /app/code-executor

COPY rootfs/ /
RUN chmod +x /etc/cont-init.d/* \
    && chmod +x /usr/local/bin/wait-for-http \
    && chmod +x /etc/s6-overlay/s6-rc.d/*/run

ENV DATABASE_PATH=/data/chat-ui/sqlite.db \
    REGISTRY_DATABASE_URL=sqlite:////data/registry/wot_registry.db \
    REGISTRY_PUBLIC_URL=http://localhost:8000 \
    REDIS_URL=redis://127.0.0.1:6379 \
    WOT_RUNTIME_STREAM=wot_runtime_events \
    AGENT_STATE_DB_PATH=/data/copilot/agent_state.db \
    HOME=/home/app \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    NEXT_TELEMETRY_DISABLED=1

VOLUME ["/data"]

EXPOSE 3000

USER app:app

ENTRYPOINT ["/init"]
