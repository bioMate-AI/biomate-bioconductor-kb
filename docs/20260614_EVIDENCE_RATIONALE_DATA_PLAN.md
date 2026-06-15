# Evidence-supported phase rationale — data collection plan

Date: 2026-06-14
Branch: `bioc/v2-qc-audit-panel`
Drives: the `(why?)` anchor feature (L in the v2 closure plan).

## What the Claude design actually does

Source files (audited):
- `reference/claude_design/research_agents/src/research-data.js`
- `reference/claude_design/research_agents/src/ChatStream.jsx`

Pattern:

1. **Chat event opts in.** Each chat event in the scenario tape that
   warrants a `(why?)` anchor carries a `rationaleId` string:
   ```js
   { kind:'chatLine', s:'wf', m:'Step 2/5: STAR alignment…',
     rationaleId: 'rnaseq:B' }
   ```
   Lines without a `rationaleId` get no anchor — the designer chooses
   per-line which decisions are worth surfacing.

2. **Single in-process registry.** `window.RESEARCH_PHASE_TRACE` is a
   static JSON object indexed by `rationaleId`. Per the file
   research-data.js:571+, each entry has **4 sections**:
   ```js
   'rnaseq:B': {
     rationale: { text: '…',  cite: { title, href } },
     events:    [ { ts, s, m }, …  ],   // live event log
     params:    [ { k, v, tag }, … ],   // values w/ default|edited|user|autoloop tag
     cost:      { used, est, vcpuh }    // (commented out today, leaving for future work)
   }
   ```

3. **Hover dispatches lookup.** ChatStream.jsx:30 does
   `(window.RESEARCH_PHASE_TRACE[line.rationaleId] || {}).rationale` —
   pure client-side, no fetch.

4. **UX is 4-section popover.** "Why this method · Live events ·
   Parameters · Cost" — text · log · table · numbers. Not just text.

## What I shipped this session (L week-1 to week-3)

| Layer | Design intent | What I built |
|---|---|---|
| Per-line tagging | `rationaleId` opt-in per line | Component mounts on **every** progress line, silently hides when DB has no row |
| Lookup | Static JSON in process | DB table + REST endpoint with per-hover fetch |
| Content shape | 4 sections (rationale, events, params, cost) | 1 section (rationale_text + citation) |
| Data source | `RESEARCH_PHASE_TRACE` in research-data.js | `workflow_phase_rationale` table, populated from BiocTours.jsx + qc_evidence.yaml |
| Coverage | 5 scenarios (rnaseq:B/C, drugscreen:B, variant:B), curated | 24 bioc chain rows (curated) + auto-extraction for ~80 other chains (dry-run only — not committed) |

## Discrepancy summary

1. **Tagging.** Real dev backend doesn't emit `rationaleId` on any SSE
   chat_progress event today. My WhyAnchor renders nothing on real
   runs even after L week-3.
2. **Content shape.** I shipped 1 of 4 design sections. Live events
   and parameters tables are missing entirely.
3. **Coverage path.** I built bottom-up from chain rows; design works
   top-down from per-event opt-in.

## What evidence has to be collected

For the design pattern to function on real dev runs, every "step-decision"
chat event needs an explicit `rationaleId` tag, and a registry that
resolves that id to four blocks of evidence.

### Required per-event metadata (producer side)

The backend chain runner needs to set on each emitted chat event:

| field | type | source | notes |
|---|---|---|---|
| `technical.rationale_id` | str | curated, per chain step | e.g. `'bulk_rnaseq:B'`, `'methyl:D'`, `'cryosparc:A'`. Domain prefix + phase letter, stable across runs. Absent → no anchor on the line. |
| (everything else stays as today: phase_name, n, of, …) |

This is a **content decision per chain step**, not auto-derivable. The
chain curator writes it once when authoring the chain row.

### Required per-rationale_id content (registry)

For each `rationale_id`, we collect 4 blocks (matching design):

| block | required fields | source of truth | gathering cost |
|---|---|---|---|
| **rationale** | `text` (1–2 sentences) + `citation_doi` + `citation_title` | Curated. For bioc chains, lift verbatim from `BiocTours.jsx` body literals. For cryo, use the CRYOSPARC pipeline curator's docs. For admet, the ADMET FDA guidance. **No invention.** | ~2 min per phase from curator |
| **events** | array of `{ts, speaker, message}` | Auto-collected at runtime from the SSE stream — backend already emits these; we just persist the last N per phase per invocation. | 1 backend feature: dump last 12 events per phase per invocation_id |
| **params** | array of `{k, v, tag: 'default' \| 'edited' \| 'user' \| 'autoloop'}` | The chain runner already knows. `tag` distinguishes manifest values from user overrides. Backend needs to expose. | 1 backend feature: extend nextflow_executor params endpoint to include source tag |
| **cost** | `{used, est, vcpuh}` (currently commented out in design) | Lago billing already tracks per-job vCPU-hours; just need to surface per phase. | 1 backend feature: pull from billing records by invocation+phase |

