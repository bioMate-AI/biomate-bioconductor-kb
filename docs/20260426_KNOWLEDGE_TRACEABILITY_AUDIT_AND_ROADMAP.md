# Knowledge Traceability Audit and Roadmap

Date: 2026-04-26

## The Core Question

BioMate has accumulated substantial structured knowledge: 181 RAG chunks, 22 cryo-EM tool entries, 7 sample class protocols, and now 20+ tool_knowledge entries for cryo-EM, protein dynamics, pocket detection, and structure prediction tools — all with verified DOIs from peer-reviewed primary sources.

The question is: **does this knowledge show up where it matters — in the process BioMate runs and in what the user sees?**

The answer is: partially. The knowledge shapes LLM reasoning invisibly but is not traceable by the user. This document maps exactly what is wired, what is broken, and what to build.

---

## How Knowledge Currently Flows (The Actual Pipeline)

```
User query
    │
    ▼
galaxy-assistant.ts → calls query_domain_knowledge tool (cryo-EM domain only)
    │
    ▼
POST /api/cryo_em/context → retriever.get_full_context()
    ├─ cryo_em_protocols:    structured protocol JSON        → LLM system prompt
    ├─ cryo_em_parameters:   parameter table                 → LLM system prompt
    └─ cryo_em_chunks_vec:   BGE ANN search → top-k chunks  → LLM system prompt
    │
    ▼
LLM reasons with context silently → produces workflow recommendation
    │
    ▼
_build_knowledge_highlights() + _build_workflow_citations()
    ├─ queries tool_knowledge by exact tool_name match
    ├─ queries cryo_em_protocols for QC gates
    └─ returns: best_practices, qc_thresholds, literature_guidance, citations[]
    │
    ▼
Frontend rendering
    ├─ citation-panel.tsx:   BibTeX export + methods section  (user-triggered)
    └─ findings-card.tsx:    key results + supporting literature (post-run)
```

---

## What Is Working

### 1. cryo-EM RAG shapes LLM reasoning
All 181 chunks in `cryo_em_chunks_vec` are actively injected into the system prompt when a cryo-EM query is detected. When a user asks about saposin nanodisc SPA, the LLM gets the correct pixel_size range, QC gates, and picking strategy before answering. This is verified by E2E tests (CE-S7-3).

### 2. cryo_em_protocols is rich and domain-complete
7 sample class protocols with QC gates, collection parameters, picking strategy, and key principles. BioMate distinguishes saposin (<60 kDa) from GPCR-Gα (MSP nanodisc) and gives different advice. The protocol knowledge is from primary cryo-EM papers with verified DOIs.

### 3. Citations panel + methods section generation (user-triggered)
`citation-panel.tsx` can export BibTeX and generate a full methods section via:
- `POST /api/ai_assistant/citations/export`
- `POST /api/ai_assistant/citations/methods`

This is real scientific value — a researcher can paste the generated methods section into a manuscript.

### 4. tool_knowledge feeds workflow citations
When a workflow containing a known tool (e.g., cryoDRGN, GROMACS) is generated, `_build_workflow_citations()` queries `tool_knowledge` by exact name and formats citations correctly.

---

## What Is Not Working

### Gap 1: knowledge_highlights are silently dropped (CRITICAL)

`_build_knowledge_highlights()` correctly builds `best_practices`, `qc_thresholds`, and `literature_guidance` from the DB. However, per the knowledge flow audit, **these fields are built and then never rendered in the UX**. A `knowledge-highlights-panel` component is referenced in E2E tests but the data is dropped somewhere in the serialization path. The QC thresholds from `cryo_em_protocols` — e.g., "CTF fit resolution >4 Å: discard micrograph" — are computed and thrown away.

### Gap 2: The user never sees evidence during reasoning

When BioMate says "use pixel_size 0.83 Å/pixel" — the user cannot see that this came from the saposin nanodisc protocol, citing Frauenfeld et al. 2016. The knowledge shapes LLM output but there is **no traceability**. The user has no basis to trust the recommendation over a generic chatbot response.

