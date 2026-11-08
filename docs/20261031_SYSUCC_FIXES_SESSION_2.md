# 2026-10-31 SYSUCC fixes — session 2

## Benchling AI Connector readiness: remote MCP OAuth (biomate-connector)

**Date:** 2026-10-31. **Repo:** `/Users/kky/biomate-connector`. Not committed and not deployed.

### What changed
- **Confidential clients.** Dynamic client registration (`POST /oauth/register`) now accepts `token_endpoint_auth_method` values `none`, `client_secret_basic` and `client_secret_post`.
  - Secret clients receive a server-generated `client_secret` (256-bit) with `client_secret_expires_at: 0`. Only a `sha256$` hash is stored.
  - The token endpoint authenticates confidential clients on both the `authorization_code` and `refresh_token` grants. It accepts the secret either in an HTTP Basic header or in the POST body, but not both at once.
  - A wrong or missing secret returns `401 invalid_client`, with `WWW-Authenticate: Basic` when Basic was used. A failed authentication does not consume the authorization code.
  - Public PKCE clients are unchanged. A secret sent by a public client is ignored, because ChatGPT Actions always sends one.
  - Authorization-server metadata now advertises all three methods.
- **Manual (pre-registered) confidential clients.** New `oauth_server/oauth/admin.py` provides `python -m oauth_server.oauth.admin register-confidential --client-id … --name … --redirect-uri …`. It ships in the remote_mcp image. `seed_oauth_clients.py register-confidential …` delegates to it.
  - The command prints the secret once and stores only its hash. Re-running it rotates the secret.
  - Redirect URIs must be https, or http on loopback only.
- **RFC 8707 `resource` parameter.**
  - Accepted on authorize (including the consent POST) and on token requests.
  - Must equal `https://<host>/mcp` after canonicalisation (lowercase host, default port and trailing slash dropped). Otherwise the server returns `invalid_target`: as a redirect from authorize, or a 400 from the token endpoint.
  - The resource is bound to the authorization code and refresh token; refresh keeps the binding.
  - Bound access tokens carry `aud: ["biomate-api", "<resource>"]`. `/mcp` rejects tokens bound to a different resource.
  - Requests that omit `resource` work exactly as before and get `aud: "biomate-api"`.
  - SQLite migration: `ALTER TABLE ... ADD COLUMN resource` runs on start-up for existing databases.
- **offline_access.** A requested `offline_access` scope is stripped before scope resolution. Refresh tokens were already always issued for the code flow, so this grants nothing extra. Requesting only `offline_access` now behaves like omitting `scope`, where previously it returned `invalid_scope`. Unknown scopes on their own (for example `openid admin:all`) still return `invalid_scope`.
- **Grant surface.** DCR clients whose redirect URI is on `*.benchling.com` get surface `benchling`, so their grants can be revoked per surface.
- **Behaviour change.** An unknown `client_id` at the token endpoint now returns `401 invalid_client`; it used to be `400 invalid_grant` on mismatch. MCP SDK clients treat this as "register again".

### Files changed (biomate-connector)
- `oauth_server/oauth/tokens.py`
- `oauth_server/oauth/store.py`
- `oauth_server/oauth/scopes.py`
- `oauth_server/oauth/server.py`
- `oauth_server/oauth/__init__.py`
- `oauth_server/oauth/router.py`
- `oauth_server/oauth/admin.py` (new)
- `remote_mcp/oauth_app.py`
- `remote_mcp/app.py`
- `seed_oauth_clients.py`
- `tests/test_oauth_server.py` (14 new tests)
- `tests/test_remote_mcp_oauth.py` (new, 8 HTTP-level tests)

### Tests
Run in a Python 3.11 venv with the Dockerfile's dependencies.
- **Full suite:** 342 passed, 13 failed, 29 skipped, 2 xfailed. The 13 failures are the same set as before the change: manifest/OpenAPI drift since the `identify_targets` commit, plus Feishu and Telegram tests that need `flask` and other dependencies not installed.
- **Remote MCP files:** `tests/test_oauth_tool_bridge.py` and `tests/test_remote_mcp_oauth.py` must run in their own pytest invocation (10 passed). Other test files import the repo's local `mcp/` package, which shadows the MCP SDK once it is in `sys.modules`. This collision existed before this change.
- **Smoke test:** `remote_mcp.oauth_smoke` against a local uvicorn `remote_mcp.run` passed all checks: DCR, PKCE, authorize, token plus refresh, 401 challenge, and MCP initialize with tools/list.

