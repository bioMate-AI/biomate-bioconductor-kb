# Grounded Standards Assistant — prototype

**Date:** 2026-10-14
**Status:** working prototype (engine + MCP + frontend panel), self-contained under `grounded-prototype/`
**Origin:** a pharma-engineering practitioner's account of two hard limits she hit using AI for GMP work.

---

## 1. The problem (from the source account)

A pharmaceutical engineering practitioner described two boundaries when using AI
(and a company Copilot) for GMP / standards work:

1. **Depth / "the science behind the number."** The AI explains *what* a standard
   requires and *that* wet steam impairs sterilization, but when she asks **why a
   specific numeric threshold is set where it is — what work was done to arrive at
   that number and why** — it runs out of grounded answers and either goes generic
   or confabulates. She wants *rooted* information: the experiments, the derivation,
   the committee reasoning behind the figure.

2. **Provenance & isolation.** In the shared company Copilot, her own project
   content (questions, collaboration records, uploaded files) was retrievable by
   colleagues in *their* projects. So "professional answers" could silently be
   someone else's **unverified personal opinion** rather than a formal regulatory
   source — unacceptable where product quality and patient safety depend on the
   judgement being evidence-based.

Her conclusion: in regulated work, judgements must rest on **reliable, verifiable
evidence**, and the real experts (standards-committee members, PDA/ISPE/SPE
working groups) remain irreplaceable.

## 2. Is her question actually answerable? (reality check)

We researched the worked example (EN 285 steam-quality dryness value) before
building, to avoid a prototype that pretends a question is answerable when it is
not. Findings:

- **There IS a real origin trail.** The physical steam-quality test limits trace
  to the British NHS: first in **HTM 101**, superseded by **HTM 2010** and the
  Scottish **SHTM 2010 / 2031**, later adopted into **EN 285**. There is even a
  dedicated paper, *"The Derivation of United Kingdom Physical Steam Quality Test
  Limits."* So the question is **partly answerable** — the lineage and the
  rationale documents exist and can be cited.
- **But the exact numbers were "established pragmatically."** Published industry
  references (e.g. K. Shuttleworth, *The Application of Steam Quality Test Limits*)
  state the limits were set **empirically / by expert convention** by the UK
  working groups — not derived to a specific figure from a single controlled
  experiment. So the deep "why exactly this number, from first-principles
  experiments" is **only partially answerable** — which is exactly why a generic
  AI (and her colleagues) couldn't satisfy her.
- **There IS supportive experimental literature for the mechanism.** e.g.
  *Detection of Superheated Steam During Sterilization Using Biological Indicators*
  (PMC10634659) and *Analysis of water quality over non-condensable gases
  concentration on steam used for sterilization* (PMC9514632). These ground **why
  a dryness / superheat / NCG window exists**, but characterise the effect rather
  than fixing the exact acceptance cut-off.
