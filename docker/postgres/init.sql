-- =============================================================================
-- docker/postgres/init.sql
--
-- WHEN does this file run?
--   The official postgres image looks for files in:
--     /docker-entrypoint-initdb.d/
--   and executes them in alphabetical order on FIRST BOOT ONLY —
--   meaning only when the postgres_data volume is completely empty.
--
--   If the volume already has data (any subsequent container start أي عملية تشغيل لاحقة للحاوية),
--   this file is silently ignored. That is intentional: it prevents
--   destructive re-initialization on restart.
--
-- WHO runs it?
--   The postgres image entrypoint runs it as the "postgres" superuser,
--   before the container is marked healthy. This is important because
--   our other services wait for the healthcheck before starting.
--
-- WHAT belongs here vs in Prisma migrations?
--   This file  → infrastructure that Prisma migrations depend ON:
--                extensions, schemas, privileges, audit infrastructure.
--   Prisma     → all application tables (users, products, orders, etc.)
--
-- The rule: if a Prisma migration would fail without it, it goes here.
-- =============================================================================


-- =============================================================================
-- PART 1 — Extensions
--
-- Extensions add functionality to PostgreSQL.
-- They must be installed by a superuser (postgres), which is why they live
-- here instead of in a Prisma migration (which runs as erp_user).
--
-- "IF NOT EXISTS" makes every statement idempotent — safe to re-run.
-- =============================================================================

-- uuid-ossp: provides uuid_generate_v4() for generating UUIDs in raw SQL.
-- Prisma uses gen_random_uuid() (built into PG 13+) for its own migrations,
-- but this extension is useful for hand-written seed scripts and raw queries.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- pgcrypto: provides gen_random_uuid(), crypt(), and gen_salt().
-- We hash passwords in the application layer (bcrypt via Node.js), but
-- pgcrypto is available as a fallback and for any DB-level encryption needs.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- pg_trgm: trigram-based text similarity and fuzzy search.
-- Enables fast ILIKE '%...%' queries using GIN indexes.
-- We will use this in Phase 4 for product and customer search.
CREATE EXTENSION IF NOT EXISTS "pg_trgm";


-- =============================================================================
-- PART 2 — Schemas
--
-- A PostgreSQL schema is a namespace — like a folder for database objects.
-- Tables, functions, and views inside a schema are accessed as schema.table.
--
-- We use 3 schemas to separate concerns clearly:
--
--   auth   →  authentication & authorisation
--              (users, roles, refresh_tokens)
--
--   erp    →  all business domain tables
--              (products, orders, employees, customers, suppliers, ...)
--
--   audit  →  append-only change log
--              (who changed what and when — never modified by app logic)
--
-- Benefits of this separation:
--   1. Access control: you can grant SELECT on "erp" without exposing "auth"
--   2. Clarity: the schema name immediately tells you what domain a table is in
--   3. Audit isolation: business logic cannot accidentally UPDATE audit rows
--      because the audit schema can be made read-only for the app user
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS erp;
CREATE SCHEMA IF NOT EXISTS audit;


-- =============================================================================
-- PART 3 — Privileges
--
-- Grant erp_user full access to all three schemas.
--
-- There are TWO kinds of privilege grants needed:
--
--   GRANT ON SCHEMA     →  allows erp_user to "see" the schema and use it
--                          (without this, queries like SELECT * FROM erp.products
--                          return "permission denied for schema erp")
--
--   ALTER DEFAULT PRIVILEGES →  applies to objects created IN THE FUTURE.
--                               Without this, tables created by Prisma migrations
--                               (which run as erp_user) would not be accessible
--                               to erp_user itself — which sounds paradoxical but
--                               is a real PostgreSQL gotcha when the schema owner
--                               differs from the connecting user.
-- =============================================================================

-- Schema-level access
GRANT ALL PRIVILEGES ON SCHEMA auth  TO erp_user;
GRANT ALL PRIVILEGES ON SCHEMA erp   TO erp_user;
GRANT ALL PRIVILEGES ON SCHEMA audit TO erp_user;

-- Future tables and sequences in each schema
ALTER DEFAULT PRIVILEGES IN SCHEMA auth
    GRANT ALL ON TABLES    TO erp_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth
    GRANT ALL ON SEQUENCES TO erp_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA erp
    GRANT ALL ON TABLES    TO erp_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA erp
    GRANT ALL ON SEQUENCES TO erp_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA audit
    GRANT ALL ON TABLES    TO erp_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA audit
    GRANT ALL ON SEQUENCES TO erp_user;