### Must still be verified against a real Benchling tenant
1. Which path Benchling takes: DCR, and with which `token_endpoint_auth_method`, or manual Client ID/Secret.
2. That it sends PKCE S256. PKCE is mandatory for every client here, per OAuth 2.1 and the MCP authorization spec.
3. The exact `resource` value Benchling sends, and whether "Suppress resource parameter" is needed.
4. The scope string Benchling requests.
5. Refresh behaviour after the 30-minute access-token expiry.
6. That the callback `https://<tenant>.benchling.com/1/api/llm/mcp/oauth/callback` round-trips. Redirect URIs are exact-matched at authorize and token; there is no production allowlist.
7. That `BIOMATE_OAUTH_DB` on dev and prod lives on a persistent volume, so DCR and manual clients survive container redeploys.

### Open items and recommendations (not changed)
- **Instrument tools are reachable on the cloud endpoint.** With `BIOMATE_MCP_TOOLS=*`, which the staging docs use, the remote server exposes `list_instruments`, `get_instrument_status` and `run_instrument_protocol`.
  - `remote_mcp/server.py:75` combined with `mcp/tools_manifest.py:897` `to_mcp()` does not filter `local_only`.
  - None of the three has a `_TOOL_SCOPES` entry (`remote_mcp/server.py:38`), so any OAuth token can call them.
  - They execute inside the cloud container against a caller-supplied `robot_ip` (`mcp/biomate_mcp_server.py:1463`). That is an SSRF surface, and `confirm=true` can actuate hardware.
  - Recommendation: exclude `local_only` tools from the remote endpoint unless an explicit on-prem flag is set, and add an `instruments:control` scope outside `DEFAULT_SCOPES`.
  - `identify_targets`, `get_quota` and `get_usage` also lack `_TOOL_SCOPES` entries.
- **Revocation endpoint is missing.** `revocation_endpoint` is advertised (`remote_mcp/app.py:118`), but no `/oauth/revoke` route exists on the remote app. Benchling's disconnect flow may call it.
- **DCR redirect-URI rules.** DCR accepts any http(s) redirect URI, including non-loopback `http://` (`remote_mcp/oauth_app.py:103`), and rejects custom schemes such as `cursor://`. Consider restricting to https or loopback, and confirm what Cursor's remote-MCP OAuth actually registers.
- **Resource binding on `/oauth/tools/{name}`.** That endpoint (`remote_mcp/tool_bridge.py`) does not check the resource binding. It is the same origin, so this is low risk.

## Campaign proposals: identical predicted scores (handoff open item 2)

### Diagnosis (with evidence)
Reproduced on the SYSUCC Case 3 fixture (`docs/qa/sysucc-usecases/assays_initial.csv` then `assays_safety.csv`; library `CCCC, CCCO, CCCN, CCCl`; 3 training compounds `CCO, CCN, CCC`), through `auto_retrain.refit_and_propose`.

- **Root cause: the Matérn length-scale collapses on binary fingerprints.** The fitted kernel was `Matern(length_scale=1e-05, nu=2.5)` in both rounds. That makes the kernel the identity matrix, so every unseen compound gets the prior mean with the prior standard deviation:
  - before the safety batch: mean 0.6364 for all four candidates (= mean of labels 1.0, 0.909, 0), std 0.4515;
  - after it: mean 0.3532 for all four, std 0.4580.
- **Why maximum likelihood collapses.** Euclidean distances between 2048-bit training fingerprints are about 2–2.8. The log marginal likelihood keeps increasing as the length scale shrinks: −8.21 at 3, −4.53 at 1, −4.27 at 0.5, and −4.257 at 1e-5. Any length scale long enough to correlate compounds must explain very different labels with one smooth function, so "every compound independent" wins.
- **The candidates are not indistinguishable.** Their Tanimoto similarities to the three training compounds range from 0.27 to 0.56, and candidates are at most 0.44 similar to each other.
- **Hypotheses ruled out:**
  - production fit/predict featurization mismatch: `fit_campaign_optimizer` uses `opt._featurise`, the same function as for the library;
  - near-duplicate candidates;
  - label scaling.
- **Contributing defects:**
  - Acquisition ignored uncertainty. With equal means, hypervolume improvement was 0 for every candidate, and `acquisition_values` (0.2, 0.125) were the diversity term alone.
  - The hypervolume box topped out at 1.0, which always equals the min–max-scaled best observed value, so for one objective the improvement could never be positive.
  - The seed used `hash(str)`, which is salted per process.
  - The no-RDKit fallback produced random vectors seeded per batch, so fit and predict saw different features for the same molecule.
  - `test_bo.py` fitted on random 256-dimension features and predicted on 2048-bit fingerprints. Baseline: 1 PASSED, 4 FAILED (sklearn `ValueError` on feature count).

