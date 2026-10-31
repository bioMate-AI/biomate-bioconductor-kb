# Benchling integration: how to connect, and the state of our connector

Date: 2026-10-30
Scope: Benchling's official integration options, checked against Benchling's developer documentation on 2026-10-30, and a code review of BioMate's existing Benchling connectors. No Benchling tenant was available, so nothing was tested against a live Benchling API.

## Update: MCP is the fastest path (added after checking Benchling's AI Connector docs)

Benchling AI (Chat and Deep Research) accepts **external MCP servers as "AI Connectors"**. BioMate already runs a compatible remote MCP server, so customers can connect to us **without any new integration code**.

**How a Benchling customer connects to BioMate today (custom AI Connector):**
1. Prerequisites: the tenant has Benchling **Chat or Deep Research** enabled. No additional Benchling licence is required.
2. The tenant admin goes to **Tenant Admin Console → Settings → AI Connectors → Add AI Connector**:
   - Name: `BioMate`
   - Server: `https://<biomate-host>/mcp` (dev: `https://dev-public.biomate.ai/mcp`)
   - Type: **HTTP** (Streamable HTTP; the default)
   - OAuth: dynamic discovery / dynamic client registration. Manual OAuth registration with client ID and secret is the fallback.
   - Then choose which BioMate tools users may use.
3. Each user goes to **AI → Settings → AI Connectors → Connect BioMate**, signs in to BioMate (OAuth), and picks tools.
4. Benchling Chat and Deep Research then call BioMate tools when a prompt needs them. Examples: search workflows, run a workflow, watch a run, analyze results, search literature, query databases, export a report.

**Our server already provides what Benchling needs** (verified live on dev, 2026-10-30):
- `POST /mcp` returns `401` with `WWW-Authenticate: Bearer resource_metadata=".../.well-known/oauth-protected-resource"`.
- RFC 9728 protected-resource metadata and RFC 8414 authorization-server metadata are both served.
- **Dynamic client registration** at `/oauth/register`; authorization code + PKCE (S256); refresh tokens; scopes `workflows:search`, `runs:read/write`, `files:upload`, `reports:export`, `memory:read/write`, `billing:read`.
- 24 tools (`biomate-connector/mcp/tools_manifest.json`), the same server used by the claude.ai, Claude Desktop, Cursor and ChatGPT connectors.

**To verify with a real Benchling tenant** (untested; we have no tenant):
- **Client authentication:** our metadata advertises `token_endpoint_auth_methods_supported: ["none"]` (public client + PKCE). If Benchling registers as a *confidential* client (`client_secret_basic` or `client_secret_post`), the registration or token request may fail. Support confidential clients if needed.
- **Redirect URI:** Benchling's callback is `https://<tenant>.benchling.com/1/api/llm/mcp/oauth/callback`. Our dynamic registration accepts any https redirect URI, so it should work; confirm it isn't blocked by an allowlist in production.
- **`resource` parameter:** Benchling may send RFC 8707 `resource` (it offers a "Suppress resource parameter" override). Confirm our authorize and token endpoints accept or ignore it.
- **Tool descriptions:** Benchling's agent picks tools from their descriptions. Check that the descriptions route scientific prompts well, and decide which tools to enable by default; for example, keep `run_instrument_protocol` off.
- **Data flow:** Benchling's cloud calls our server, so the customer's prompts and any data passed to tools reach BioMate's cloud. This needs the customer's agreement and a data-processing agreement. It does **not** suit on-premises or air-gapped BioMate deployments, such as SYSUCC, because Benchling must reach a public HTTPS endpoint.

**Getting listed in Benchling's built-in MCP Directory** (one-click install for every customer) requires Benchling's partnership team. Contact integrations@benchling.com or use https://www.benchling.com/partnerships. Directory entries currently include Notion, Snowflake, GitHub, SharePoint and PubMed.

**The other direction: BioMate reading Benchling via Benchling's own MCP server.**
- URL: `https://<tenant>.mcp.benchling.com/mcp`.
- Auth: OAuth 2.1 with delegated authentication. Dynamic client registration is officially supported; API keys are not.
- Redirect URI: `https://<tenant>.benchling.com/1/api/llm/mcp/oauth/callback` is Benchling's callback when *Benchling* is the client. As a client, BioMate registers its own redirect URI.
- Requirements: the tenant has Benchling Chat and Benchling MCP enabled (Admin → Settings → AI Settings), plus V3 APIs. It is not available on Benchling for Academics; Validated Cloud needs Benchling's help.

