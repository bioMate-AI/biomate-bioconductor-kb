# Instruments & lab connectivity (hospital / wet-lab integration)

> One-line promise: after this page you know exactly which instrument and LIMS integrations BioMate can
> really do today, how each one is reached, and — just as important — what is **not** yet a point-and-click
> feature in the app. For developers, lab-core admins, and drug-discovery teams (not an end-user walkthrough).

<!-- Every capability here is code-verified (tier C, source-read); see the citations inline. No in-app
     instrument UI exists, so this chapter carries no product screenshots — that absence is itself a verified
     fact (grep for "instrument" in frontend/client/src returns zero hits). -->

## Read this first — the honest headline

BioMate's instrument-connector **code is real and substantial** — genuine device and API clients, not
stubs. But today it is **almost entirely back-end plumbing and ops tooling: there is no in-app instrument
screen.** The "Connectors" dialog an end-user sees (chapter I.12) holds **databases and AI/platform
integrations only — zero instruments**, and no React code anywhere consumes the instrument API
(`grep -ri instrument frontend/client/src/` → no hits; the instrument routes in
`frontend/server/routes.ts:16028-16364` have no front-end caller).

So **do not** tell a user "open Connectors, add your sequencer, and data flows into your workspace" — that
UI does not exist. What genuinely works today is three things, described below. This is the real meaning of
the long-standing "the gap is the closed design–build–test–learn loop" note: the wiring exists, but it is
reached through MCP, an API, or an admin deployment — not an in-app button.

## What genuinely works today

### 1. OpenTrons liquid-handling robots — via MCP (the one user-facing path)

The only instrument capability a user can drive directly is **OpenTrons OT-2 / Flex** control through
BioMate's **MCP tools** — `list_instruments`, `get_instrument_status`, and `run_instrument_protocol` —
from an MCP client (Claude Desktop, Cursor, etc.).

- These tools wrap a **real REST client**, `backend/lib/integrations/opentrons_connector.py`: a
  `requests.Session` against the robot's HTTP API — `health_check` (`:62`), `list_protocols` (`:100`,
  `GET /protocols`), `upload_protocol` (`:106`, `POST /protocols`), `start_run` (`:140`, `POST /runs` then
  `POST /runs/{id}/actions`), and `get_run_status` (`:172`). This is genuine device control, not a mock.
- **They run on the local network.** `list_instruments` discovers robots by scanning or by
  `OPENTRONS_ROBOT_IPS`; the MCP server must sit on the same LAN as the robot. With no robot reachable,
  the tools return an empty discovery — correctly, not an error.
- The MCP tool *implementations* live outside this repo (in the MCP server package); this chapter documents
  the connector they drive, which is in-tree and verified.

**Honest scope:** real and demonstrable, but it needs (a) a physical OT-2/Flex and (b) an MCP client on the
lab network. It is not reachable from the web app.

### 2. Benchling LIMS → compound ranking — the one closed wet-lab loop

For drug-discovery campaigns there is a **genuinely closed loop**: assay results pulled from Benchling LIMS
feed back into compound ranking.

- Route: `GET /api/drug-discovery/{campaign_id}/lims/poll` (`backend/lib/galaxy/ai/drug_discovery/api_router.py:827`,
  `async def poll_lims`), which calls `AssayIngestionService` (`:449` onward) to ingest results and re-rank
  compounds.
- The Benchling client itself is real (`backend/lib/integrations/benchling_connector.py` — Benchling REST v2
  GET/POST/PATCH). A second, campaign-side client
  (`backend/lib/galaxy/ai/drug_discovery/benchling_connector.py`) has an explicit `mock_mode` that returns
  synthetic data **only when no API key is set**, and uses the real HTTP path when keyed.

**Honest scope:** this is the real "test → learn" step of the DBTL loop, and it is code-complete — but it is
**triggered via the API / MCP, not a button.** In the web UI the CRO/drug-discovery surface shows only a
**static label** "LIMS & sample tracking" (`frontend/client/src/components/domain-profile-selector.tsx:172`)
and a "LIMS Sync" string (`locales/en/common.json:201`); neither issues the poll. A user cannot start this
from the app today.

### 3. Self-hosted connectors & the directory watcher — an admin deployment

For sequencers, mass-spec, plate readers, qPCR, flow cytometers, and cryo-EM, BioMate ships **real
file-watcher / API connectors** meant to run **on the lab's own server**, not in the cloud app:

- `backend/lib/integrations/instrument_watcher.py` — a standalone daemon (`__main__`) that watches
  NFS/S3/local directories for instrument output (`.mrc/.pod5/.fast5/.fastq.gz/.mzML/.raw`), waits for a
  file to settle, and POSTs a notification to `{BIOMATE_API_URL}/api/instruments/new-data` (`:123-139`).
  It is **not started by the running app** — an operator deploys it (systemd/Docker) alongside the
  instrument.
- The per-device connectors are all real (no stubs in `backend/lib/integrations/`): `nanopore_minknow`
  (MinKNOW HTTP), `illumina_basespace` (OAuth2 + BaseSpace API), `lcms`, `qpcr`, `flow_cytometer`,
  `plate_reader` (file parsers that POST to `/api/instruments/new-data`), and `cryoem_instrument` (EPU +
  watchers). The cryo-EM connector is the one imported by the separate **Unified Instrument Service**
  (`backend/lib/galaxy/instruments/service/main.py`), deployed via its own compose file, which parses files
  → S3 → a Galaxy dataset.
