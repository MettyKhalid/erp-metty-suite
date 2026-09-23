#!/usr/bin/env bash
# =============================================================================
# .devcontainer/scripts/post-create.sh
#
# WHEN:  Once — after the container is first created (or rebuilt).
# WHO:   Runs as the "node" user inside the workspace container.
# WHY:   Install dependencies, generate Prisma client, apply migrations, seed.
#
# This script is the equivalent of "setting up a new developer's machine".
# Everything that needs to happen exactly once before the project is usable.
#
# If this script fails halfway through, fix the issue and run
# "Rebuild Container" in VS Code — it will run again from scratch.
# =============================================================================

set -euo pipefail
# set -e          exit immediately if any command returns a non-zero exit code
# set -u          treat unset variables as errors (catches typos in var names)
# set -o pipefail a pipeline fails if ANY command in it fails, not just the last

# ── Colour helpers ────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Colour — resets all formatting

step()  { echo -e "\n${BLUE}${BOLD}▶  $1${NC}"; }
ok()    { echo -e "   ${GREEN}✓  $1${NC}"; }
warn()  { echo -e "   ${YELLOW}⚠  $1${NC}"; }
fail()  { echo -e "   ${RED}✗  $1${NC}"; exit 1; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║        ERP Business Suite — First Boot Setup        ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# =============================================================================
# STEP 1 — Wait for PostgreSQL
#
# The workspace container starts after postgres passes its healthcheck
# (depends_on: condition: service_healthy in docker-compose.yml).
# However, this script runs slightly after the container starts, and
# postgres might still be finishing its init.sql execution.
# We poll with pg_isready as a safety net.
# =============================================================================
step "Waiting for PostgreSQL..."

MAX_RETRIES=30  # 30 attempts × 2 seconds = 60 seconds maximum wait
RETRY_COUNT=0

until pg_isready -h postgres -p 5432 -U erp_user -d erp_db --quiet 2>/dev/null; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
    fail "PostgreSQL did not become ready after 60 seconds.
         Check: docker logs erp_postgres"
  fi
  echo -e "   ⏳  Still waiting... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 2
done

ok "PostgreSQL is ready"

# =============================================================================
# STEP 2 — Install API dependencies
#
# npm ci vs npm install:
#   npm ci   — reads package-lock.json exactly, deletes node_modules first.
#              Reproducible and faster for clean installs. Use in containers.
#   npm install — resolves package.json, may update package-lock.json.
#              Use when adding new packages locally.
#
# --prefer-offline: use the local npm cache if packages are already downloaded.
# Speeds up subsequent rebuilds without needing network access for every run.
# =============================================================================
step "Installing API dependencies..."
cd /workspace/api

if [ -f "package-lock.json" ]; then
  npm ci --prefer-offline
else
  # package-lock.json doesn't exist yet (Phase 2 will add it)
  warn "package-lock.json not found — skipping (will be created in Phase 2)"
fi

ok "API dependencies ready"

# =============================================================================
# STEP 3 — Generate Prisma client
#
# Reads prisma/schema.prisma and generates:
#   node_modules/.prisma/client/   the actual database client code
#   TypeScript types for every model
#
# MUST run:
#   - AFTER npm install (prisma CLI lives in node_modules/.bin/)
#   - BEFORE any TypeScript file that imports from '@prisma/client'
#   - EVERY TIME schema.prisma changes (VS Code's Prisma extension reminds you)
# =============================================================================
step "Generating Prisma client..."

if [ -f "prisma/schema.prisma" ]; then
  npx prisma generate
  ok "Prisma client generated"
else
  warn "prisma/schema.prisma not found — skipping (will be added in Phase 2)"
fi

# =============================================================================
# STEP 4 — Apply database migrations
#
# "prisma migrate deploy" vs "prisma migrate dev":
#
#   migrate dev    Interactive. CREATES new migration files from schema changes.
#                  Prompts you to name the migration. Use this when developing.
#
#   migrate deploy Non-interactive. APPLIES existing migration files.
#                  Safe for containers, CI, and production. Never creates new
#                  migration files — only runs what's already in prisma/migrations/.
#
# We use "deploy" here because this script runs non-interactively inside
# a container. When you add a new model in Phase 2, you will run
# "prisma migrate dev" manually from your VS Code terminal.
# =============================================================================
step "Applying database migrations..."

if [ -f "prisma/schema.prisma" ] && [ -d "prisma/migrations" ]; then
  npx prisma migrate deploy
  ok "Migrations applied"
else
  warn "No migrations found — skipping (will be added in Phase 2)"
fi

# =============================================================================
# STEP 5 — Seed the database
#
# Inserts initial data needed to use the application:
#   - Default roles: admin, manager, employee
#   - Admin user: admin@erp.dev / Admin123!
#   - Sample company record
#
# The seed script uses "upsert" operations so it is idempotent —
# running it multiple times does not create duplicate records.
#
# Configured in api/package.json under "prisma.seed".
# =============================================================================
step "Seeding the database..."

if [ -f "prisma/schema.prisma" ]; then
  if npx prisma db seed 2>/dev/null; then
    ok "Database seeded"
  else
    warn "Seed script not found or failed — skipping (will be added in Phase 2)"
  fi
else
  warn "No schema found — skipping seed"
fi

# =============================================================================
# STEP 6 — Install Frontend dependencies
# =============================================================================
step "Installing Frontend dependencies..."
cd /workspace/frontend

if [ -f "package-lock.json" ]; then
  npm ci --prefer-offline
else
  warn "frontend/package-lock.json not found — skipping (will be added in Phase 3)"
fi

ok "Frontend dependencies ready"

# =============================================================================
# Done
# =============================================================================
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║               Setup complete!                           ║"
echo "  ╠══════════════════════════════════════════════════════════╣"
echo "  ║  Open new terminal tabs and run:                        ║"
echo "  ║                                                          ║"
echo "  ║   cd api && npm run dev         API  → :3000            ║"
echo "  ║   cd frontend && npm start      App  → :4200            ║"
echo "  ║   cd api && npx prisma studio   DB   → :5555            ║"
echo "  ║                                                          ║"
echo "  ║   Swagger  →  http://localhost:3000/documentation       ║"
echo "  ║   pgAdmin  →  http://localhost:5050                     ║"
echo "  ║                login: admin@erp.dev / admin             ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"