This suits **conversational** access ("summarize the hERG results for series X"). It does **not** replace a structured REST or warehouse sync for training labels, which needs complete, typed, reviewed data with provenance (sections 1–4 below).

**Documentation MCP:** `https://docs.benchling.com/mcp` (public, no credentials) lets developer tools search Benchling's docs.

Sources: https://help.benchling.com/hc/en-us/articles/42715696739341 (AI Connectors, updated 2026-07-25), https://help.benchling.com/hc/en-us/articles/40342713479437 (Benchling MCP server), https://www.benchling.com/ai/connectors, https://docs.benchling.com/docs-mcp.md, https://docs.benchling.com/docs/agents-api.md (`sources: [{"type":"mcp_server","serverId":"mcpconf_…"}]`).

## Summary

- **The recommended path** is a **Benchling App**: OAuth 2.0 client credentials plus the REST API v2, installed into the customer's tenant. Benchling documents personal API keys as "generally discouraged".
- **Access requirements:**
  - The customer's tenant needs the **Developer Platform**, which is available to **enterprise tenants** only and is enabled by a tenant admin.
  - As a software vendor, we can build one shareable app and install it into each customer's tenant via an install URL.
  - To get our own development tenant, contact Benchling's partner team (integrations@benchling.com).
- **Our current assay-polling connector would not work against a real tenant.** It uses the wrong authentication scheme and the wrong API host, omits a required filter, and reads compound links as SMILES. Its output also doesn't match our assay validator. Details are in section 3.
- **SYSUCC relevance is low.** Benchling is hosted on AWS in the US (primary) and the EU; no mainland-China hosting region is documented. It is relevant for US/EU biotech customers and CRO partners, not for a Chinese hospital's on-premises deployment.

## 1. Ways to connect (official options)

| Method | How it works | Best for | Notes |
| --- | --- | --- | --- |
| **Benchling App + REST API v2** (recommended) | App gets `client_id`/`client_secret`; `POST https://{tenant}.benchling.com/oauth/token` with `grant_type=client_credentials`; then `Authorization: Bearer <token>` on `https://{tenant}.benchling.com/api/v2/...` | Read and write sync; scheduled pulls; writing results back | Tokens expire after 15 min and have no refresh token, so request a new one. Actions are attributed to the app in audit logs, with the app's own scoped permissions. The SDK handles tokens. |
| **Delegated auth** (OAuth authorization code) | The app acts as the signed-in user | Interactive use from inside BioMate, with the user's own permissions | Requires a user in the loop. |
| **Events: webhooks** | Subscriptions are declared in the app manifest; Benchling POSTs thin payloads (IDs only), then we fetch the resource | Near-real-time reaction to new assay runs or registered entities (`v2.assayRun.created`, `v2.entity.registered`, `v2.entry.updated.reviewRecord`) | Needs a **public HTTPS endpoint**. Calls come from fixed Benchling IPs per region. |
| **Events: AWS EventBridge** | Benchling sends hydrated payloads to an event bus in our AWS account | We already run on AWS; this suits our hosted/dev deployment | Not permission-scoped; 256 KB payload limit; also carries alpha/beta events. |
| **Data warehouse** (read-only PostgreSQL) | `postgres-warehouse.{tenant}.benchling.com:5432/warehouse` with warehouse credentials, TLS | Bulk historical pulls and analytics; reviewed-only views | Two forms per schema: `<schema>$raw` (all data) and `<schema>` (reviewed, valid data only). Data lags the live system. Access is limited to permitted projects. |
| **Personal API key** | HTTP **Basic** auth: key as username, empty password | Quick trials only | Attributed to the user who created the key. Benchling discourages it for integrations. |

**Recommended architecture for BioMate:**