### Required schema

Replace my current `workflow_phase_rationale` with a more design-faithful
shape:

```sql
CREATE TABLE rationale_registry (
  rationale_id    TEXT PRIMARY KEY,     -- e.g. 'bulk_rnaseq:B'
  rationale_text  TEXT NOT NULL,
  citation_doi    TEXT,
  citation_title  TEXT,
  applies_to_workflow_name TEXT,        -- ranged lookup ("any bulk_rnaseq_* chain")
  last_curated_at INTEGER NOT NULL
);

-- The events + params + cost blocks come from existing runtime data,
-- joined at endpoint time by invocation_id (when hovering on a line
-- from an in-progress / completed run).
```

The endpoint becomes:
```
GET /api/rationale/:rationale_id?invocation_id=…
→ {
    rationale: { text, citation: {doi, title} },
    events:    [ … last N for this invocation+phase … ],
    params:    [ … from chain runner … ],
    cost:      { … from Lago when available … }
  }
```

## Phased plan — what's worth doing, in order

### Phase 0 — concede the divergence (this doc)

Acknowledge L week-1..3 doesn't fire on real dev runs without producer-
side tagging. Don't pretend it works.

### Phase 1 — minimum viable opt-in tagging (2 BE-days)

- Extend `backend/lib/galaxy/ai/workflow_ops/workflow_chat_narrator.py` to
  accept + forward a `rationale_id` field in `technical`.
- Author + commit `rationale_registry` table (per schema above) +
  populate from the 4 bioc chains using BiocTours.jsx + qc_evidence.yaml
  (extends my existing populate script).
- Backend chain runner: for the bioc chains, tag each phase_started
  event with the corresponding `rationale_id`.

### Phase 2 — frontend mirror of design (1 FE-day)

- Update `<WhyAnchor>` to expect `rationaleId` instead of inferring
  `workflowName + phaseId`.
- Update chat-message.tsx wiring to pass
  `message.metadata.technical.rationale_id`.
- Anchor renders nothing when the field is absent.

### Phase 3 — events + params + cost sections (3 BE-days)

- Backend: endpoint extension to join in events (from existing SSE log
  per invocation) + params (with source tag — already discussed in
  Wave 3-2, currently dropped per your earlier instruction) + cost
  (from billing tables).
- Frontend: 3 extra popover tabs.

### Phase 4 — extend curation to non-bioc (1 BE-day per domain)

- Cryo, admet, docking, pbpk — one curator pass per domain, citing
  qc_evidence.yaml gates.

### Phase 5 — production rollout

- Enable on dev → user testing → enable on prod.

## What's already in place

| Item | State |
|---|---|
| `workflow_phase_rationale` table + 24 bioc rows | shipped (L week-1) — would be replaced/repurposed by Phase 1's rationale_registry |
| Endpoint stub | shipped — needs reshape for the 4-section response |
| `<WhyAnchor>` React component + RTL tests | shipped (L week-2) — keeps; just needs prop refactor in Phase 2 |
| Chat-message wiring | shipped (L week-3) — keeps; just reads a different field in Phase 2 |

Net: **~70% of what I built is reusable**; the remaining 30% is the
tagging discipline + content-shape refactor described in Phase 1+2.

## Open questions for you

1. **Per-event tagging** — is the chain curator the right person to
   maintain the `rationale_id` per chain step, or should it be a
   separate role (e.g. scientific lead)?
2. **Citation requirement** — for Phase 1 do we ship rationale rows
   without DOIs (the design allows it), or hold for fully-cited?
3. **Cost block** — design has it commented out. Skip it or wire it in?
4. **Coverage scope** — for the bioc tutorial recordings, 24 bioc rows
   are enough. For real dev coverage we'd need ~150 rationale_ids
   across 12 domains. Is that the right scope or smaller?

## What I won't do until you answer

- I won't extend the rationale to non-bioc chains via auto-extraction
  (the script I wrote `populate_chain_rationale_from_steps.py` is
  staged but unrun). That's authoring without the per-event tagging
  discipline above — same architectural debt at larger scale.
- I won't add the events/params/cost sections to the popover until
  Phase 3 is approved.

Reply with answers to the 4 open questions and I can start Phase 1.

---

## Update — your answers + citation source audit (2026-06-14)