- The receiving side is real server infrastructure: `POST /api/instruments/new-data` (`routes.ts:16031`),
  `GET /api/instruments/events` (`:16079`), full `/api/instruments` CRUD (`:16125-16252`), and a **live**
  `GET /api/instruments/:id/health` connectivity check (`:16256`). Backed by `instruments` /
  `instrument_events` tables.

**Honest scope:** a lab admin can stand this up so instrument files land as events server-side. But — again —
**nothing in the web UI yet lists those instruments, shows those events, or launches a workflow from them.**
Some of this stack ships from a separate repo (`biomate-connectors-v2`, referenced at
`frontend/shared/schema.ts:1562`), so treat it as an advanced add-on, not a core-app feature.

## How it fits a run

Where a connector *is* wired to compute, the data path is: instrument → event / ingestion → (server) →
dataset or ranking. For OpenTrons it is MCP → robot → status back to the chat. For Benchling it is
poll → `AssayIngestionService` → re-ranked compounds in the campaign. For the self-hosted watchers it is
file → `/api/instruments/new-data` → an `instrument_events` row (and, via the Unified Instrument Service,
an S3 upload + Galaxy dataset). The provenance of anything that reaches a workflow is then recorded the same
way as any other run (see I.7 / I.9).

### Worked example — from a bench instrument to an immunology readout

Tie the connector to a real analysis use case — what a rheumatology/immunology lab actually does:

- **Flow cytometer → immunophenotyping.** The `flow_cytometer` watcher settles each `.fcs` export and POSTs
  it to `/api/instruments/new-data` → an `instrument_events` row (and, via the Unified Instrument Service, an
  S3 upload + a Galaxy dataset). That FCS dataset feeds the catalog's flow-cytometry workflows — **`flowcore`**
  (compensation → fluorescence transform → manual gating; real-execution-verified) or
  **`analyze_flow_cytometry_immunophenotyping`** (a gating strategy → marker-positive population
  quantification, e.g. CD-marker⁺ B-cell / NK subsets). The chat-driven analysis half is live today; the
  automatic instrument→dataset hop is the admin-deployed watcher above.
- **ELISA plate reader → soluble-ligand titers.** The `plate_reader` connector lands OD tables;
  **`analyze_ebv_antibody_titers`** fits a standard curve and quantifies titers across sample groups — the
  same soluble-protein-ELISA → titer → group-comparison pattern used for soluble checkpoint-ligand
  biomarkers. It is self-contained on its built-in demo data: try the cold-start **"EBV antibody titers
  (ELISA)"** example before wiring a real plate reader.
- **LC-MS → proteomics / metabolomics.** The `lcms` watcher lands `.mzML/.raw`; the proteomics/metabolomics
  workflows (e.g. `metaboanalystr`) take it from there.

> **Honest split.** The *analysis* workflows are in the catalog and runnable from chat today; the *automatic
> instrument → dataset* ingestion is the admin-deployed watcher (no in-app instrument registry yet — see
> "What's not covered"). For a demo, drive the analysis from a cold-start example; for a production lab, an
> admin stands up the watcher so exports flow in without manual upload.

## Pitfalls & tips

> **Pitfall — the Connectors dialog is not the instrument surface.** I.12's dialog manages databases and
> LLM/platform integrations. Instruments are reached only by MCP, the drug-discovery API, or an admin
> deployment — there is no instrument tab, registry, or event feed in the app today.

> **Tip — check residency / network before you wire a device.** OpenTrons MCP and MinKNOW are
> **local-network** by design; the MCP server or watcher must be able to reach the instrument. A cloud-only
> deployment cannot see a bench instrument.

> **Tip — Benchling without a key returns synthetic data.** The campaign-side client's `mock_mode` activates
> when no API key is set; set a real key before trusting any assay-ingestion result.

## What's not covered (because it isn't built yet)

- **An in-app instrument registry / dashboard / event feed.** The API and tables exist; no React screen
  consumes them. This is the single biggest gap for a layman "connect your hospital instrument" experience.
- **An in-UI "launch workflow from instrument data" button.** The ingest path exists server-side; the
  one-click close of the loop in the app does not.
- **A user-facing LIMS poll control.** The route is real; the UI shows only a static label. (→ capability
  gap, not a documentation gap.)
- **MCP tool internals for non-OpenTrons devices.** `list_instruments` et al. are OpenTrons-only today.

> **Product note (for the roadmap, not the user):** the honest, high-value next step to make a true
> "hospital-instrument tutorial" possible is to **surface the existing instrument API in the UI** — a
> registry + event feed + "launch from event" — and a UI trigger for the Benchling LIMS poll. The back end
> is already there; the front door is missing. Until then, any instrument tutorial must be framed as the
> advanced/ops capability it is, exactly as this chapter does.

---
_Verification: all claims source-read (tier C); citations inline. No Batch runs and no product screenshots —
there is no instrument UI to capture, which is itself the chapter's central finding._
