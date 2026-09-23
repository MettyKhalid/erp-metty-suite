#!/usr/bin/env bash
# =============================================================================
# .devcontainer/scripts/post-start.sh
#
# WHEN:  Every time the container starts:
#          - First boot (runs right after post-create.sh)
#          - After VS Code reconnects to an existing container
#          - After Docker Desktop restarts
#          - After your Mac wakes from sleep and Docker reconnects
#
# WHO:   Runs as the "node" user inside the workspace container.
#
# RULES:
#   1. Keep it FAST — this runs before your terminal opens.
#      If it takes 10+ seconds the developer experience suffers.
#   2. Keep it IDEMPOTENT — must be safe to run multiple times.
#   3. Do NOT install packages here — that is post-create.sh's job.
#      Running npm install on every start would be very slow.
#
# PURPOSE: lightweight health checks and a useful quick-reference print.
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── 1. PostgreSQL connectivity check ──────────────────────────────────────────
# Quick non-blocking check — just report status, don't wait or retry.
# If postgres isn't ready yet (e.g. Docker just restarted), the developer
# will see the warning and can manually retry after a few seconds.
if pg_isready -h postgres -p 5432 -U erp_user -d erp_db --quiet 2>/dev/null; then
  echo -e "${GREEN}✓ PostgreSQL connected${NC}"
else
  echo -e "${YELLOW}⚠ PostgreSQL not ready yet — wait a moment and retry${NC}"
  echo "  Run: pg_isready -h postgres -p 5432 -U erp_user"
fi

# ── 2. Pending migrations check ───────────────────────────────────────────────
# If a teammate pushed a new migration, this reminds you to apply it
# before starting the API (otherwise Prisma will throw schema mismatch errors).
#
# We only run this if schema.prisma exists — it won't exist until Phase 2.
# "|| true" prevents the script from exiting if prisma returns non-zero
# (which it does when there are pending migrations — that is not an error here).
if [ -f "/workspace/api/prisma/schema.prisma" ]; then
  cd /workspace/api

  PENDING=$(npx prisma migrate status 2>/dev/null \
    | grep -c "have not yet been applied" || true)

  if [ "$PENDING" -gt 0 ]; then
    echo -e "${YELLOW}⚠ $PENDING unapplied migration(s) detected${NC}"
    echo "  Run: cd api && npx prisma migrate deploy"
  fi
fi

# ── 3. Quick-reference ────────────────────────────────────────────────────────
# Printed every time the terminal opens — no need to remember commands.
echo ""
echo "  ──────────────────────────────────────────────────────────"
echo "  ERP Business Suite — DevContainer ready"
echo "  ──────────────────────────────────────────────────────────"
echo "  API           cd api && npm run dev"
echo "  Frontend      cd frontend && npm start"
echo "  Prisma UI     cd api && npx prisma studio"
echo "  New migration cd api && npx prisma migrate dev --name <desc>"
echo "  ──────────────────────────────────────────────────────────"
echo "  Swagger  →  http://localhost:3000/documentation"
echo "  pgAdmin  →  http://localhost:5050  (admin@erp.dev / admin)"
echo "  ──────────────────────────────────────────────────────────"
echo ""