### Changes
- **New `drug_discovery/fingerprint_surrogate.py`:**
  - `MorganFeaturizer`: radius 2, 2048 bits, using `rdFingerprintGenerator`. Bits are identical to the legacy `GetMorganFingerprintAsBitVect`. It reports unparsable SMILES and raises `ImportError` if RDKit is missing (no random fallback).
  - `TanimotoKernel`: parameter-free, positive semidefinite, matches RDKit `BulkTanimotoSimilarity`.
  - `TanimotoGP`: explicit label standardization and kernel `1.0 (fixed) × Tanimoto + White(noise ∈ [1e-4, 1])`. It returns latent mean and std, plus full covariance on request. `ConvergenceWarning`s are recorded and logged, not swallowed.
  - `assess_discrimination`: the maximum posterior P(f_i > f_j) over candidate pairs, using the joint covariance, with threshold 0.95.
  - Analytic expected improvement (EI) for one objective.
  - Monte Carlo expected hypervolume improvement (EHVI) for several objectives, using common random numbers: identical posteriors get identical acquisition, so Monte Carlo noise cannot create a ranking. The box extends beyond the observed front.
- **`bayesian_optimizer.py`:**
  - one shared featurizer, exposed as `featurise()` (`_featurise` kept as an alias);
  - `fit()` raises `ValueError` if `dataset.features` are not this featurizer's fingerprints of `dataset.smiles_list`, or if a training SMILES cannot be parsed;
  - one Tanimoto GP per objective;
  - acquisition uses mean and uncertainty (EI or EHVI), normalized, then combined with greedy Tanimoto diversity;
  - candidate screening excludes invalid SMILES, duplicate canonical structures and compounds already measured, each with a reason;
  - the current Pareto front comes from observed labels, not GP re-predictions;
  - scores are no longer clipped to [0, 1], because clipping can create ties;
  - deterministic SHA-256 seed;
  - new `RoundProposal.can_discriminate` and `surrogate_report`: kernel, featurizer, per-objective noise / log marginal likelihood / discrimination, excluded candidates, and warnings (`cannot_discriminate`, `small_training_set` (< 10), `constant_labels`, `noise_at_upper_bound`, fit warnings);
  - the report is persisted in a new `bo_proposals.surrogate_report_json` column (with an `ALTER TABLE` migration for existing tables) and returned by `load_proposals`;
  - `acquisition_values` now holds the raw EI/EHVI of each proposed compound; the combined selection scores are in `surrogate_report.selection_scores`;
  - removed the dead `_hypervolume_improvement` / `_tanimoto_distance`.
- **`test_bo.py`:** datasets are featurized by the optimizer under test. Added assertions:
  - per-candidate std > 0;
  - random labels are flagged as non-discriminating;
  - foreign 256-dimension features are rejected;
  - the surrogate report round-trips through the database.
- **New `drug_discovery/tests/test_bo_surrogate.py`:** 19 tests covering the kernel against RDKit, fixture non-collapse with ConvergenceWarning treated as an error, nearest-analogue ordering, the cannot-discriminate flag at n = 3, discrimination on an acid/non-acid signal, constant labels, identical scores for fingerprint-identical enantiomers, EHVI common random numbers, EI rewarding uncertainty, the feature-space guards, candidate screening, batch diversity, persistence and migration, and reproducibility.

### Before / after on the fixture (public `refit_and_propose` path)
| Round | Before | After | Max P(order) | `can_discriminate` |
|---|---|---|---|---|
| 1 (potency) | CCCC 0.636, CCCl 0.636 (std 0.452) | CCCO 0.695, CCCN 0.676 (std ≈ 0.40) | 0.597 | False |
| 2 (+ safety) | CCCC 0.353, CCCl 0.353 (std 0.458) | CCCN 0.498, CCCl 0.331 | 0.681 | False |

After the safety batch, CCCN (the analogue of the best compound, B = CCN at 0.955) now leads; previously it was tied. With three compounds the surrogate honestly cannot order the candidates at 95%, and the proposal says so. Control: 20 compounds with an acid / non-acid signal give acids 0.94 / 0.88 versus non-acids 0.28 / 0.13, max P(order) = 0.996, and `can_discriminate = True`.

### Tests
- `pytest` on `test_campaign_learning_loop.py`, `test_model_versioning.py` and `test_bo_surrogate.py`: **43 passed, 1 skipped**.
- `test_bo.py`: **40 PASSED, 0 FAILED** (was 1 / 4).
- `scripts/test_sysucc_usecases.py --output /tmp/sysucc_bo2.json`: **29 / 29 passed**, with 0 `ConvergenceWarning`s in the log.
- Python 3.9: the changed files parse with `ast.parse(feature_version=(3, 9))` and contain no PEP 604 annotations.
- The local anaconda python3.9 import check could not run: its scipy is broken (`scipy.interpolate` TypeError, reached via `galaxy.ai/__init__` → sentence_transformers → sklearn before the changed modules load). This is pre-existing and unrelated. scipy was already a hard dependency of sklearn.