- **Secondary sources even disagree on the numbers.** Web summaries transpose the
  0.90 / 0.95 dryness figures (general ≥ 0.90; metal-only loads ≥ 0.95) and
  mis-state the NCG limit (3.5 ml per 100 ml of condensate, *not* "3.5 % by
  volume"). This is first-hand proof that answering a regulated question from a
  model's memory or a web summary is unsafe.

**Conclusion:** her question is answerable *to a documented boundary*, and the
correct behaviour is to ground what the record supports, **name the point where it
stops**, and route the remainder to the committee / societies — which is precisely
what this prototype does. The honest answer is not "here is why 0.95"; it is "here
is the lineage and mechanism that are grounded, and here is the derivation paper /
committee to ask for the rest, because the figure was set pragmatically."

## 3. What the prototype does

An **evidence-tiered, provenance-honest answering layer** for regulated-domain
questions. Two behaviours distinguish it from a generic chatbot:

### (a) Threshold-provenance chain with an explicit boundary
For a "why is the threshold this number / what produced it" question it returns:
1. **What the number is** — from the normative standard (Tier A), with the clause cited.
2. **Why a limit of this kind exists** — the documented *mechanism*, from
   peer-reviewed literature (Tier B).
3. **How the figure was arrived at** — the origin / derivation record (committee,
   HTM/NHS lineage, derivation paper).
4. **Where the record stops** — a `Boundary` that names the part it *cannot*
   ground ("the primary justification for the exact numeric value"), says why
   (pragmatic/empirical origin), and routes to the real holders of the answer
   (standards committee / PDA / ISPE / a drafting SME) with concrete questions to
   put to them. It **never** asserts the exact derivation from memory.

### (b) Tiered provenance + tenant isolation
- Every claim carries its **source tier** (A normative / B peer-reviewed / C
  org-validated / D unverified-personal) and a **citation the reader can verify**.
- A **Tier-D personal note never supports a confirmed claim** — it is only ever
  shown back to its own author, flagged "UNVERIFIED — not evidence."
- **Cross-tenant isolation** is enforced in the retrieval layer: one user's
  private note is never even retrievable by another user. Each answer carries a
  **provenance/isolation audit** (sources used by tier, other users' notes
  blocked) so the property is observable, not taken on faith.
- Overall confidence is a **GRADE-style** badge; a boundary caps the headline
  grade at MODERATE even when the normative/mechanistic parts are strong — honesty
  over a green checkmark.

## 4. Architecture

```
grounded-prototype/
  engine/            # pure-Python, Py3.9-safe, zero deps
    models.py        # SourceTier, QuestionType, Claim, Boundary, IsolationAudit, GroundedAnswer
    corpus.py        # seed corpus (EN 285 steam-quality worked example, real citations)
    classify.py      # rule-first question classification (rationale/normative/investigation/…)
    retrieve.py      # tenant-isolated, tier-aware retrieval (the isolation invariant lives here)
    answer.py        # assembly: provenance chain + boundary + GRADE
    engine.py        # ask() + to_markdown()/to_dict() renderers
  mcp_server/
    server.py        # stdio JSON-RPC MCP server (zero deps, engine in-process)
    http_api.py      # stdlib HTTP API: POST /api/grounded/answer  (+ serves the demo page)
  frontend/
    demo.html        # self-contained demo page (tenant switcher to show isolation live)
    grounded-assistant-panel.tsx   # drop-in BioMate panel (shadcn/Tailwind conventions)
    grounded-api.ts                # typed API client (lib/ai-assistant-api.ts style)
  tests/test_engine.py             # 11 tests: classification, boundary honesty, isolation
  demo.py                          # CLI walkthrough (3 scenarios)
```

### Run it
```bash
# tests (no deps)
python3 grounded-prototype/tests/test_engine.py

# CLI demo
python3 grounded-prototype/demo.py

# HTTP API + visual demo page
python3 grounded-prototype/mcp_server/http_api.py   # http://127.0.0.1:7788/

# MCP server (stdio) — add to Claude Desktop / Cursor / company Copilot:
#   { "mcpServers": { "grounded": {
#       "command": "python3",
#       "args": ["<abs>/grounded-prototype/mcp_server/server.py"] } } }
```

## 5. How it goes into BioMate production

The prototype is deliberately self-contained; the production wiring is drop-in
because the engine is a pure library.

**Platform (frontend) path**
1. `POST /api/grounded/answer` in `frontend/server/routes.ts`, proxying to a
   Galaxy backend handler that calls the engine (`engine.ask(question, user=<authed user id>)`).
   The real user id comes from auth — isolation then keys on the real tenant.
2. Copy `grounded-assistant-panel.tsx` → `frontend/client/src/components/` and
   `grounded-api.ts` → `frontend/client/src/lib/`.
3. Register a `<Route path="/grounded">` in `App.tsx` wrapped in `<PlatformLayout>`,
   and a sidebar button in `app-sidebar.tsx` (`setLocation('/grounded')`).
4. Pre-sync checklist (`docs/PRE_SYNC_CHECKLIST.md`): `npx tsc --noEmit` + `vitest`
   before `scripts/sync_to_dev.sh`.

**Co-pilot (MCP) path — real connector at `/Users/kky/biomate-connector`**
- Add a `ToolSchema("grounded_answer", tier="knowledge", …, backend_path="/api/grounded/answer",
  backend_method="POST", read_only_hint=True)` entry to the single source of truth
  `mcp/tools_manifest.py`, plus a `BioMateClient.grounded_answer()` method and an
  `if tool_name == "grounded_answer":` branch in `dispatch_tool()` in
  `mcp/biomate_mcp_server.py`. The hosted Streamable-HTTP + OAuth surface
  (`remote_mcp/`), the OpenAPI/Anthropic/OpenAI exports, and the drift test all
  regenerate from the manifest (`regen_tools_manifest.sh`).
- This lets a company Copilot that today answers a GMP threshold question from
  memory instead **call the tool** and get the grounded answer + boundary.

## 6. What is real vs. seeded

- **Engine, isolation logic, classification, boundary logic, MCP/HTTP/UI:** real,
  tested, runnable now.
- **Corpus:** a small seed with the EN 285 steam-quality worked example. Normative
  paraphrases are marked `verified=False` with a "confirm against the controlled
  copy" note; the origin/derivation and the two PMC mechanism papers carry **real
  citations and URLs**. Production replaces the seed with BioMate's retrieval over
  a licensed standards/pharmacopoeia corpus + the literature index + the org's
  QA-approved SOP store, keyed by tenant.
- **Retrieval scoring:** transparent keyword/overlap for the prototype; production
  swaps in BioMate's existing dense-vector search (UnifiedWorkflowSearch /
  VectorToolSearch). **The isolation filter stays exactly where it is and keeps its
  shape** regardless of the scorer.

