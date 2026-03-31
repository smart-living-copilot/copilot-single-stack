# Copilot Single Stack

This repo builds the Smart Living Copilot all-in-one container from pinned
upstream source repos via Git submodules.

Included services:

- `chat-ui`
- `copilot`
- `code-executor`
- `wot-registry`
- `wot-runtime`
- `valkey`

## Upstreams

This repo tracks two upstream repos as submodules:

- `upstream/copilot`
- `upstream/wot-registry`

Clone with submodules:

```bash
git clone --recurse-submodules https://github.com/smart-living-copilot/copilot-single-stack.git
```

If you already cloned it:

```bash
git submodule update --init --recursive
```

## Build

From this repo root:

```bash
docker build -t copilot-single-stack .
```

## Run

The stack expects the same core environment values as the current compose
deployment. The registry also needs `OPENAI_API_KEY` because semantic search
indexing is enabled.

When you use `--env-file .env`, the stack automatically reuses
`INIT_ADMIN_TOKEN` as `WOT_REGISTRY_TOKEN` for the internal clients.

```bash
docker run --rm -p 3000:3000 \
  --env-file .env \
  -v copilot-single-stack-data:/data \
  copilot-single-stack
```

Equivalent explicit example:

```bash
docker run --rm -p 3000:3000 \
  -v copilot-single-stack-data:/data \
  -e OPENAI_API_KEY=... \
  -e OPENAI_MODEL=... \
  -e OPENAI_API_BASE_URL=... \
  -e INIT_ADMIN_TOKEN=change-me \
  -e INTERNAL_API_KEY=change-me \
  -e WOT_RUNTIME_REGISTRY_TOKEN=change-me \
  -e WOT_RUNTIME_API_TOKEN=change-me \
  copilot-single-stack
```

Optional embedding-specific settings:

```bash
-e OPENAI_EMBEDDING_API_BASE_URL=...
-e OPENAI_EMBEDDING_API_KEY=...
-e OPENAI_EMBEDDING_MODEL=...
```

## Access

- App UI: `http://localhost:3000`

All internal services bind to `127.0.0.1` inside the container.

The image runs as an unprivileged `app` user by default (`uid=10001`,
`gid=10001`).

## Data

Persistent data lives under `/data`:

- `chat-ui`: `/data/chat-ui/sqlite.db`
- `copilot`: `/data/copilot/agent_state.db`
- `wot-registry`: `/data/registry`
- `valkey`: `/data/valkey`

## Updating Upstreams

To move to newer upstream commits:

```bash
git submodule update --remote upstream/copilot upstream/wot-registry
```

Then review the submodule SHA changes and rebuild the image.