### Needed outside this change (files owned by another agent; not edited)
- **`auto_retrain.py`:**
  - In `_insert_auto_proposal`, persist `proposal.can_discriminate` and `proposal.surrogate_report`, for example by merging `{"surrogate": proposal.surrogate_report}` into `training_report_json`, or via a new `surrogate_report_json` column.
  - Add the same fields to `AutoProposal`.
  - The `bo_proposals` ledger already stores them through `save_proposal`.
- **`api_router.py`:**
  - `propose_next_round` should return `can_discriminate` and `surrogate_report` (at least `objectives.*.discrimination`, `excluded_candidates` and `warnings`) next to `gp_stds`.
  - `_format_proposal` should add a proposal-level `can_discriminate` and per-item `std`, so the UI can show "too few data to rank" instead of implying an ordering.
  - Note: `n_proposed` can now be smaller than `n_propose` when library entries are excluded.

### Remaining gaps
- The 0.95 pairwise threshold and the "< 10 compounds" warning are policy choices, not calibrated values.
- The noise level is fitted by maximum likelihood (bounded to [1e-4, 1]). On clean labels it can reach the lower bound; that is reported as a warning.
- The applicability-domain checker is unchanged. With n = 3 its leverage threshold is not meaningful.
- No dev or authenticated verification (blocked as in open item 1). Nothing committed or synced.

## Assay data contract: censored values, salt forms, Benchling REST connector (handoff open item 3)

Not committed, not deployed. Nothing was tested against a live Benchling tenant; the Benchling tests use payloads shaped like the responses documented at docs.benchling.com (checked 2026-10-30/31: `/oauth/token`, `GET /assay-results` with `modifiedAt.gte` and `archiveReason`, `GET /molecules?ids=`, `GET /custom-entities:bulk-get`, V2 rate limits). The IND module was not touched.

### Root causes (pre-change line numbers, HEAD `c09f9bc77`)

- **Censored values ranked as exact:** `assay_ingestion.py:271` normalised every `value_uM` on the min/max range with no regard to `operator`, so IC50 `>10 uM` scored exactly like a measured 10 uM; `auto_retrain.build_training_rows` then used that score as a regression label.
- **Salt vs free base flagged as a conflict:** identity compared the whole canonical SMILES (`assay_schema.py:133`, `assay_ingestion.py:196`), so `CCN.Cl` and `CCN` under one ID were "two structures".
- **Benchling polling connector** (`drug_discovery/benchling_connector.py`): API key sent as Bearer (`:67`); default host `https://api.benchling.com/v2` (`:38`) with no tenant passed from the router (`api_router.py:1000`); `schema_id` optional (`:85`); compound ID/SMILES read from fields literally named `compound_id`/`smiles`, and the value from the *first numeric field* (`:165`); output keys `assay_name/assay_value/created_at` (`:185`) that the CSV validator rejects; silent mock mode when no key (`:56`, `:202`); API key accepted as a query parameter (`api_router.py:971`); review and archive status ignored; the router then wrote the rows to a temp CSV and read a non-existent `result.compounds_updated` attribute.

### Changes

**Censored values** (`assay_schema.py`, `assay_ingestion.py`)
- Operator kept; validated rows carry `censored`; `<`/`>` on binary flag endpoints (DILI/Ames/ClinTox) is rejected.
- Ranking: an unfavourable bound (IC50 `>X`, pIC50/solubility/hERG `<X`) contributes the worst normalised score (0) to `combined_score`; a favourable bound contributes its value. `combined_score_upper` (new column) is the at-best score, taking every bound at its value. hERG `<X` always takes the liability penalty in the conservative score. Normalisation ranges come from exact values only. At equal score, exact compounds rank first.
- Ranked compounds expose `objectives: {objective: {censored, censored_measurements}}` and `censored_objectives`; ingest returns a warning per censored compound.
- `auto_retrain.build_training_rows` (only this function): skips compounds with `censored_objectives`, reason `censored_value` (with the objectives), reported in `training_report.skipped`.

