# ERP Business Suite

Full-stack ERP system for medium-sized businesses, developed entirely
inside a VS Code DevContainer — no local Node.js or PostgreSQL required.

**Stack**

| Layer    | Technology                             |
| -------- | -------------------------------------- |
| Frontend | Angular 20 · Signals · PrimeNG         |
| API      | HapiJS · TypeScript · Joi · Swagger    |
| ORM      | Prisma                                 |
| Database | PostgreSQL 16                          |
| Dev env  | Docker Desktop · VS Code DevContainers |

---

## Prerequisites

- **Docker Desktop** for Mac — https://www.docker.com/products/docker-desktop
  Settings → Resources: allocate at least 4 CPU / 6 GB RAM
- **VS Code** — https://code.visualstudio.com
- **Dev Containers extension** — ID: `ms-vscode-remote.remote-containers`

---

## Quick start

```bash
git clone <repo-url> erp-suite
cd erp-suite
code .
# VS Code will prompt → "Reopen in Container" → click it
# First build: ~4 min   |   Subsequent starts: ~15 s
```

---

## Project structure

```
erp-suite/
├── .devcontainer/               # VS Code DevContainer config  (Step 5)
│   ├── devcontainer.json
│   ├── docker-compose.devcontainer.yml
│   └── scripts/
│       ├── post-create.sh       # Runs once on first boot
│       └── post-start.sh        # Runs on every container start
│
├── docker/                      # Docker infrastructure
│   ├── docker-compose.yml       # All service definitions      (Step 4)
│   ├── workspace/
│   │   └── Dockerfile           # Node 20 dev image            (Step 2)
│   ├── postgres/
│   │   └── init.sql             # Schemas, extensions, audit   (Step 3)
│   └── pgadmin/
│       └── servers.json         # Pre-configured DB connection  (Step 3)
│
├── api/                         # HapiJS + TypeScript  (Phase 2 onward)
├── frontend/                    # Angular 20           (Phase 3 onward)
│
├── .vscode/
│   ├── extensions.json          # Recommended extensions
│   └── launch.json              # Debugger configurations
│
├── .gitignore
└── README.md                    ← you are here
```

---

## Service URLs (once the container is running)

| Service     | URL                                 | Credentials             |
| ----------- | ----------------------------------- | ----------------------- |
| Angular app | http://localhost:4200               | —                       |
| HapiJS API  | http://localhost:3000               | —                       |
| Swagger UI  | http://localhost:3000/documentation | —                       |
| pgAdmin     | http://localhost:5050               | admin@erp.local / admin |
| PostgreSQL  | localhost:5432                      | erp_user / erp_password |

---

## Development phases

| Phase      | Status | Description                  |
| ---------- | ------ | ---------------------------- |
| 1 — Step 1 | ✅     | Project skeleton (this file) |
| 1 — Step 2 | ⬜     | Workspace Dockerfile         |
| 1 — Step 3 | ⬜     | PostgreSQL + pgAdmin         |
| 1 — Step 4 | ⬜     | Full docker-compose stack    |
| 1 — Step 5 | ⬜     | DevContainer wiring          |
| 2          | ⬜     | Prisma schema + migrations   |
| 3          | ⬜     | Auth module end-to-end       |
| 4          | ⬜     | ERP modules                  |