1. A Benchling App with client credentials and read access to the relevant assay-result schemas and molecule/custom-entity schemas. Write access only if we push results back.
2. **Pull** with `GET /api/v2/assay-results?schemaId=...&modifiedAt.gt=<watermark>&sort=modifiedAt:asc`, paging with `nextToken` (max `pageSize` 100). Store the watermark and the Benchling result IDs so re-runs are idempotent.
3. Optionally, **webhooks** (hosted deployments) or **EventBridge** (our AWS) to trigger the pull immediately instead of on a schedule.
4. The **warehouse** for an initial backfill of historical data, using the reviewed-only views.
5. Write-back of BioMate outputs, such as predictions or model scores, as a *separate* result schema labelled as computational. Never write into measured-result schemas.

## 2. Benchling data model: what our mapping must handle

- **Assay results are schema-specific.** Each result has `fields: {fieldName: {value, type, displayValue, ...}}`.
  - Field types include `float`, `integer`, `text`, `dropdown`, `molecule_link`, `custom_entity_link`, `entity_link`, `batch_link` and `assay_run_link`.
  - Field names and units are defined per customer schema, so the mapping must be **configured per schema**, not guessed.
- **Compounds are links, not SMILES.** A `molecule_link` field's `value` is an ID such as `mol_…`. Resolve it with `GET /api/v2/molecules/{id}`, which returns `canonicalizedSmiles`, `originalSmiles` and the registry ID (`entityRegistryId`).
  - Many customers register compounds as **custom entities** with a structure field instead, which needs a schema-specific lookup.
  - Use **bulk-get** endpoints to avoid one call per row.
- **Review status:**
  - Results carry `isReviewed` (attached to an accepted entry) and an archive status.
  - For training labels, ingest **reviewed, non-archived** results by default (`archiveReason=NOT_ARCHIVED`), or record the review status so the learning loop can exclude unreviewed data.
- **Provenance to keep with each row:** the Benchling result ID, schema ID, assay run ID, entry ID, creator, `createdAt`/`modifiedAt`, and the molecule registry ID and batch. This fits BioMate's provenance model.
- **Required filter:** `list assay results` requires either `schemaId` or `automationOutputProcessorId`. There is no "all schemas" listing of results.

## 3. Review of BioMate's current connectors

There are **two separate connectors**:

- `backend/lib/galaxy/ai/drug_discovery/benchling_connector.py`: used by the campaign polling endpoint `api_router.py` (`/benchling` poll → `AssayIngestionService`).
- `backend/lib/integrations/benchling_connector.py`: a broader ELN, sample and assay client used for workflow input and output.

A third piece, the connection check in `frontend/server/routes.ts` (~line 16918), validates a key against `/api/v2/entries`.

### The drug-discovery polling connector: defects

| # | Defect | Location | Effect |
| --- | --- | --- | --- |
| 1 | Sends a personal API key as `Authorization: Bearer <key>` | `_headers()` | API keys must use **Basic** auth, so a real key would be rejected. No OAuth app support. |
| 2 | Default base URL `https://api.benchling.com/v2`; the API router never passes a tenant | `BASE_URL`, `api_router.py` ~line 1000 | The API is per tenant (`https://{tenant}.benchling.com/api/v2`), so calls go to the wrong host. |
| 3 | `schemaId` is optional | `list_assay_results(schema_id=None)` | The API requires `schemaId` or `automationOutputProcessorId`, so a call without one fails. |
| 4 | Reads SMILES from a field literally named `smiles`/`SMILES`; takes `compound_id` from a field's raw value | `_normalize_result` | Compound fields are usually `molecule_link`/`custom_entity_link` **IDs**, so SMILES is usually empty and the compound ID is a Benchling-internal ID. |
| 5 | Takes the **first numeric field** as the assay value | `_normalize_result` | Can pick the wrong measurement, such as a concentration, replicate number or Hill slope, silently. |
| 6 | Output keys `assay_name`/`assay_value`/`created_at` | `_normalize_result` | Our validator expects `assay_type`/`value`/`assay_date` (plus unit and identity), so polled rows are rejected. This is already in the handoff. |
| 7 | **Silent mock mode** when no key is set | `__init__` | It returns synthetic results that look real. The endpoint currently demands a key, but the class default is unsafe. |
| 8 | API key accepted as a **query parameter** | `api_router.py` `benchling_api_key` | Secrets in URLs end up in access logs and browser history. |
| 9 | Review and archive status ignored | — | Unreviewed or archived results can become training labels. |

### Other notes