**Salt forms / parent structure** (`assay_schema.py`)
- `structure_identity()`: RDKit `rdMolStandardize.Cleanup` (disconnects covalent metal salts) → `SaltRemover` default list plus citrate, succinate, malate, lactate, formate, besylate, esylate, Zn/Al (list priority over size, so the oxalate in ethylamine oxalate is stripped) → `Uncharger`. If every fragment is a listed counterion, carbon-containing fragments are kept (sodium acetate → acetic acid).
- Identity is compared on the parent. Same parent, different submitted forms: accepted with a note. Different parents: conflict, as before. Several distinct non-counterion fragments (`CCO.CCCO`, co-drug, unlisted counterion): kept as a multi-component parent, flagged in `notes`, never collapsed; `A.B` vs `A` under one ID is a conflict.
- Rows store as-submitted `smiles`, plus `parent_smiles` and `structure_flags` (new columns; older rows get the parent computed on read). `build_training_rows` featurises `parent_smiles` and skips multi-component parents (reason `multi_component_structure`).

**Shared row-level path** (`assay_schema.py`, `assay_ingestion.py`)
- `read_assay_csv` + `AssayCSVValidator.validate_rows` (values may be numbers; `source_row` labels errors). `validate()`/`validate_csv()` are the CSV wrappers; `validate()` keeps its `(rows, errors)` return.
- `AssayIngestionService.ingest_rows` is used by `ingest()` (CSV) and the Benchling poll. Rows with `source_record_id` are upserted on `(source_system, source_record_id)` and report `ingested/updated/unchanged`. A replaced record is not checked against its own old structure. `retract_records()` deletes withdrawn records. A rerank now rewrites the whole ranking table, so retracted compounds drop out.

**Benchling connector, consolidated**
- `backend/lib/integrations/benchling_connector.py` is the single HTTP client:
  - OAuth client credentials via form POST to `https://{tenant}.benchling.com/oauth/token`. The token is cached and requested again 60 s before expiry; a 401 triggers one new token.
  - Personal API keys use Basic auth (`key:`); a raw key is never sent as Bearer.
  - A tenant URL is required and must be `https://<tenant>.benchling.com`; `api.benchling.com`, plain http and embedded credentials are rejected. `from_env()` reads `BENCHLING_TENANT_URL` (or `BENCHLING_API_URL`), `BENCHLING_CLIENT_ID`/`BENCHLING_CLIENT_SECRET` and `BENCHLING_API_KEY`.
  - Retries on 429/5xx and connection errors with exponential backoff and jitter, honouring `Retry-After`.
  - `list_all` follows `nextToken`, with `pageSize` ≤ 100.
  - `list_assay_results` requires `schemaId` and sends `archiveReason` (default `NOT_ARCHIVED`), `sort=modifiedAt:asc` and `modifiedAt.gte`. The documented endpoint has no entry filter, so `entry_id` filters client-side.
  - Compound lookups: `get_molecules` (`GET /molecules?ids=`, 100 IDs per call) and `get_custom_entities` (bulk-get).
  - The existing ELN, sample and push methods are unchanged, and the class name is kept.
- `drug_discovery/benchling_connector.py` is rewritten:
  - `BenchlingSchemaMapping` is explicit and validated, with unknown keys rejected. It configures:
    - the compound link field and its entity type (`molecule` or `custom_entity` plus a structure field, given as text SMILES or a molecule link);
    - the value field;
    - a fixed `assay_type` or an `assay_type_field` with a value map;
    - a fixed `unit` or a `unit_field` with a map;
    - the operator field and its map;
    - the date source (a field, `$createdAt` or `$modifiedAt`);
    - replicate, batch and run fields;
    - `review_policy` (default `reviewed_only`), `exclude_invalid` and `require_registered`.
  - `BenchlingAssayPoller` resolves links in bulk. The compound identity is `entityRegistryId`, and the structure is `canonicalizedSmiles`, which then goes through the salt/parent identity check.
  - Rows use the ingestion contract and carry provenance:
    - Benchling identifiers: result, schema, run, entry, project and creator IDs;
    - timestamps and review state: `createdAt`, `modifiedAt`, `isReviewed`, `validationStatus`;
    - compound: entity ID, registry ID and `originalSmiles`;
    - replicate, batch and tenant host.
  - Skip reasons: `not_reviewed`, `validation_invalid`, `archived`, `missing_compound_link`, `multi_compound_link`, `compound_not_found`, `unregistered_compound`.
  - The watermark is held at the oldest `not_reviewed` or `unregistered_compound` result. Re-reads are harmless because of the upsert.
  - Results archived since the watermark are listed with `ANY_ARCHIVED` and retracted.
  - `load_sync_state`/`save_sync_state` store the mapping and watermark per campaign and schema, keyed to the tenant host.
  - There is no mock mode.