### Gap 3: RAG exists only for cryo-EM

`cryo_em_chunks_vec` is searched only when a cryo-EM domain is detected. The 18 new chunks for RELION 5, PocketMiner, ProDy, DiffDock-L, AlphaFold 3 etc. are in `cryo_em_chunks` and will be searched for cryo-EM queries — but:
- Drug discovery queries trigger no RAG
- RNA-seq, WGS, proteomics — no RAG layer exists at all
- `tool_knowledge` for those domains is queried only by exact name match AFTER the workflow is already decided

### Gap 4: tool_knowledge is a post-hoc citation store, not a reasoning layer

`tool_knowledge` is read AFTER the LLM decides what to recommend. The new RELION 5 entry with `limitations: ["DynaMight is computationally expensive and limited to relatively rigid proteins"]` will never influence the LLM to say "for your dataset size, consider 3DVA first." The knowledge shapes citations, not reasoning.

### Gap 5: cryo_em_tools gap notes are never surfaced

The DB now knows MotionCor2 is `missing`, ModelAngelo is `missing`, RELION 5 is `partial`. When a user asks for RELION 5, BioMate silently falls back without saying: "RELION 5 is not containerized — using RELION_multibody (partial integration). For a full SPA pipeline, CryoSPARC is recommended." The `biomate_status` and `biomate_gap_notes` columns are never read at runtime.

### Gap 6: Protein dynamics has no protocol layer

Workflow 12886 (protein dynamics) has no `cryo_em_protocols`-equivalent structured protocol. The MDAnalysis fallback, BioEmu limitations, fpocket vs PocketMiner tradeoffs — none of this is structured knowledge injectable at query time. It exists only as RAG chunks that are searched only for cryo-EM domain queries.

### Gap 7: New tool entries are orphaned from the citation pipeline

`_build_workflow_citations()` queries `tool_knowledge WHERE LOWER(tool_name) = ?`. The 16 new tool entries (RELION 5, CTFFFind5, 3DVA, 3DFlex, PocketMiner, P2Rank, ProDy, OpenMM, DiffDock-L, ESMFold, RFAA, etc.) are not yet referenced by any workflow's tool list. They are correct and well-sourced, but will not appear in any generated citation unless a workflow explicitly names them as tools.

---

## Summary Table: Knowledge Asset Status

| Knowledge Asset | Built | Used in LLM Reasoning | Shown to User |
|---|---|---|---|
| cryo_em_chunks RAG — cryo-EM queries | ✅ 181 chunks | ✅ via system prompt | ❌ invisible |
| cryo_em_protocols — 7 sample classes | ✅ rich | ✅ via system prompt | ❌ invisible |
| tool_knowledge — 20 new entries today | ✅ | ❌ post-hoc citations only | ⚠️ citation panel (user must click) |
| knowledge_highlights (QC, best practices) | ✅ built | ✅ built | ❌ silently dropped |
| cryo_em_tools gap notes (missing/partial) | ✅ | ❌ never read at runtime | ❌ |
| RAG for drug discovery / RNA-seq / proteomics | ❌ | ❌ | ❌ |
| Parameter-level citation badges | ❌ | ❌ | ❌ |
| Inline "evidence basis" explanation | ❌ | ❌ | ❌ |

---

## Roadmap to Make BioMate Smarter

### P1 — Fix knowledge_highlights surfacing (1 day)

The data is already built. Find the drop point between `_build_knowledge_highlights()` and the frontend response. Wire the `knowledge-highlights-panel` component to receive QC thresholds and best practices from the workflow generation response.

Expected outcome: the workflow panel automatically shows a "Protocol Notes" sidebar with items like:
- "CTF fit resolution: accept <4 Å, discard >5 Å [Rohou & Grigorieff 2015]"
- "Dose: 40–60 e⁻/Å² total, 1–2 e⁻/Å²/frame [Grant & Grigorieff 2015]"

### P2 — Inline citation badges on parameter prefill (2 days)