- The **integrations connector** uses Basic auth correctly and takes a tenant URL. It is a better base, but it still has no OAuth app support, and it shares the mapping problems for assay results.
- The **frontend connection check** uses Basic auth correctly, but its default URL `https://benchling.com` is not a tenant URL; it should require the tenant URL. A reachable `/entries` call also proves only that the key works, not that assay-schema access exists.

## 4. Recommended implementation (when prioritized)

1. **Consolidate** into one connector module with:
   - **OAuth client-credentials** auth, with 15-minute token renewal, plus Basic-auth API keys for trials only;
   - a required tenant URL;
   - retry with backoff on HTTP 429 and 5xx.

   Consider Benchling's Python SDK (`benchling-sdk`), which handles auth, pagination and rate limits.
2. **Per-schema mapping configuration**, stored per BioMate project or campaign:
   - `schemaId`;
   - which field holds the compound link and its entity type;
   - the value field and assay type;
   - the unit source;
   - the operator/qualifier field (for censored values `<`/`>`);
   - the replicate/batch fields;
   - the review policy.

   No heuristics.
3. **Resolve compound links** in bulk to `canonicalizedSmiles` plus the registry ID. Feed the registry ID as the compound identity, and the SMILES into the existing identity-conflict and salt/parent checks.
4. **Map to the validated ingestion contract** at the connector boundary, sharing the row-level validator with CSV ingestion (the `validate_rows` / `ingest_rows` design in the handoff). Keep the Benchling provenance fields.
5. **Incremental sync:** a stored `modifiedAt` watermark, idempotent upserts keyed on the Benchling result ID, handling of edits and archives, and default ingestion of reviewed, non-archived results only.
6. **Events (optional):** webhooks for hosted deployments, or EventBridge on our AWS, to trigger syncs.
7. **Write-back (optional):** a dedicated "BioMate computational prediction" result schema with model version and run ID.
8. **Security:**
   - no secrets in query strings; credentials in the platform's secret store;
   - scope the app to the needed projects and schemas;
   - remove silent mock mode, using a separate, clearly labelled demo fixture instead.
9. **Testing:**
   - unit tests with recorded Benchling payloads (mocking the external HTTP API is acceptable);
   - an end-to-end test against a real Benchling test tenant before claiming the integration works.

## 5. Relevance to SYSUCC and other customers

- **SYSUCC (on-premises, China):**
  - No mainland-China hosting region is documented. Data would be stored in the US or EU, which conflicts with on-premises and data-residency expectations.
  - Webhooks need a public endpoint, which won't fit an on-premises deployment behind the hospital firewall.
  - Chinese hospitals typically use domestic ELN/LIMS systems.
  - **Don't raise Benchling with SYSUCC.** If they mention an existing ELN or LIMS, ask what it is and whether it offers an API or database export.
- **US/EU biotech customers and CRO partners:** this integration is valuable. Benchling is common there, and the assay → learning loop is a natural fit. Prioritize it when such a customer is in the pipeline, and obtain a test tenant through Benchling's partner program or the customer.

## Sources

- Authentication (methods, OAuth client credentials, Basic API keys): https://docs.benchling.com/docs/authentication
- Token endpoint: https://docs.benchling.com/docs/api/benchling-api/authentication/get-token
- List assay results (query parameters, required `schemaId` or processor ID, field types): https://docs.benchling.com/docs/api/v2/benchling-api/assay-results/list-assay-results.md
- Molecules (`canonicalizedSmiles`, `originalSmiles`, registry ID): https://docs.benchling.com/docs/api/v2/benchling-api/molecules/get-molecule.md
- Events, webhooks vs EventBridge: https://docs.benchling.com/docs/receiving-events-in-your-app , https://docs.benchling.com/docs/events-reference
- Data warehouse: https://docs.benchling.com/docs/getting-started , https://help.benchling.com/hc/en-us/articles/39956448280717
- Developer platform access (enterprise tenants): https://help.benchling.com/hc/en-us/articles/9714802977805 , https://docs.benchling.com/docs/developer-platform-overview
- Sharing apps across tenants: https://docs.benchling.com/docs/managing-and-sharing-benchling-apps
- Partner program: https://www.benchling.com/partnerships
- Hosting and security (US primary, EU on request, AWS): https://help.benchling.com/hc/en-us/articles/39953690790669 ; Benchling Data Processing Addendum (Oct 2023)
