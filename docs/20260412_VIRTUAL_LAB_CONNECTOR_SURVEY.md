# 2026-04-12 — Virtual Lab Connector Survey

## Overview

This document surveys open-source robot APIs, cloud lab APIs, LIMS APIs, sequencer APIs,
and lab automation frameworks relevant to BioMate's "virtual lab" vision.

**The virtual lab goal**: A researcher describes an experiment → BioMate generates a protocol
→ a robot/cloud lab executes it → BioMate ingests the output data → analysis runs automatically.

**Ranking criteria (1–5):**
- **Open-source score**: Is the API/SDK open source? Is the device open?
- **Pilot relevance**: Do BioMate pilot users have this device in their lab?
- **API quality**: REST > gRPC > file-based > vendor proprietary
- **Effort estimate**: Days to a working BioMate connector

---

## Category 1: Open-Source Liquid Handlers

### OpenTrons OT-2 / Flex ★★★★★

| Property | Value |
|----------|-------|
| Open-source score | 5/5 (SDK fully open, hardware designs public) |
| Pilot relevance | 5/5 (most common liquid handler in academic labs) |
| API quality | 5/5 (local HTTP REST API on port 31950, JSON-RPC for protocol upload) |
| Effort estimate | 2 days |
| BioMate connector | ✅ Implemented: `backend/lib/integrations/opentrons_connector.py` |

**API summary**:
- `GET /health` → robot info, firmware version
- `POST /protocols` (multipart) → upload Python protocol file → returns `protocol_id`
- `POST /runs` → create run from protocol → returns `run_id`
- `POST /runs/{run_id}/actions` `{"actionType": "play"}` → start run
- `GET /runs/{run_id}` → status (idle / running / paused / succeeded / failed)
- Robot simulator: `pip install opentrons` includes a simulated OT-2 for testing

**BioMate integration**:
1. User: "Run a serial dilution in 96-well plate"
2. BioMate AI generates a valid OT-2 Python protocol
3. `opentrons_connector.upload_protocol()` → robot
4. `opentrons_connector.start_run()` → runs on robot
5. Results (absorbance CSV, etc.) pulled from robot; BioMate ingests

---

### Opentrons Protocol Library (open)

Hundreds of validated protocols at `protocols.opentrons.com`. BioMate can:
- Search and retrieve matching protocols by assay type
- Adapt parameters (volumes, labware) using LLM
- Upload directly to robot without writing code from scratch

---

### LabOP / PAML (open protocol language)

| Property | Value |
|----------|-------|
| Open-source score | 5/5 (W3C-style open standard) |
| Pilot relevance | 2/5 (academic niche, not yet widely deployed) |
| API quality | 3/5 (SPARQL execution, Python SDK exists) |
| Effort estimate | 5 days |

LabOP (Laboratory Open Protocol Language) is a W3C-inspired semantic protocol language.
A LabOP program describes "what to do" device-independently; execution engines translate
to device-specific commands (OpenTrons, Hamilton, etc.).

**Value for BioMate**: Write one LabOP protocol, execute on multiple robot types.
The `labop` Python library can compile LabOP → OpenTrons protocol directly.

---

## Category 2: Cloud Lab / CaaS (Contract Automation as a Service)

### Strateos (formerly Transcriptic) ★★★★

| Property | Value |
|----------|-------|
| Open-source score | 3/5 (Autoprotocol standard is open; API itself is SaaS) |
| Pilot relevance | 3/5 (pharma/biotech users, not academic) |
| API quality | 4/5 (REST, JSON-based Autoprotocol format) |
| Effort estimate | 3 days |
| BioMate integration path | POST Autoprotocol JSON → Strateos runs → pull results via API |

Strateos uses the **Autoprotocol** format (open standard: `autoprotocol.org`).
BioMate AI can generate Autoprotocol JSON from natural language descriptions,
post to Strateos API, and retrieve results when the cloud lab completes the run.

