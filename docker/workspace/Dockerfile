# =============================================================================
# docker/workspace/Dockerfile
#
# The development container for the entire ERP project.
# Both the HapiJS API and the Angular frontend run inside this one container.
#
# WHY one container for both?
#   VS Code Dev Containers attaches to exactly ONE running container.
#   Rather than pick one service, we run both inside a single Node.js
#   container and open separate terminal tabs for each.
#   It keeps the setup simple and avoids networking complexity at this stage.
#
# WHY node:20-bullseye-slim and not alpine?
#   Alpine uses musl libc instead of glibc. Some npm packages with native
#   bindings (node-gyp, bcrypt, canvas...) fail to compile on Alpine without
#   extra workarounds. Debian "slim" gives us a safe, compatible base with
#   a much smaller footprint than the full Debian image.
#   Result: ~250 MB base vs ~80 MB alpine (but alpine causes hard-to-debug
#   errors later, so the tradeoff is not worth it for a dev environment).
#
# WHY pin to "20" and not "latest"?
#   "latest" would silently upgrade to Node 22 on the next docker pull,
#   potentially breaking our code. Pinning to a major version (20) is safe:
#   we get patch updates automatically but no breaking major upgrades.
# =============================================================================

FROM node:20-bullseye-slim

# -----------------------------------------------------------------------------
# Layer 1 — System packages
#
# We install everything in ONE RUN command. This is important:
#   - Every RUN creates a new image layer
#   - The apt cache created by "apt-get update" is stored in that layer forever
#   - If update and install were separate RUN commands, the cache layer would
#     bloat the image size permanently even after "rm -rf /var/lib/apt/lists/*"
#   - Combining them means the cache is created and deleted in the same layer
#
# --no-install-recommends  →  skip optional packages (saves ~50 MB)
# rm -rf /var/lib/apt/lists/*  →  delete the package list cache after install
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # pg_isready — used in our lifecycle scripts (post-create.sh, post-start.sh)
    # to poll until PostgreSQL accepts connections before running migrations
    postgresql-client \
    # curl — for quick manual API testing from the terminal
    # also used by some DevContainer features during setup
    curl \
    # git — required by some npm install scripts and by the GitHub CLI feature
    git \
    # procps — provides "ps" and "top", useful for identifying stuck processes
    procps \
    # Clean up the apt package cache — reduces image size by ~40 MB
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Layer 2 — Global npm tools
#
# These need to be available anywhere in the filesystem (on PATH),
# not just inside a specific project's node_modules.
#
# WHY global here and not local per-project?
#   - @angular/cli needs "ng" on PATH before the frontend project is created
#   - tsx needs to be available to run "tsx watch src/server.ts" from any dir
#   - typescript's "tsc" is useful globally for one-off checks
#
# npm cache clean --force → removes downloaded package tarballs after install
# Saves ~100 MB from the image that would otherwise be cached unnecessarily.
# -----------------------------------------------------------------------------
RUN npm install -g \
    # Angular CLI — "ng generate", "ng build", "ng serve"
    # @latest ensures we get Angular 20 (current latest at time of writing)
    @angular/cli@latest \
    # TypeScript compiler — "tsc" available globally for debugging and checks
    typescript \
    # tsx — TypeScript Execute. Runs .ts files directly without a compile step.
    # Used by the API's "npm run dev" script: "tsx watch src/server.ts"
    tsx \
    && npm cache clean --force

# -----------------------------------------------------------------------------
# Layer 3 — Working directory
#
# WORKDIR creates the directory if it doesn't exist and sets it as the
# default directory for all subsequent RUN, CMD, COPY, and ENTRYPOINT
# instructions, and for the terminal session when you attach to the container.
#
# /workspace is the path where we'll bind-mount our project code.
# The bind-mount is defined in docker-compose, not here — the Dockerfile
# just prepares the directory and its permissions.
# -----------------------------------------------------------------------------
WORKDIR /workspace

# Give the "node" user ownership of /workspace.
# Without this, root owns the directory and the "node" user (our runtime user)
# cannot create files in it — which would break npm install, file generation, etc.
RUN chown -R node:node /workspace

# -----------------------------------------------------------------------------
# Layer 4 — Switch to non-root user
#
# The official node image ships with a pre-created user called "node" (UID 1000).
# We switch to it here so the container never runs as root.
#
# WHY non-root?
#   1. Security: if an attacker exploits a vulnerability in the app, they get
#      "node" privileges, not root. Root would let them escape the container.
#   2. File permissions: on macOS, Docker Desktop maps UIDs transparently,
#      so files created by the "node" user are readable/writable on the host
#      without any extra UID remapping configuration.
#
# Every instruction AFTER this USER line runs as "node", including CMD.
# -----------------------------------------------------------------------------
USER node

# -----------------------------------------------------------------------------
# EXPOSE — Port documentation
#
# EXPOSE does NOT publish or open ports. It is purely metadata that tells
# Docker (and other developers) which ports this container listens on.
# Actual port publishing happens in docker-compose.yml via "ports:" entries.
#
# 3000 → HapiJS API
# 4200 → Angular dev server
# -----------------------------------------------------------------------------
EXPOSE 3000
EXPOSE 4200

# -----------------------------------------------------------------------------
# CMD — Default command
#
# This is what runs when you start the container without specifying a command.
# "bash" opens an interactive shell — useful for manual exploration.
#
# In docker-compose.devcontainer.yml this will be overridden to
# "sleep infinity" so VS Code can attach and keep the container alive
# without a process that would exit.
# -----------------------------------------------------------------------------
CMD ["bash"]