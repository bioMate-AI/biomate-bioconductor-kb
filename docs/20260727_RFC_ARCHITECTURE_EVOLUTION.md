# RFC: BioMate architecture evolution — compose what's already built

Date: 2026-07-27
Status: RFC (for discussion)
Author: engineering

## Framing (corrected)

An earlier draft of this analysis read as "here are the gaps." That undersold the
platform. A first-hand inventory shows **BioMate is an integrated, production-scale
system, not a prototype.** What's genuinely built and working:

- **Execution engine** — 2,455 indexed workflows across ~34–36 domains, real
  **Nextflow-on-AWS-Batch** execution, **embedding-based semantic workflow search**
  (bge-small + dense index), workflow generation from natural language *and* from
  research papers, SSE live progress, Redis-backed run-state with an orphan
  completion poller.
- **Auto-loop QC + remediation** — **evidence-graded gates (GOLD/SILVER/BRONZE)**
  with domain-specific thresholds (hERG/ICH-S7B, RNA-seq Z′, cryo-EM resolution,
  AMES, DILI), plus an auto-healer with 20+ fixers and was→now param remediation.
- **AI findings + regulatory reporting** — structured findings, **IND §2.6.1
  narratives**, CRO compliance packages, DOCX/PDF export, JSONL audit trails.
- **Drug-discovery / clinical suite** — 58 modules: ADMET, PBPK/MRSD (ICH M3),
  docking, retrosynthesis, **BOIN dose escalation**, survival/KM, NONMEM PopPK,
  ICH S2/S5/S7 regulatory gating, active-learning auto-retrain, Bayesian optimizer.
- **Agentic orchestration** — multi-agent research/domain routing, a composed
  toolkit (`run_code` sandbox, `read_file`, param mappers), user-pattern
  personalization, LTM memory (expertise, corrections, saved workflows).
- **Connectors / MCP** — a single-source-of-truth 19-tool manifest → ChatGPT,
  Claude, Slack, WeChat, Feishu, Cursor, etc.; **19 lab-instrument connectors**
  (Opentrons, plate reader, qPCR, MinKNOW, LCMS…); OAuth.
- **Multi-omics breadth** — RNA-seq, WGS/sarek, cryo-EM/CryoSPARC, single-cell,
  proteomics, metabolomics, MOFA2, metagenomics, phylogenomics, immunology.
- **Closed-loop** — output→input chaining (`run:<id>:outputs`), chain composer,
  billing (Lago + Java service + Batch/S3 Lambdas), and a real **DBTL controller**
  (cyclic-peptide design-build-test-learn).
- **Federated 18-DB search**, benchmark-driven development (40+ eval adapters),
  vision/PDF ingestion.

**So the thesis of this RFC is evolution, not construction:** the capabilities
exist and are sophisticated. The leverage is in making them **compose**, be
**self-aware**, be **model-drivable**, and be **verified and governed** — so the
whole is as strong as the (already strong) parts. Nearly every problem this month —
the literature-search punt, `/mcp` down, fragmented data, connector drift — traced
to *connection/orchestration/awareness*, not missing features.

## The one architectural idea

> Turn a rich set of powerful-but-siloed capabilities, each behind a narrow
> hardcoded path, into a **self-aware, agentic, verified, governed fabric** where
> the model composes BioMate's own capabilities as tools over a unified data plane.

Everything below is an instance of that idea, each grounded against a capability
that already exists.

---

## Principle 1 — Compose via agency, not pre-computed injection
**Elevates:** the agentic tool loop + `federated_query` + auto-loop QC + findings.