**Authentication**: API key (`STRATEOS_API_KEY` env var)
**Endpoints**: `POST /projects/{id}/refs`, `GET /runs/{run_id}`, `GET /runs/{run_id}/data`

---

### Emerald Cloud Lab ★★★

| Property | Value |
|----------|-------|
| Open-source score | 2/5 (proprietary, but Constellation language is documented) |
| Pilot relevance | 2/5 (pharma focus) |
| API quality | 3/5 (StellarScript DSL, REST for status) |
| Effort estimate | 5 days |

---

### Arctoris ★★★

| Property | Value |
|----------|-------|
| Open-source score | 2/5 |
| Pilot relevance | 3/5 (growing biotech usage) |
| API quality | 4/5 (REST API, JSON protocols) |
| Effort estimate | 3 days |

---

## Category 3: LIMS / ELN Partners

### Benchling ★★★★★

| Property | Value |
|----------|-------|
| Open-source score | 2/5 (SaaS, but REST API is fully documented) |
| Pilot relevance | 5/5 (dominant in pharma/biotech; many pilot users) |
| API quality | 5/5 (comprehensive REST API, OAuth2, webhooks) |
| Effort estimate | 2 days |
| BioMate connector | ✅ Implemented: `backend/lib/integrations/benchling_connector.py` |

**Key endpoints used**:
- `GET /api/v2/entries` → notebook entries (experiment context)
- `GET /api/v2/samples` → compound/sample inventory  
- `POST /api/v2/assay-results:bulk-create` → upload BioMate results
- `GET /api/v2/projects` → project list for context

**BioMate integration value**: Benchling-managed labs can use BioMate as the
computational backend: pull compound lists from Benchling, run ADMET/docking,
push ranked results back as assay results — all without leaving either platform.

---

### SENAITE (open-source LIMS) ★★★★

| Property | Value |
|----------|-------|
| Open-source score | 5/5 (Plone-based, AGPLv3) |
| Pilot relevance | 3/5 (clinical labs, environmental) |
| API quality | 4/5 (REST JSON API via `plone.restapi`) |
| Effort estimate | 3 days |

Supports 60+ instrument interfaces. BioMate can:
- Pull sample worksheets and analytical requests
- Push calculated results back
- Relevant for clinical genomics / environmental monitoring labs

---

### OpenELIS Global 2 ★★★

| Property | Value |
|----------|-------|
| Open-source score | 5/5 (Apache 2.0) |
| Pilot relevance | 2/5 (low-resource clinical settings) |
| API quality | 3/5 (FHIR endpoints + custom REST) |
| Effort estimate | 4 days |

---

## Category 4: Sequencer Data APIs

### Illumina BaseSpace ★★★★

| Property | Value |
|----------|-------|
| Open-source score | 2/5 (SaaS, but SDK is open: `github.com/illumina/basespace-python-sdk`) |
| Pilot relevance | 5/5 (near-universal in genomics labs) |
| API quality | 4/5 (OAuth2, REST, FASTQ download) |
| Effort estimate | 3 days |

**Flow**:
1. OAuth2 browser flow → user grants BioMate access to their BaseSpace account
2. `GET /v1pre3/projects` → list sequencing projects
3. `GET /v1pre3/runs` → list completed sequencing runs
4. `GET /v1pre3/files/{id}/content` → download FASTQ files to S3
5. BioMate auto-suggests WGS/RNA-seq workflow based on run metadata (sample sheet)

**Auth endpoints**:
- `GET https://api.basespace.illumina.com/oauth/authorize`
- `POST https://api.basespace.illumina.com/oauth/token`

---

### Nanopore MinKNOW REST API ★★★★

| Property | Value |
|----------|-------|
| Open-source score | 3/5 (MinKNOW itself is proprietary; `minknow-api` Python gRPC client is open) |
| Pilot relevance | 4/5 (Oxford Nanopore common in genomics labs) |
| API quality | 4/5 (gRPC + local HTTP health endpoint) |
| Effort estimate | 3 days |