You answered:
1. **Tagging owner**: scientific lead per domain.
2. **Citations**: must have solid DOIs/source links from existing
   curated DBs. Audit what we have first; flag gaps.
3. **Cost block**: commented out for now (matches design's commented
   state).
4. **Coverage**: ~150 rationale_ids across 12 domains, audited by
   per-domain experts.

### Citation-source audit (DB-first survey)

Sources confirmed in the repo:

- `backend/config/qc_evidence.yaml` — **73 gates with paper_doi**, 100%
  cited. 28 domains.
- No other `*_citations.yaml`, `references.json`, or DB column carries
  per-workflow DOIs. Per-workflow rows in the `workflows` table do not
  carry citations.

Chain-vs-qc_evidence coverage matrix:

| chain domain | # chains | qc_evidence gates available by domain name | category |
|---|---|---|---|
| transcriptomics | 15 | 5 | ✅ direct |
| drug_discovery | 11 | 0 | ⚠️ mapping (admet/pbpk/docking/cyp_ddi/nca_pk/ivive/etc. all exist in qc_evidence, just not by domain name) |
| epigenomics | 5 | 4 | ✅ direct |
| single_cell | 5 | 7 | ✅ direct |
| genomics | 5 | 0 | ❌ true gap |
| variant_calling | 4 | 0 | ❌ true gap |
| pharmacology | 3 | 0 | ⚠️ mapping (nlmixr2_poppk + p0_pkpd + allometric exist in qc_evidence) |
| cryo_em | 1 | 3 | ✅ direct |
| immunology | 1 | 0 | ❌ true gap |
| metabolomics | 1 | 0 | ❌ true gap |
| metagenomics | 1 | 0 | ❌ true gap |
| proteomics | 1 | 0 | ❌ true gap |
| rare_disease | 1 | 0 | ❌ true gap |

24 qc_evidence domains have curated DOIs but no chain in the matching
domain — these are the candidates the **drug_discovery + pharmacology**
mapping work would consume. Examples: admet (4 gates), pbpk (4),
docking (2), cyp_ddi (2), structure_prediction (3), antibody_
developability (3), …

### Total scope estimate

| Category | Chains | ~Phases/chain | Rationale_ids | Citation work |
|---|---|---|---|---|
| ✅ Already done (bioc, week-1) | 4 | 6 | 24 | done |
| ⚠️ Mapping only (drug_discovery + pharmacology) | 14 | 5 | ~70 | scientific lead writes **per-chain phase→gate map** (~30 min/chain). DOIs already exist in qc_evidence. |
| ❌ True gap (genomics, variant_calling, immunology, metabolomics, metagenomics, proteomics, rare_disease) | 13 | 5 | ~65 | scientific lead **collects new DOIs** + writes per-chain mapping (~2 hr/chain) |
| | | | **~159 total** | close to your ~150 target |

### Concrete next deliverables

What I can produce mechanically (no science authoring) before any
scientific-lead review:

1. **A `rationale_mapping.yaml` template** at
   `backend/config/rationale_mapping.yaml` with one stub block per
   chain — empty `phase → gate_name` table the scientific lead fills
   in. For the 14 mapping-only chains I can pre-fill suggested gate
   matches based on chain step `role` keywords (e.g. step
   `admet_triage` → likely cites `admet_herg_ic50` / `admet_ames`),
   marked `suggested: true` for scientific-lead review.

2. **Phase-1 backend refactor**: `rationale_registry` table per
   the doc above, replacing `workflow_phase_rationale`. Populate
   script reads `rationale_mapping.yaml` → joins with qc_evidence.yaml
   → INSERTs rows. Per-event `rationale_id` tagging added to chain
   narrator.

3. **Phase-2 frontend**: `<WhyAnchor>` prop refactor to expect
   explicit `rationaleId` from chat metadata. Existing component
   architecture survives.

4. **A gap-tracker doc** at `docs/20260614_RATIONALE_GAP_TRACKER.md`
   listing the 13 "true gap" chains with one row per phase, where the
   scientific lead checks off as DOIs are collected. Reviewer-friendly.

5. **Audit hook**: every row in `rationale_registry` carries
   `last_curated_at` + `curated_by` (scientific lead's id/email),
   so domain-expert audit can sign-off per row.

### What's awaiting you

Pick which of (1)–(5) to start with. My recommendation:
- (1) first — gives the scientific lead the work to schedule.
- (4) in parallel — surfaces the true gaps separately so they get
  scheduled with curators.
- (2) + (3) after — backend/frontend wiring once we know how content
  arrives.

I will NOT pre-fill any actual citation text from imagination — only
mechanical mappings (chain role keyword → existing qc_evidence gate
name), marked as suggestions for scientific-lead review.
