# Preserved from the deleted nested clone — MCP HIPAA sync change (2026-11-01)

While reclaiming disk, the accidental 5.5 GB nested git clone at
`biomate-review/biomate/` (on `integration/next-phase`, fully pushed) was deleted.
It had one uncommitted code change worth preserving: a 2-line addition to
`scripts/sync_to_dev.sh` in the `deploy_remote_mcp()` function, part of the
SYSUCC HIPAA MCP isolation WIP (see
`docs/20261031_SYSUCC_PRODUCT_AND_MCP_HIPAA_HANDOFF.md`).

This was NOT auto-applied to this tree's `scripts/sync_to_dev.sh` — it is a
deploy-behavior change (enables HIPAA mode + disables local tools for the remote
MCP container on dev) and belongs to the SYSUCC/connector workstream. Reapply
deliberately if/when that work lands.

```diff
--- a/scripts/sync_to_dev.sh
+++ b/scripts/sync_to_dev.sh
@@ deploy_remote_mcp() @@
       -e BIOMATE_API_URL=http://biomate-dev-frontend:3000 \
       -e BIOMATE_MCP_PUBLIC_URL=https://dev-public.biomate.ai \
       -e BIOMATE_OAUTH_ISSUER=https://dev-public.biomate.ai \
+      -e BIOMATE_MCP_HIPAA=1 \
+      -e BIOMATE_MCP_ALLOW_LOCAL_TOOLS=0 \
       -e BIOMATE_MCP_REQUIRE_AUTH=0 \
       -e BIOMATE_OAUTH_SIGNING_KEY="$SIGNING_KEY" \
       -e BIOMATE_OAUTH_DB=/var/lib/biomate/oauth.db \
```

The handoff doc itself was also preserved to
`docs/20261031_SYSUCC_PRODUCT_AND_MCP_HIPAA_HANDOFF.md` (it referenced that path
as its canonical location, which did not previously exist in this tree).
