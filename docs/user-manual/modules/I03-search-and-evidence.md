# Search & evidence

> One-line promise: ask a scientific question in plain language and get back a **cited answer** you can
> read, audit, and save — with the search shown ("how this was searched"), disagreements surfaced
> rather than smoothed, and an always-present boundary telling you what the answer is *not* evidence
> for. For everyone: PIs sizing up a target, chemists checking SAR, anyone who needs a sourced answer
> before committing compute.

<!--
General-module chapter (Part I.3). Every "supported" claim is code-verified (tier C) and cited
file:line. Honesty rule: the rich answer surface (retrieval bars, conflicts, source reader, per-item
BibTeX/APA, locus, recency) is REAL in the UI but several pieces render only when the backend supplies
real data — which for some fields it does not yet. Those are called out inline and in "What's not
covered" (Appendix E). Nothing here is styled as present that a live query would not actually show.
-->

## What this is for

This is the **Instant lane's** front door for questions of the form *"what is known?"* — as opposed to
*"run this on my data"* (that's Data analysis, I.6). You type a question; BioMate searches the
literature and a set of live biomedical databases, synthesises a short answer, and returns it **in the
conversation, in seconds**, with its sources attached. No run panel, no AWS Batch, no bill for a
pipeline — an evidence answer is an Instant-lane result (`_lane_from_classification` maps
literature/comparison/knowledge intents to `"instant"`,
`ai_assistant.py:3131-3141`).

The design commitment that separates this from a chatbot: **the answer carries its own provenance and
its own limits.** You always see which sources it rests on, you can open each one, and you always see a
boundary block stating what it does not cover. An evidence answer is meant to be *auditable*, then
either saved as a reusable project object or turned into a real run on your own data.

## What you can ask — the four tracks

The Search & evidence module presents four tracks on the cold-start card
(`COLD_MODULES[0]`, `cold-start-dashboard.tsx:225-263`). Clicking an example **seeds** your composer
(and, for data-backed examples, **attaches its prepared demo dataset**; it does not send — you review
and send). The tracks are framings of the same question surface, not
four different engines:

| Track | What you ask | Example (real seed) | Backed by |
|---|---|---|---|
| **Literature** | Evidence, mechanism, SAR, why-things-fail | "What is the evidence linking this target to disease?" | PubMed · arXiv · Semantic Scholar + PMC/Europe PMC full-text |
| **Databases** | Reported structures, off-targets, trial endpoints, gene/variant facts | "Pull every reported structure for this target." | Live REST: Ensembl, GTEx, ENCODE, ClinVar, MyGene/OMIM, GWAS Catalog, Open Targets, Monarch/HPO |
| **Patents** | Composition-of-matter, freedom-to-operate, claim overlap | "Who holds composition-of-matter claims on this scaffold?" | **No dedicated patent source today** — see "What's not covered" |
| **Internal** | "Have we done this before / what did we conclude" | "Find the last ADMET baseline for this platform." | Project knowledge / memory (not the literature agent) |

> **Pitfall — Patents is a doorway, not a patent search engine.** The Patents track seeds a
> patent-shaped question and routes it to the Instant lane, but the research agent behind the answer
> queries **no patent corpus** (USPTO / Google Patents / Lens are not wired;
> `research_agent.py` + `literature_clients.py` expose only PubMed/arXiv/Semantic Scholar). A
> patent-worded question returns a *literature-grounded* answer, not a freedom-to-operate opinion.
> Treat it as background, and confirm FTO with counsel. (Appendix E.)

Sources genuinely queried (verified): **PubMed, arXiv, Semantic Scholar**
(`UnifiedLiteratureClient`, `literature_clients.py:581-615`), with **PMC / Europe PMC** full-text and
figure/table extraction when a paper is open-access (`_fetch_pmc_fulltext`,
`_fetch_paper_pdf_url`, `research_agent.py:106-335`), plus the live biomedical databases listed above
called **before** synthesis so the model reasons over real records, not guesses
(`research_agent.py:463-1153`).

## How to ask

Ask a *knowledge* question, not a *do-this* command — the phrasing decides the lane.

> "What is the evidence linking KRAS G12C to pancreatic cancer, and how strong is it?"

> "Known off-targets for a sulfonamide chemotype — what does the literature say drives them?"

**Disambiguation to avoid:**
- *"Analyse my expression data for KRAS"* is **not** a search — it routes to Data analysis (Cloud).
  Search answers "what is known"; the moment your own file is the subject, you're in a different lane.
- A patent-worded question (see Pitfall above) still returns literature, not a patent opinion.
- "Have we…/did we…/our previous…" phrasing is the **Internal** track — it reaches for project
  knowledge/memory, a different surface from the literature agent.

## How the answer is built — retrieval transparency

BioMate does not just hand you a paragraph; it shows the search that produced it, but **only using real
counts it actually has**. This is the honesty spine of the module.

**Query widening.** A single AND-joined query under-retrieves on specific questions, so the agent
decomposes your question into several complementary queries (the precise joined query first, then the
natural-language question, then salient term-pairs and rare singletons) and merges the candidate pools
(`_build_search_queries`, `research_agent.py:834-871`). This raises recall without loosening the
citation-grounding guard downstream.

**"How this was searched."** When the retrieval path carries per-source tags, the agent computes, from
the *actual* pool, how many records each source contributed (`found`) and how many survived into the
papers the answer cites (`kept`) — by object identity, nothing estimated
(`_compute_retrieval_stats`, `research_agent.py:2319-2353`). The panel renders one bar per source plus
an "N of M kept" summary (`CitationPanel`, `citation-panel.tsx:485-525`).

> **QC gate — honest-empty, never fabricated.** The "How this was searched" section renders **only**
> when the backend supplied real per-source counts; the client filters on `Number.isFinite(found/kept)`
> and shows nothing otherwise (`citation-panel.tsx:147-151`). The backend emits the `retrieval` field
> **only when non-empty** (`ai_assistant.py:5311-5313`), and `_compute_retrieval_stats` returns `[]`
> when the pool has no source tags. So an ordinary answer degrades to a plain source list — you never
> see a manufactured search trace.

## Reading the answer

An evidence answer is a small dossier. Here is every part and how to read it — each renders through
`ResearchResponseDisplay` → the rich `CitationPanel`
(`benchmark-evidence.tsx:479-604`, `citation-panel.tsx`).

**The answer text**, with numbered `[N]` markers tied to the citation list. The agent keeps only the
papers the answer actually cites (citation grounding), so a source in the list is a source the text
leaned on.

**Citations you can open.** Each source shows title / venue / year and badges (DOI, PMID). An **open ▸**
button opens the **source reader** — a right-hand pane with next/prev navigation so you can walk the
whole evidence base without leaving the thread (`SourceReaderPane`, `source-reader-pane.tsx:51-181`).
Full text is not fetched into the reader; it links out to the DOI/PubMed page honestly rather than
faking a passage.

**Per-citation copy.** Each source has **APA** and **BibTeX** copy buttons, and the panel has a
top-level **Export BibTeX** (`citation-panel.tsx:449-464, 869-895`).

> **Pitfall — BibTeX/APA for literature answers are currently *not* pre-formatted.** The buttons are
> real, but a literature citation from the research agent arrives with **empty** `formatted_apa` /
> `formatted_bibtex` (`toEvidenceCitations` sets them `""`, `benchmark-evidence.tsx:463-477`). The
> honest consequences, by design: the per-item **BibTeX** button is **disabled** when there's no
> formatted string (`citation-panel.tsx:887`); the top-level **Export BibTeX** button is **hidden**
> unless a workflow or a real BibTeX string is present (`canExportBibTeX`, `citation-panel.tsx:142`);
> **APA copy** falls back to a short `Author et al., year` string (`citation-panel.tsx:873`). Formatted
> BibTeX today is populated for **workflow tool** citations (server-side export via
> `exportCitationsBibTeX`), not for literature sources. Use the DOI/PMID to import into your reference
> manager. (Appendix E.)

**Conflicts — "Sources disagree."** If two or more retrieved sources materially disagree on the same
point, a `ConflictRow` appears — "Sources disagree — N conflicting findings" — expanding to show each
position side by side with the source it rests on, never silently resolved in favour of the newer or
more-cited paper (`ConflictRow`, `citation-panel.tsx:529-535, 687-737`).

> **QC gate — conflicts are only ever real.** The agent asks the synthesis model to emit a
> machine-parseable conflicts block **only if** a genuine disagreement exists, and to emit nothing
> otherwise; a conflict needs ≥2 distinct positions on the same point or it is dropped
> (`_CONFLICT_INSTRUCTION` + `_parse_conflicts_block`, `research_agent.py:38-51, 2355-2415`). The
> backend emits `conflicts` only when non-empty (`ai_assistant.py:5314-5316`) and the client filters
> to positions-bearing conflicts (`citation-panel.tsx:143`). No disagreement → no row. It is never
> manufactured to fill the section.

**Locus ("cited for:") and recency.** The citation item and reader can show the exact figure/table/
section a source was relied on ("cited for: Fig 3B") and when it was retrieved / which corpus version
(`citation-panel.tsx:807-827`, `source-reader-pane.tsx:105-128`).

> **Pitfall — locus and per-citation recency don't populate for live literature answers yet.** The
> `Citation` dataclass carries `locus` / `retrieval_date` / `corpus_version` fields, all defaulting to
> `None`, and the UI renders them honest-empty (`research_agent.py:1187-1193`). But the research agent
> **never sets** them and the serializer **never emits** them (verified: no assignment in
> `research_agent.py`, not in the `citations_json` block at `ai_assistant.py:5276-5292`). So today the
> "cited for:" line and the per-source "Retrieved …" line stay hidden on a real answer — the affordance
> is built and safe, but the data pipeline behind it is not connected. (Appendix E.)

**The boundary block — always present.** Below the answer sits an amber boundary: *what this answer is
NOT evidence for.* If the agent supplied a specific caveat it shows that; otherwise it shows an honest
standing caveat ("Synthesises retrieved literature only — not validated against your project's data")
— never silently omitted (`ResearchResponseDisplay`, `benchmark-evidence.tsx:516-555`).

> **Pitfall — the standing boundary is the usual case.** The backend's `research_query` response does
> **not** emit a `boundary` field today (it is absent from the `result` dict,
> `ai_assistant.py:5294-5316`), so `response.boundary` is normally undefined and the client falls back
> to the standing caveat. That's by design and honest — but don't read a generic boundary as
> "the agent judged this specific answer safe."

**Benchmark evidence (when present).** For tool-comparison questions ("STAR vs HISAT2?"), a
`BenchmarkEvidence` card can appear above the citations with ranked tools, metrics, and the source
study's DOI/PMID (`benchmark-evidence.tsx:76-382`). This renders only when the backend attached
`benchmark_evidence`.

## Saving / exiting the answer

An evidence answer is ephemeral until you act on it. There are three sanctioned exits:

| Exit | What it does (precisely) | Where |
|---|---|---|
| **Save to project** / **Save to notes** | Writes the answer **plus its sources** as a **project-knowledge note** (`knowledgeType: "notes_synthesis"`) via `POST /api/memory/projects/:id/knowledge`. The Project Notes page reads it. | `benchmark-evidence.tsx:493-513`; `citation-panel.tsx:242-278` |
| **Make instruction** | Promotes the answer to a **standing project instruction** (`knowledgeType: "project_instruction"`, bounded to ~300 chars) the assistant applies in this project's future chats. | `citation-panel.tsx:287-327` |
| **Check against our data** | Re-runs the question that produced the answer as a **validated workflow** on your data (the redo-as-validated-run path). Only rendered when the handler is wired — never a dead button. | `benchmark-evidence.tsx:571-582`; `chat-message.tsx:638-641` |

> **Pitfall — "Save to project" is a project-knowledge note, NOT a versioned Files document.** It is
> stored in project knowledge/memory (the same store Notes and Instructions use), keyed by project. It
> is *not* an entry in the `/files` data hub and does not carry file versioning or lineage. It is
> reusable and non-ephemeral, but it lives with the project's notes, not its datasets
> (`api.request("/memory/projects/${id}/knowledge", …)`, `benchmark-evidence.tsx:499`).

> **Pitfall — the save/instruction exits need an open project.** With no active project the buttons are
> **disabled** with an explanatory tooltip, never a fake success (`activeProjectId` guard,
> `citation-panel.tsx:391-447`; `benchmark-evidence.tsx:564-566`). Open or select a project first.

## Pitfalls & tips

> **Tip — read the boundary before you trust the answer.** Every evidence answer synthesises *retrieved
> literature only* and is not validated against your data. If it matters, click **Check against our
> data** to turn it into a real run.

> **Tip — open the sources, don't just skim the paragraph.** The **open ▸** / **Read** buttons and the
> source reader exist so you can audit the actual figure/paper. An answer with two open-able,
> on-point sources is worth more than a confident paragraph with none.

> **Pitfall — a plain source list can mean the search wasn't source-tagged, not that it was shallow.**
> Absence of the "How this was searched" bars means the backend didn't supply per-source counts for
> this query — it is honest-empty, not a bug and not a claim of exhaustiveness.

> **Tip — use Databases-track questions for hard facts.** Gene→Ensembl ID, variant consequences (VEP),
> tissue expression (GTEx), pathogenic variants (ClinVar), GWAS/Open-Targets gene ranking are looked up
> from **live REST APIs before synthesis** (`research_agent.py:463-1153`), so those answers rest on
> real records, not the model's memory.

## What's not covered

Honest scope — these are **not** claimed as present; they live in **Appendix E (Coverage & roadmap)**:

- **A real patent / freedom-to-operate search.** The Patents track is a question doorway only; no
  patent corpus (USPTO / Google Patents / Lens) is wired into the research agent
  (`literature_clients.py` exposes only PubMed/arXiv/Semantic Scholar). Patent-worded questions return
  literature-grounded answers.
- **Pre-formatted APA / BibTeX for literature citations.** Literature sources arrive with empty
  `formatted_apa`/`formatted_bibtex`; the per-item BibTeX button is disabled and top-level Export is
  hidden for literature-only answers (`benchmark-evidence.tsx:463-477`, `citation-panel.tsx:142, 887`).
  Formatted BibTeX today is populated for **workflow tool** citations, not literature. Import via
  DOI/PMID meanwhile.
- **Per-citation locus ("cited for:") and recency on live answers.** The UI fields exist and render
  honest-empty, but the research agent never populates `locus`/`retrieval_date`/`corpus_version` and the
  serializer never emits them (`research_agent.py:1187-1193`; `ai_assistant.py:5276-5292`). The
  affordance is built ahead of the data pipeline.
- **An answer-specific boundary.** The boundary block is always shown, but the backend does not emit a
  per-answer `boundary` field yet, so the standing caveat is the normal case
  (`ai_assistant.py:5294-5316`).
- **Full-text in the source reader.** The reader links out to the publisher (DOI/PubMed); it does not
  render article body text (`source-reader-pane.tsx:131-150`).
- **"Save to project" as a versioned Files document.** Saving writes a project-knowledge note, not a
  versioned `/files` dataset (`benchmark-evidence.tsx:493-513`).

---
_Verification: this page depends on the coverage-ledger rows under **"## Search & evidence"** —
Instant-lane routing for knowledge questions (C), four tracks / cold-start seeds (C), literature sources
PubMed+arXiv+S2+PMC (C), live DB lookups before synthesis (C), retrieval transparency real found/kept +
honest-empty (C), conflicts real-only + honest-empty (C), source reader link-out (C), citations
abstract+relevance emitted / locus+recency NOT emitted (C), APA/BibTeX empty for literature (C),
always-present boundary + standing-caveat fallback (C), three exits Save-note / Make-instruction /
Check-against-data (C), and the gap rows for patents / formatted citations / locus-recency / answer
boundary / full-text (🗺️)._