-- =============================================================================
-- PART 4 — Audit infrastructure
--
-- The audit_log table and its trigger function live here — not in Prisma —
-- because they are infrastructure that application tables depend on.
-- Any table can be audited by calling audit.enable_tracking() once.
--
-- HOW IT WORKS at runtime:
--   1. Before each write operation, the API sets a session variable:
--        SET LOCAL app.current_user_id = '<uuid-of-logged-in-user>';
--      (We add this to a Prisma middleware in Phase 3.)
--   2. The INSERT / UPDATE / DELETE fires the trigger on the target table.
--   3. The trigger function reads app.current_user_id and writes a row to
--      audit.audit_log with a full JSON snapshot of the before/after state.
--
-- SECURITY DEFINER means the function executes with the privileges of its
-- OWNER (postgres superuser), not the caller (erp_user). This lets erp_user
-- write audit rows even if the audit schema is otherwise read-only for it.
-- =============================================================================

-- The audit log table itself
CREATE TABLE IF NOT EXISTS audit.audit_log (
    id            UUID         NOT NULL DEFAULT gen_random_uuid(),
    table_schema  TEXT         NOT NULL,
    table_name    TEXT         NOT NULL,
    -- Operation is constrained to exactly these three values
    operation     TEXT         NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    -- Full JSON snapshot of the row BEFORE the change (NULL for INSERT)
    old_data      JSONB,
    -- Full JSON snapshot of the row AFTER the change (NULL for DELETE)
    new_data      JSONB,
    -- The UUID of the logged-in user, set by the API via SET LOCAL
    changed_by    TEXT,
    changed_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_audit_log PRIMARY KEY (id)
);

-- Index 1: "show me all changes to erp.products, newest first"
CREATE INDEX IF NOT EXISTS idx_audit_table_time
    ON audit.audit_log (table_schema, table_name, changed_at DESC);

-- Index 2: "show me everything user X changed today"
CREATE INDEX IF NOT EXISTS idx_audit_user_time
    ON audit.audit_log (changed_by, changed_at DESC);

-- The trigger function — called by any trigger attached via enable_tracking()
CREATE OR REPLACE FUNCTION audit.log_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO audit.audit_log (
        table_schema,
        table_name,
        operation,
        old_data,
        new_data,
        changed_by,
        changed_at
    ) VALUES (
        TG_TABLE_SCHEMA,
        TG_TABLE_NAME,
        TG_OP,
        -- Capture OLD row for DELETE and UPDATE; NULL for INSERT
        CASE WHEN TG_OP IN ('DELETE', 'UPDATE')
             THEN row_to_json(OLD)::jsonb
             ELSE NULL
        END,
        -- Capture NEW row for INSERT and UPDATE; NULL for DELETE
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE')
             THEN row_to_json(NEW)::jsonb
             ELSE NULL
        END,
        -- "true" = return NULL instead of raising an error if the variable is not set
        current_setting('app.current_user_id', true),
        NOW()
    );

    -- Triggers must return the row being processed
    -- COALESCE handles all three operations: NEW is NULL for DELETE, OLD is NULL for INSERT
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- =============================================================================
-- PART 5 — Convenience helper
--
-- Attaches the audit trigger to any table with a single function call.
-- We will call this from Prisma migration files in Phase 2 for key tables.
--
-- Usage example (run once per table):
--   SELECT audit.enable_tracking('erp', 'products');
--   SELECT audit.enable_tracking('auth', 'users');
-- =============================================================================

CREATE OR REPLACE FUNCTION audit.enable_tracking(
    p_schema TEXT,
    p_table  TEXT
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_trigger_name TEXT := 'trg_audit_' || p_table;
BEGIN
    EXECUTE format(
        $sql$
            CREATE TRIGGER %I
            AFTER INSERT OR UPDATE OR DELETE ON %I.%I
            FOR EACH ROW EXECUTE FUNCTION audit.log_changes()
        $sql$,
        v_trigger_name,
        p_schema,
        p_table
    );

    RAISE NOTICE 'Audit tracking enabled on %.%', p_schema, p_table;
END;
$$;

-- =============================================================================
-- PART 6 — Readable view
--
-- A friendly view over audit_log for quick inspection in pgAdmin or psql.
-- Usage: SELECT * FROM audit.recent_changes LIMIT 20;
-- =============================================================================

CREATE OR REPLACE VIEW audit.recent_changes AS
SELECT
    to_char(changed_at, 'YYYY-MM-DD HH24:MI:SS TZ') AS "when",
    operation                                          AS "op",
    table_schema || '.' || table_name                  AS "table",
    changed_by                                         AS "who",
    CASE operation
        WHEN 'DELETE' THEN old_data
        ELSE new_data
    END                                                AS "current_state",
    old_data                                           AS "previous_state"
FROM  audit.audit_log
ORDER BY changed_at DESC;