- `api_router.py` poll endpoint (only that endpoint) is now `POST /{campaign_id}/lims/poll`:
  - Body: `mapping`, or `schema_id` to reuse the stored mapping, plus `since` and `full_resync`.
  - Credentials and the tenant come only from the server environment, so a caller cannot point server credentials at another host.
  - Secret-looking query parameters return 400 with a rotation hint.
  - Errors: 400 for a bad or missing mapping, 503 when the server is not configured, 502 for a Benchling error.
  - A changed mapping or tenant re-reads the schema from the start.
  - The response gives `records_ingested/updated/unchanged/retracted`, `skipped`, `errors`, `warnings`, `notes`, `watermark` and `updated_ranks`.

### Files changed
- `backend/lib/galaxy/ai/drug_discovery/assay_schema.py`
- `backend/lib/galaxy/ai/drug_discovery/assay_ingestion.py`
- `backend/lib/galaxy/ai/drug_discovery/benchling_connector.py` (rewritten)
- `backend/lib/galaxy/ai/drug_discovery/auto_retrain.py` (`build_training_rows` only)
- `backend/lib/galaxy/ai/drug_discovery/api_router.py` (`poll_lims` and its request model only; module docstring line)
- `backend/lib/integrations/benchling_connector.py`
- New tests:
  - `drug_discovery/tests/test_assay_censoring_and_salts.py` (26);
  - `test_benchling_connector.py` (38);
  - `test_benchling_poll_api.py` (5; needs FastAPI).

### Tests
- `/opt/homebrew/bin/python3 -m pytest` on the new suites plus `test_assay_report_fidelity.py`, `test_campaign_learning_loop.py` and `test_model_versioning.py`: 126 passed, 1 skipped (`test_benchling_poll_api.py` is skipped without FastAPI).
- `/tmp/biomate_api_venv`: `test_benchling_poll_api.py` + `test_model_versions_api.py`: 10 passed.
- `scripts/test_sysucc_usecases.py --output /tmp/sysucc_assay2.json`: 29/29 passed.
- Python 3.9:
  - The AST scan of all changed files found no PEP 604 annotations and no `match` statements.
  - `integrations.benchling_connector` imports under Anaconda 3.9.
  - The `galaxy.ai.drug_discovery` package cannot be imported there because Anaconda's numpy crashes with SIGFPE in `_mac_os_check`. This happens before any changed code runs and was already known.

### Remaining gaps
- **No live Benchling verification.** Before claiming the integration works, test it against a real tenant: token endpoint, `modifiedAt.gte` semantics, molecule `ids` lookup, and whether accepting an entry review changes a result's `modifiedAt`. The watermark-hold logic assumes it may not.
- The mapping is stored by the poll call. There is no separate mapping CRUD endpoint or UI, and no scheduler or webhook/EventBridge trigger.
- Not updated:
  - the frontend connection check in `routes.ts`, which still defaults to `https://benchling.com` and is owned by another session;
  - the manual pages that reference `GET …/lims/poll` (`reference/claude_design/.../I14-instruments-and-lab-connectivity.md`, the Benchling tutorials).
- Tenant hosts outside `*.benchling.com`, if any exist, are rejected.
- Salt and parent handling:
  - Counterions outside the list (meglumine, tromethamine, napsylate, …) leave a multi-component parent. This is flagged, not collapsed, so a free base vs such a salt is reported as a conflict.
  - Tautomers and stereo variants are not merged.
- Censoring:
  - The conservative score treats an unfavourable bound as the campaign's worst observed value.
  - Censored labels are excluded from regression rather than modelled (no Tobit or interval loss).
  - The BO/surrogate code (other agent) was not changed.
- Unreviewed or unregistered results hold the watermark until they become ingestible, so a result that never gets reviewed is re-read on every poll. The re-reads are idempotent but cost API calls.

## Remote MCP hardening: instrument tools, scopes, revocation, redirect URIs (biomate-connector)

**Date:** 2026-10-31. **Repo:** `/Users/kky/biomate-connector`. Not committed and not deployed. This follows up the open items in the "Benchling AI Connector readiness" section above.

### What changed
- **Local-only tools are off on the remote endpoint by default.** These are the manifest tools marked `local_only`: `list_instruments`, `get_instrument_status` and `run_instrument_protocol`.
  - They are removed from tool listing and from `/healthz`, even with `BIOMATE_MCP_TOOLS=*` or when listed by name (`remote_mcp/server.py` `enabled_tool_names`).
  - `tools/call` refuses them a second time as defence in depth.
  - The OAuth tool bridge (`/oauth/tools/{name}`) always answers 404 for them, because it proxies to the cloud backend, which cannot reach a lab.
  - An on-prem deployment opts in with `BIOMATE_MCP_ALLOW_LOCAL_TOOLS=1`. The policy lives in the new `remote_mcp/local_tools.py`.