**Flow**:
1. BioMate connects to local MinKNOW instance (`http://localhost:9501`)
2. `GET /positions` → list flow cells, find active run
3. Poll run status; when complete, ingest POD5/FAST5 files from local disk
4. Auto-suggest basecalling workflow (Guppy/Dorado)

---

### PacBio SMRT Link ★★★

| Property | Value |
|----------|-------|
| Open-source score | 2/5 |
| Pilot relevance | 3/5 |
| API quality | 3/5 (REST API, OAuth2) |
| Effort estimate | 4 days |

---

## Category 5: Lab Device Protocols

### SiLA2 (Standardized in Lab Automation) ★★★

| Property | Value |
|----------|-------|
| Open-source score | 4/5 (open standard, `sila-python` library is open) |
| Pilot relevance | 2/5 (mostly high-end pharma/CRO automation) |
| API quality | 4/5 (gRPC, protobuf schemas per device) |
| Effort estimate | 5 days |

SiLA2 is an IEC standard for lab instrument communication. A single SiLA2 adapter
can theoretically talk to any SiLA2-compliant device (Hamilton, Tecan, centrifuges,
plate readers). Devices expose typed gRPC endpoints.

**Python SDK**: `pip install sila2` (sila-python library)
**Devices with SiLA2 support**: Hamilton STAR line, Tecan Fluent, some Thermo Fisher
devices, several plate readers and centrifuges.

---

### Hamilton VENUS REST Add-On ★★

| Property | Value |
|----------|-------|
| Open-source score | 1/5 (proprietary, REST add-on is commercial) |
| Pilot relevance | 3/5 (common in pharma automation) |
| API quality | 3/5 (REST, JSON) |
| Effort estimate | 4 days |

---

## Category 6: Flow Cytometry

### FlowJo + FCS Format ★★★

| Property | Value |
|----------|-------|
| Open-source score | 3/5 (FCS format is open; FlowJo has API; `fcsparser` Python is open) |
| Pilot relevance | 4/5 (immunology labs universal) |
| API quality | 3/5 (file-based FCS + FlowJo API) |
| Effort estimate | 3 days |

BioMate can:
1. Accept `.fcs` file upload
2. Parse with `fcsparser` Python library
3. Run gating / dimensionality reduction workflow (UMAP, tSNE, Leiden clustering)
4. Return annotated cell population summaries

---

## Ranked Summary

| Connector | Priority | Effort | Status |
|-----------|----------|--------|--------|
| OpenTrons OT-2/Flex | P1 | 2 days | ✅ Implemented |
| Benchling LIMS/ELN | P1 | 2 days | ✅ Implemented |
| Illumina BaseSpace | P1 | 3 days | Not yet |
| Nanopore MinKNOW | P2 | 3 days | Not yet |
| Slack bot | P1 | 2 days | ✅ Implemented |
| Strateos (cloud lab) | P2 | 3 days | Not yet |
| SENAITE (open LIMS) | P2 | 3 days | Not yet |
| FlowJo/FCS | P2 | 3 days | Not yet |
| SiLA2 generic adapter | P3 | 5 days | Not yet |
| LabOP protocol language | P3 | 5 days | Not yet |
| PacBio SMRT Link | P3 | 4 days | Not yet |
| Hamilton VENUS | P4 | 4 days | Not yet |
| Emerald Cloud Lab | P4 | 5 days | Not yet |

---

## File Watcher: CryoEM Auto-Ingestion

A lightweight daemon watches an NFS/S3 prefix for new `.mrc` / `.tif` files from
a Titan Krios (or other cryo-EM) and triggers the CryoSPARC SPA workflow automatically.

Already partially covered by BioMate's Cryo-EM module (`.mrc` upload handling).
The file watcher extension would:
1. `fsnotify` or S3 event trigger on new `.mrc` files
2. Create a BioMate session, attach files
3. Pre-fill `movies_path` parameter
4. Send a notification: "New cryo-EM data detected — click to run CryoSPARC SPA"

Implementation: `backend/lib/integrations/file_watcher.py` — 1 day.