Several "smart" paths pre-compute one result and inject it as fixed context the
model is *locked to* (the research agent injected 3 records + "cite only the
provided list" → it punted). The platform already has the pieces for the better
pattern — the `BIOMATE_TOOLS` loop, MCP, `run_code`. **Route the intelligent paths
through agency:** expose `search_literature` (federated, iterative, verified),
`query_database` (entity-routed), `search_my_data`, `read_file`/`run_code` as tools
the model chooses and iterates on. This is what just fixed the PEX search (route
through the federated engine + give breadth + verify) and it generalizes.

## Principle 2 — Capability self-awareness (a registry the model reads)
**Elevates:** the workflow DB (2,455), `federated_query`, `WorkflowDatasetSelector`,
the connector `tools_manifest`.

The model didn't know `federated_query` or `WorkflowDatasetSelector` existed. The
connector already proves the pattern — one `tools_manifest.py` → all surfaces.
Generalize it: a **single capability registry** (workflows + DB sources + tools +
user data + instruments) that (a) the model is told about, and (b) is drift-guarded
by a contract test. This structurally closes the "capability exists but unused"
class.

## Principle 3 — A unified data plane: catalog + provenance over the S3 store
**Elevates:** `project_files`, the `run:<id>:outputs` closed loop, Redis run-state,
Galaxy `file_sources`/object-stores (present, unused).

Today data is real and reusable (the `run:<id>:outputs` loop *works*), but scattered
across a local dir + custom S3 + `project_files` + `chat_sessions.datasets`. Promote
`project_files` into **one searchable dataset catalog** with an input→run→output
**lineage graph**, exposed as `search_my_data`. Keep S3 as the physical store; add
lifecycle + quota. Reach for Galaxy `file_sources` (S3/Drive/Dropbox/iRODS — already
in the codebase) for *user-connectable* storage and Galaxy object-stores for
RBAC/audit **only where enterprise governance demands it** (pharma/CRO). Note: the
object-store bypass was a *deliberate* Nextflow-on-Batch choice, not an oversight.

## Principle 4 — Two-tier model routing (quick vs deep)
**Elevates:** the existing model-config + thinking-budget machinery.

Default Gemini Flash serves quick Q&A well; **deep/rigorous tasks should route to a
stronger model (Claude) + a real thinking budget + a larger completion budget** (a
gpt-4o-mini synthesis is visibly weaker than Claude on an evidence review). Make the
tier explicit and cost-aware, detected from rigor cues or a toggle. (Phase-0 already
raised the deep-mode completion budget; the model choice belongs at the
orchestration layer.)

## Principle 5 — Verification & grounding as first-class
**Elevates:** the evidence-graded QC system, the citation pipeline, the regulatory
checkers.

BioMate already grades QC evidence (GOLD/SILVER/BRONZE) and runs ICH checkers — the
same rigor should govern *retrieval and synthesis*: cite only from the retrieved
list, verify every DOI/PMID/PDB against the source (Phase-0 added NCBI title-match
verification), label "Not directly demonstrated." For scientific/pharma users,
*checkable, non-hallucinated* output is the moat.

## Principle 6 — Contracts + canaries + monitors for every assembled surface
**Elevates:** the connector contract test + deploy canary (just built), the
benchmark suite.

Unit tests test the parts; the connector work showed you must test the *assembled*
whole against a running server. Extend the runtime-contract + deploy-canary +
synthetic-monitor pattern to the **research path, DB integrations, and workflow
execution**, and add **single-source + drift guards** wherever something is declared
N times (adapter switches, manifests, model configs).

## Principle 7 — Resilience & observability by default
**Elevates:** the Redis run-state fix, the SSM-independent health check.

Generalize the run-state fix — *no critical state in in-process dicts*. Add
**structured tracing of agentic decisions** (which tools/sources chosen, why, what
was retrieved/verified) so failures are diagnosable without the SSM archaeology this
month kept needing. Harden deploys (public-URL health check — done) and the
git/worktree workflow that caused churn (feature branches + clean merges; avoid a
shared main dir being edited by multiple sessions).

---

## Strategic through-line: feed the DBTL loop
BioMate's differentiator is being the **execution engine + a closed DBTL loop**
(the DBTL controller + Bayesian optimizer + instrument connectors already exist).
Principles 1–7 are precisely what turns the current capability set into that loop:
the model *composes* search → data → workflow → QC → findings → next design
(agency), *knows* what it can reach (registry), over a *governed, provenance-tracked*
data plane (catalog), with *verified* science (grounding) and *observable, resilient*
execution. Search was the first thread; the same pattern threads the loop.

## Phased roadmap (build on what exists)
- **Phase 0 (shipped this session):** route the research path through
  `federated_query`, drop the sabotaging augmentation, inject real citation
  metadata, verify identifiers, deep-mode budget. Validated: PEX 3→17 papers
  matching ChatGPT; generalizes across 6 domains.
- **Phase 1:** agentic tools for search/DB/data (P1); deep-mode → Claude routing
  (P4); capability registry v1 (P2); full-text enrichment into deep synthesis.
- **Phase 2:** unified dataset catalog + `search_my_data` + lineage (P3); fix
  `user_s3` fetch; contract tests/canaries for the research + workflow paths (P6).
- **Phase 3:** Galaxy `file_sources` for user-connectable storage + object-store
  governance where required (P3); agentic-decision tracing + monitors (P7); wire the
  composed loop end-to-end into DBTL.

## Non-goals
- Rebuilding capabilities that already exist and work.
- Integrating an external hosted search dependency (paperclip) — BioMate already
  owns the sources; the work is orchestration.
- A wholesale migration onto Galaxy's job/object-store model — adopt selectively
  where governance requires it, not as a default.

## Appendix — capability → principle map
| Existing capability (real) | Enhancement principle |
|---|---|
| federated_query (18 DBs), BIOMATE_TOOLS loop, MCP | P1 compose via agency |
| workflow DB (2,455), tools_manifest, WorkflowDatasetSelector | P2 self-awareness registry |
| project_files, run:<id>:outputs, Galaxy file_sources/object-stores | P3 unified data plane |
| model-config + thinking budget | P4 two-tier routing |
| evidence-graded QC, ICH checkers, citation pipeline | P5 verification/grounding |
| connector contract test + canary, benchmark suite | P6 contracts/canaries/monitors |
| Redis run-state, public-URL health check | P7 resilience/observability |
| DBTL controller, Bayesian optimizer, instrument connectors | strategic loop target |