- **Instrument host allowlist (SSRF guard).** With local tools enabled, every `robot_ip`, and every entry in `list_instruments.ips`, must be:
  - a bare IP address or hostname. Ports, paths, userinfo and fragments are rejected, because the OpenTrons connector builds `http://{robot_ip}:{port}` from the raw string;
  - and listed in `BIOMATE_MCP_INSTRUMENT_HOSTS`, which takes IPs, CIDR ranges or exact hostnames. An empty allowlist rejects every host.
- **New `instruments:control` scope** (`oauth_server/oauth/scopes.py`).
  - It is required for all three instrument tools and is not in `DEFAULT_SCOPES`.
  - On the cloud endpoint it is neither advertised (authorization-server and protected-resource metadata, DCR response) nor grantable (`OAuthServer(allowed_scopes=...)`). A request for it is narrowed away, and a request for it alone returns `invalid_scope`.
- **Every tool now has a required scope.** `identify_targets` requires `workflows:search`; `get_quota` and `get_usage` require `billing:read`. A tool without a mapping is refused (fail closed), and a test checks that every manifest tool has one.
  - Compatibility: claude.ai and other DCR clients get the default scopes, which include both. The ChatGPT OpenAPI requests `billing:read` and `workflows:search`.
  - The only tokens that lose access are ones granted a narrower set. Before this change those tools needed no scope on `/mcp` and returned 404 on the bridge.
- **`/oauth/revoke` (RFC 7009) is implemented.** It was advertised but missing.
  - It revokes refresh tokens, and access tokens through a JWT-ID deny-list (`revoked_access_tokens` table, purged as entries expire).
  - The deny-list is checked by both `/mcp` and the tool bridge (`OAuthServer.verify_access`).
  - Clients authenticate as at the token endpoint: Basic or POST secret for confidential clients, `client_id` for public clients. A missing or unknown client returns 401.
  - It only revokes tokens issued to the calling client. Unknown tokens, or tokens issued to another client, return 200 and change nothing.
  - `revocation_endpoint_auth_methods_supported` is advertised.
- **Redirect URI policy** (new `oauth_server/oauth/redirects.py`, shared by DCR and the admin CLI). Only `https` URIs, or `http` on a loopback host (`127.0.0.1`, `localhost`, `::1`), are accepted; fragments and malformed ports are rejected.
  - Custom schemes remain rejected; DCR rejected them before this change too.
  - Clients checked: the repo's installer uses `http://127.0.0.1:<port>/callback`, ChatGPT uses `https://chat.openai.com/...`, claude.ai and Claude Desktop use `https://claude.ai/api/mcp/auth_callback`, and Benchling uses https. No supported client in this repo registers a custom scheme.

### Files changed (biomate-connector, this pass)
- `oauth_server/oauth/scopes.py`
- `oauth_server/oauth/store.py`
- `oauth_server/oauth/server.py`
- `oauth_server/oauth/__init__.py`
- `oauth_server/oauth/admin.py`
- `oauth_server/oauth/redirects.py` (new)
- `remote_mcp/local_tools.py` (new)
- `remote_mcp/server.py`
- `remote_mcp/tool_bridge.py`
- `remote_mcp/oauth_app.py`
- `remote_mcp/app.py`
- `tests/test_oauth_server.py` (5 new tests)
- `tests/test_remote_mcp_oauth.py` (17 new tests)
- `tests/test_remote_mcp_local_tools.py` (new, 18 tests)

### Tests
- **Full suite** (excluding the remote MCP files): 347 passed, 13 failed, 29 skipped, 2 xfailed. The 13 failures are the same ones that failed before any of this work.
- **Remote MCP files**, run on their own because of the local `mcp/` shadowing issue that predates this work: 45 passed.
- **Smoke test:** a live uvicorn server with `BIOMATE_MCP_TOOLS=*` lists 22 tools and no instrument tools, and `remote_mcp.oauth_smoke` passes. `POST /oauth/revoke` without a valid client returns 401.

### Remaining gaps
- **Access tokens from a revoked refresh token stay valid.** Revoking a refresh token does not revoke access tokens already minted from it, because tokens carry no grant identifier. They expire within 30 minutes. RFC 7009 makes this cascade optional.
- **Admin-configured robot IPs bypass the allowlist.** `OPENTRONS_ROBOT_IPS`, if set, takes precedence in `list_instruments` discovery and is not checked against `BIOMATE_MCP_INSTRUMENT_HOSTS`. Set both consistently on-prem.
- **`run_id` goes into the URL path.** `get_instrument_status` interpolates `run_id` into the request path on an allowlisted robot. The impact is limited to that robot.
- **Cursor's remote-MCP OAuth redirect is unverified.** If Cursor registers a `cursor://` scheme, the remote endpoint rejects it today, as it did before this change. Verify with a real Cursor build before allowing a specific scheme and exact path.
- **The FastAPI backend router is unchanged.** Its `/oauth/revoke` still has no client authentication.

