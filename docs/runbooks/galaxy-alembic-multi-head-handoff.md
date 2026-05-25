# Handoff: Galaxy alembic multi-head fix (Task #19)

**For the Galaxy/Biomate backend team — not CI/CD work.**

This is the diagnosis from the CI/CD rebuild's P2.2/P3.1 work. The CI/CD
pipeline is otherwise complete; the only thing blocking healthy deploys is
this Galaxy-fork-internal migration state.

---

## Symptom

A fresh Galaxy container against an empty Postgres database fails to
boot with:

```
manage_db.sh upgrade
  → CommandError: Multiple head revisions are present for given argument 'gxy@head';
    please specify a specific target revision, '<branchname>@gxy@head' to narrow
    to a specific head, or 'heads' for all heads
```

And running `manage_db.sh upgrade heads` (plural — apply all heads) gets
further but crashes on:

```
sqlalchemy.exc.ProgrammingError: (psycopg2.errors.UndefinedTable)
  relation "workflow" does not exist
  [SQL: ALTER TABLE workflow ADD COLUMN source_metadata BYTEA]
```

This means alembic is interleaving the two divergent branches in a way
that executes an ALTER (from migration `b182f655505f`) before the
prior migration on the OTHER branch has CREATEd the table.

---

## Root cause

The gxy alembic tree has **two heads**:

```
backend/lib/galaxy/model/migrations/alembic/versions_gxy/
├── 3af58c192752_implement_sample_sheets.py        ← upstream Galaxy head
│     revision: 3af58c192752, down_revision: 338d0e5deb03
│     created: 2025-01-09
│
└── a7f3deepagent_autofix_tables.py                ← fork-custom head
      revision: a7f3deepagent, down_revision: c3f8a1d20260
      created: 2026-05-12 (this fork)
```

When this fork was created from upstream Galaxy, the upstream head moved
forward (`3af58c192752`) and someone added `a7f3deepagent` without
basing it on the new upstream head, so the tree split. Alembic doesn't
know which to apply first.

---

## Fix (5 minutes for someone with Galaxy alembic context)

Generate an alembic **merge migration** that joins the two heads into a
single one:

```bash
# Inside the backend container (needs Galaxy's Python env + DB stub):
cd /app
export GALAXY_CONFIG_OVERRIDE_DATABASE_CONNECTION=sqlite:////tmp/dummy.sqlite
./manage_db.sh merge -m "merge gxy heads: autofix + sample-sheets" heads
```

That creates a file like
`<new-rev>_merge_gxy_heads_autofix_sample_sheets.py` with:

```python
revision = "<new-rev>"
down_revision = ("a7f3deepagent", "3af58c192752")
```

After the merge, `manage_db.sh upgrade` (singular) works again.

---

## After the merge: verify

```bash
# 1. From a clean Postgres schema (CI/CD's test env), boot a fresh container.
#    The deploy.sh path:
gh workflow run deploy.yml --ref integration/next-phase \
  -f env=test -f tag=<sha-after-merge>

# 2. Confirm the external healthcheck flips green:
curl -I http://stage-public.biomate.ai/api/health
#    expected: HTTP/1.1 200 OK
```

If healthcheck passes, the CI/CD primitive is fully validated end-to-end
and the remaining plan items (P2.4 stage env, P4.1 prod env, P4.3
retiring `sync_to_dev.sh`) can start accumulating their "≥2 weeks of
green deploys" track record.

---

## What I tried (so this isn't re-discovered)

- `manage_db.sh init` → `Multiple heads are present; please specify a single target revision` (init can't pick a head when there are multiple).
- `manage_db.sh upgrade` → `Multiple head revisions are present for 'gxy@head'`.
- `manage_db.sh upgrade heads` (plural) → progresses further, hits `relation "workflow" does not exist [SQL: ALTER TABLE workflow ADD COLUMN source_metadata BYTEA]` because the ALTER from migration `b182f655505f` runs before the workflow-table CREATE on the other branch.
- Pre-stamping with `alembic stamp heads` then booting → Galaxy then refuses with `NoVersionTableError` after creating partial tables itself.

None of those work. The merge migration is the standard alembic recipe
for this exact situation.

---

## CI/CD context (what's blocking on this)

| What works today | What needs Task #19 |
|---|---|
| Both image-build workflows green on every push | — |
| `scripts/deploy.sh` succeeds through ECR pull + compose up + dependency gate | The external HTTP healthcheck would flip green |
| `deploy.yml` GHA wrap proven end-to-end (OIDC, SSM, Secrets fetch, auto-rollback path) | — |
| `rollback.yml` ready (same SSM mechanism) | — |
| Terraform state covers dev + test envs, zero drift | — |
| RDS Postgres provisioned for test env | — |
| Secrets Manager wired with env-scoped IAM | — |

**Stage and prod envs (P2.4, P4.1) are intentionally not provisioned yet** —
provisioning them before Task #19 clears would just create more EC2s
that can't validate anything.

`sync_to_dev.sh` remains the supported fallback for dev (per plan §P4.3
exit criteria: ≥2 weeks of green deploys, ≥1 successful auto-rollback drill,
≥1 successful major-track DB-migration deploy).