When BioMate fills workflow parameters, surface the evidence source:
```
n_zdim       8     [Zhong et al., Nature Methods 2021]
pixel_size   0.83  [saposin nanodisc protocol, Frauenfeld 2016]
n_clusters   10    [cryoDRGN default recommendation]
```

Implementation: pipe `recommended_parameters` JSON from `tool_knowledge` through to the parameter prefill API response. Add a `citation` field per parameter. Render as a small `[Author Year]` badge next to each parameter in `nextflow-workflow-viewer.tsx`.

### P3 — Inject tool_knowledge limitations into LLM context (2–3 days)

Read `tool_knowledge` entries relevant to the query BEFORE the LLM generates the recommendation, not after. Include `limitations` and `recommended_parameters` in the system prompt. This enables the LLM to say: "3DFlex requires >100 GB RAM for 1M particles — for this dataset size, 3DVA is a faster first pass."

### P4 — Surface biomate_status gaps proactively (1 day)

During workflow generation, query `cryo_em_tools WHERE biomate_status IN ('missing', 'partial')`. If a requested tool is missing or partial, include a brief note in the workflow description:
> "Note: ModelAngelo (automated model building) is not yet containerized in BioMate. Manual building via COOT is the current path. ModelAngelo integration is planned."

### P5 — Expand RAG to drug discovery and proteomics (3–5 days)

Create `drug_discovery_chunks` and `proteomics_chunks` tables with the same BGE embedding schema used for `cryo_em_chunks`. Populate with key paper chunks for ADMET tools, docking methods, proteomics pipelines. Wire into `query_domain_knowledge` via domain dispatch:
```python
if domain == 'cryo_em':   retriever = cryo_em_retriever
elif domain == 'drug_discovery': retriever = drug_discovery_retriever
elif domain == 'proteomics':     retriever = proteomics_retriever
```

### P6 — Evidence basis panel in workflow response (3–4 days)

A collapsible "How BioMate decided this" panel showing the top 3 RAG chunks that scored highest for the query. User sees:
```
Evidence basis:
• Saposin nanodisc protocol [Frauenfeld 2016] — pixel size 0.83 Å/px
• cryoDRGN analysis guide [Zhong 2021] — n_zdim=8 for complex heterogeneity
• fpocket druggability scoring [Halgren 2009] — score >0.5 = druggable
```

This transforms BioMate from "AI that seems knowledgeable" to "AI that shows its work" — the difference between scientific credibility and a chat interface.

---

## Strategic Framing

The knowledge collection work is real and correct. 181 verified RAG chunks, 7 structured protocols, 20+ tool entries with primary DOIs — this is a genuine scientific knowledge graph. The bottleneck is not the knowledge itself but the **last mile**: connecting stored knowledge to visible evidence in the UX.

For BioMate's CRO/CDMO positioning (3-phase plan documented in `docs/20260420_CRO_CDMO_POSITIONING_AND_PLAN.md`), this matters commercially. A validation package for a mid-size biotech client needs to show methodology, citations, and parameter rationale — not just output files. The citation panel, methods section generator, and findings card are the right foundations; they just need to be connected to the knowledge that's already in the DB and surfaced automatically rather than requiring user action to discover.

The single highest-leverage change is **P1**: fixing the silent drop of `knowledge_highlights`. The data is already built on every workflow generation. Surfacing it takes one day and immediately makes every workflow recommendation traceable.

---

## Related Documents

- `docs/20260414_KNOWLEDGE_FLOW_AUDIT_AND_PROPOSAL.md` — original knowledge flow audit
- `docs/20260426_KNOWLEDGE_ENRICHMENT_CRYO_DYNAMICS_TOOLS.md` — today's DB enrichment (16 tools, 18 chunks)
- `docs/20260426_CRYO_HET_PROTEIN_DYNAMICS_WORKFLOW_RELATIONSHIPS.md` — workflow relationships
- `docs/20260426_PROTEIN_DYNAMICS_AND_CRYO_HET_BATCH_PASSING.md` — AWS Batch test results