## Campaign proposals follow-up: ranking flag and uncertainty end to end

This follows the "Campaign proposals: identical predicted scores" section above. The fields `can_discriminate`, `surrogate_report` and per-compound std are now persisted, returned by every proposal endpoint, and shown in the UI.

### Changes
- **`auto_retrain.py`:**
  - `AutoProposal` gains `gp_stds`, `surrogate_report` and `can_discriminate`. `can_discriminate` mirrors `surrogate_report.can_discriminate` and is `None` for older rounds.
  - `auto_proposals` gains `gp_stds_json` and `surrogate_report_json`. `_init_tables` adds any missing columns with `ALTER TABLE`, so existing campaign databases load with `{}` / `None`.
  - `_insert_auto_proposal` and `_row_to_auto_proposal` write and read the new fields.
  - The other agent's `build_training_rows` changes are untouched.
- **`bayesian_optimizer.py`:** `surrogate_report` now carries `n_requested`, `n_proposed` and a `fewer_than_requested` warning when exclusions leave fewer usable library entries than requested.
- **`api_router.py`:**
  - `POST /{id}/propose` returns `n_requested`, `can_discriminate` and `surrogate_report`.
  - `POST /{id}/retrain` returns `gp_stds`, `can_discriminate` and `surrogate_report`.
  - `_format_proposal`, used by `POST /retrain/trigger`, the legacy `GET /retrain` and `GET /auto-proposal`, adds a per-item `std` (`null` for older rounds) plus proposal-level `can_discriminate` and `surrogate_report`.
  - The CSV export gains a `std` column. Without it, `csv.DictWriter` would have raised on the new key.
  - The Benchling poll endpoint is untouched.
- **`frontend/client/src/components/drug-discovery-auto-retrain.tsx`** (the only UI consumer of proposals):
  - new exported `ProposalRankingNotice`, an amber notice in the component's existing alert style with `data-testid="proposal-cannot-rank"`;
  - it shows "Too few data to rank" with the best pairwise confidence and the training-set size when `can_discriminate === false`;
  - nothing is shown when the flag is true or null;
  - the score cell's tooltip shows the posterior std.

### Tests
- New `tests/test_campaign_proposals_api.py` (FastAPI `TestClient`, no mocks of BioMate services):
  - `/propose` on a 16-compound acid/non-acid campaign: `can_discriminate = True`, acids outrank non-acids, 5 of 6 requested proposed with `fewer_than_requested`;
  - `/retrain`, `/retrain/trigger`, `/auto-proposal` (JSON and CSV) on the 3-compound Case 3 fixture: `can_discriminate = False`, and every item has `std > 0`.
- `test_campaign_learning_loop.py`, 4 new tests:
  - the flag, report and stds persist and reload;
  - the requested-versus-proposed shortfall is reported;
  - a legacy `auto_proposals` table is migrated;
  - `_format_proposal` returns `std` and the flag, with `None` for legacy rows.
- New `drug-discovery-auto-retrain.test.tsx` (2 tests).
- **Results:**
  - API venv (`test_bo_surrogate`, `test_campaign_learning_loop`, `test_model_versioning`, `test_campaign_proposals_api`, `test_assay_censoring_and_salts`, `test_benchling_poll_api`): **81 passed**.
  - Homebrew Python, non-API suites: 72 passed, 2 skipped.
  - `test_bo.py`: 40 / 40.
  - `scripts/test_sysucc_usecases.py`: **29 / 29**. The fixture rounds give `CCCO 0.6945 / CCCN 0.6758` then `CCCN 0.4978 / CCCl 0.3311`, both `can_discriminate = False`, with 0 `ConvergenceWarning`s.
  - `tsc --noEmit`: clean.
  - Full `vitest`: 173 files, 2001 tests passed.
  - Python 3.9 AST check on the changed backend files: clean.

### Known gaps
- `POST /{id}/propose` still uses the optimizer's default `n_initial = 16`, while `/retrain` uses `max(2, n)`, so the same 3-compound campaign returns 422 from `/propose` and an exploratory, flagged proposal from `/retrain`. This is a pre-existing policy difference, left unchanged. Now that small data are flagged explicitly, aligning `/propose` on the flag is a reasonable follow-up.
- Two `POST /{id}/virtual-library` routes are registered in `api_router.py` (pre-existing); FastAPI serves the first one.
- The UI change is covered by the component vitest only. There is no Playwright or dev screenshot audit (dev auth is still blocked, per open item 1). Nothing committed or synced.