## 6.5 R&D/CMC domain pack — the edge BioMate already owns (added 2026-10-14)

Per the manufacturing survey's recommendation (`docs/20261014_PHARMA_MANUFACTURING_PHASE_SURVEY.md` §8), the engine was first pointed at the **R&D/CMC edge where BioMate already has the buyer and the corpus**, rather than the GMP plant floor. The engine is now **domain-pluggable**: the trust lattice, retrieval, classification, boundary logic, and isolation are domain-agnostic; only the corpus changes (`engine/domains/`, registry in `engine/domains/__init__.py`; `ask(question, user, domain="cmc"|"gmp_steam")`). The CMC pack (`engine/domains/cmc.py`) is mirrored to `galaxy.ai.grounded.domains`, and `domain` is threaded through the MCP tool, the HTTP API, and the backend route.

The CMC pack deliberately spans the **groundedness spectrum of regulatory/discovery thresholds**, which is the differentiator against a naive RAG assistant — the engine assigns a *different honest verdict* to each:

| Threshold | Reality | Engine verdict |
|---|---|---|
| **ICH M7 mutagenic-impurity TTC (1.5 µg/day)** | documented quantitative derivation (10⁻⁵ lifetime cancer risk; TD50 linear extrapolation) **but** a published peer-reviewed critique exists | grade **MODERATE** + *"documented but contested"* boundary (surfaces both the derivation and the debate) |
| **ICH Q3A/Q3B qualification threshold (0.15%)** | harmonized expert/experience convention, dose-dependent, "whichever is lower" | grade **MODERATE** + *"exact value is convention, not derived"* boundary |
| **Lipinski Rule of Five (MW ≤ 500)** | empirical developability heuristic, not a regulatory spec | boundary: a heuristic, no first-principles derivation |
| **hERG cardiotoxicity** | **no fixed regulatory cutoff**; governed by ICH S7B + E14 as an integrated risk assessment; the ~10 µM screen is a discovery heuristic | grounded **refusal** — states there is no fixed threshold, and does **not** endorse a colleague's "<10 µM is automatically fine" personal note (shown only as that user's unverified note) |

Citations are real (ICH M7(R2) FDA media/170461; ICH M7(R1) database.ich.org; ICH Q3A FDA media/71727; the TTC-derivation critique in *Regul. Toxicol. Pharmacol.*; Lipinski *Adv. Drug Deliv. Rev.*; ICH S7B/E14 Q&A). Tests: `grounded-prototype/tests/test_cmc.py` (7 passing) + `test_engine.py` (11 passing). Demo: `demo_cmc.py`.

Why this is the right first application: same buyer BioMate already serves (R&D/CMC, not GMP Quality), same corpus BioMate can already reach (literature + regulatory packs + run data), and it proves the traceability-graph value — spec/threshold → derivation → debate/evidence — without a GMP-plant sale. It is the low-risk step from the survey's recommended sequencing.

## 7. Next steps

- Replace the seed corpus with a real tenant-scoped ingestion (standards under
  licence, literature index, SOP store with QA sign-off = the Tier-C gate).
- Wire the frontend route + sidebar and run the pre-sync checklist to land it on dev.
- Add the `grounded_answer` tool to the real connector manifest.
- Expand the GRADE model and add a "request the rationale annex / committee
  bibliography" action that drafts the actual email to the standards secretariat.

## Sources consulted (reality check, §2)
- K. Shuttleworth, *The Application of Steam Quality Test Limits* — https://gmpua.com/Utilities/Steam/SteamQualityPaper.pdf
- ISPE, *Introduction to Steam Quality and Testing* — https://ispe.org/pharmaceutical-engineering/july-august-2022/introduction-steam-quality-and-testing
- *Detection of Superheated Steam During Sterilization Using Biological Indicators* — https://pmc.ncbi.nlm.nih.gov/articles/PMC10634659/
- *Analysis of water quality over non-condensable gases concentration on steam used for sterilization* — https://pmc.ncbi.nlm.nih.gov/articles/PMC9514632/
- SHTM 2031: *Clean steam for sterilization* — https://www.nss.nhs.scot/media/1785/shtm-2031-part-1-v20-jun-2001.pdf
