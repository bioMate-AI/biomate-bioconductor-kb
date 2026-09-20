# Literature & evidence retrieval

> One-line promise: understand the **evidence backbone** behind every cited answer — which literature
> sources are really queried, which live biomedical databases are consulted before the model writes a
> word, how many records were found vs. kept, and where the honest edges are (no patent corpus,
> formatted citations only for tool comparisons). For: anyone who needs to trust — and audit — a
> BioMate evidence answer, and anyone deciding whether an answer is complete enough to act on.

<!--
Part II.3 (Databases & retrieval). This is the *backbone* chapter: it documents the sources and
mechanics that the Search & evidence UI (I.3) draws on. Every "supported" claim is code-verified
(tier C) and cited file:line. DO NOT duplicate the I.3 answer-UI walkthrough — cross-reference it.
Honesty rule: only real behaviour. No patent corpus; formatted BibTeX only for tool citations.
Unknowns / not-built → Appendix E.
-->

## What this is for

The **Search & evidence** module (chapter I.3) is the reading experience — the cited answer, the
retrieval bars, the conflicts card, the source reader. **This** chapter is the plumbing underneath it:
the exact set of sources BioMate queries, the order it queries them in, and the guarantees (and limits)
that the answer inherits from that pipeline.

Read this when you need to answer a harder question than "what did the answer say" — namely **"is this
answer resting on the right evidence, and what could it have missed?"** That is a question about the
backbone, not the UI. If you only want to know how to *read* an answer, its citations, conflicts and
boundary, go to **I.3 — Search & evidence**; everything below is what those affordances are built on.

> **Tip** — An evidence answer is an **Instant-lane** result: it runs in the conversation in seconds,
> with no AWS Batch and no pipeline bill. The retrieval described here happens live, per question.

## Use cases

| Goal (researcher's words) | What the backbone does | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "What's the evidence for target X in disease Y?" | Query-widen → search 3 literature sources → pull open-access full text → synthesise with citations | Plain-language question | Cited answer + per-source found/kept + conflicts (I.3 UI) | Instant |
| "Give me hard facts — Ensembl ID, VEP consequence, GTEx expression, ClinVar status" | Live REST calls to biomedical DBs **before** synthesis, so the model reasons over real records | Gene / variant / rsID in the question | Answer grounded in fetched DB records | Instant |
| "STAR vs HISAT2 — which is better and by what metric?" | Match the question against the **benchmark knowledge DB**; attach a ranked-tools evidence card | Tool-comparison question | Benchmark evidence card (when DB is populated) | Instant |
| "Pull the methods / a figure from that open-access paper" | Fetch PMC/Europe PMC full text + figure/table captions for the cited papers | An answerable question over OA literature | Full-text-grounded answer | Instant |

## How to ask

Ask a *knowledge* question in plain language — the phrasing decides both the lane and which part of the
backbone fires. (The four **tracks** and the routing rules are covered in **I.3 — How to ask**; here we
note only what each track *reaches for* in the backbone.)

> "What is the evidence linking KRAS G12C to pancreatic cancer, and how strong is it?"

> "GTEx tissue expression and ClinVar pathogenic variants for BRCA1."

**Disambiguation to avoid:**
- *"Analyse my expression data…"* is not a search — it routes to Data analysis (Cloud). The backbone
  here only answers *"what is known,"* never *"run this on my file."*
- A **patent**-worded question reaches the same literature backbone — there is **no patent corpus** (see
  "What's not covered"). It returns literature, not a freedom-to-operate opinion.

## Tools & workflows behind this

### Literature sources actually queried

Three sources, and only three, are wired behind the `UnifiedLiteratureClient`
(`literature_clients.py:581-593`), searched in parallel per query (`search_all`,
`literature_clients.py:615-624`):

| Source | Client | Endpoint | Where |
|---|---|---|---|
| **PubMed** (NCBI E-utils) | `PubMedClient` | esearch → efetch | `literature_clients.py:73-254` |
| **arXiv** | `ArxivClient` | Atom query API | `literature_clients.py:257-399` |
| **Semantic Scholar** | `SemanticScholarClient` | Graph API v1 | `literature_clients.py:402-579` |

Each client enforces the source's own **rate limit** (PubMed 0.34 s with an NCBI key / 1.0 s without,
`literature_clients.py:82-100`; Semantic Scholar 1.0 s / 5.0 s, `:411-427`; arXiv fixed 3.0 s, `:266-275`),
so answers degrade gracefully under load rather than getting throttled to an error.

> **License / provenance** — These are public bibliographic APIs. An answer is only as current as what
> those indexes return at query time; there is no private, pre-built literature cache you are reading
> from a snapshot of.

### Open-access full text (PMC / Europe PMC)

When a cited paper is open-access, the agent goes past the abstract and pulls **full text, figures and
tables** — so the answer can rest on Methods/Results, not just the summary:

- `_fetch_pmc_fulltext` — BioC-JSON and E-utils XML fetch; extracts Methods/Results sections, `<fig>`
  captions and `<table-wrap>` numeric tables (`research_agent.py:106-217`).
- `_fetch_paper_pdf_url` — Europe PMC direct-PDF render endpoint (`research_agent.py:307-335`).
- `_extract_fulltext_for_question` — orchestrates S2-PDF → PMC → PDF-text fallback, capped ~6000 chars
  (`research_agent.py:220-290`).

> **Pitfall — full text is fetched for *synthesis*, not shown in the reader.** These fetches feed the
> model's reasoning. The **source reader** in the answer UI (I.3) still **links out** to the DOI/PubMed
> page; it does not render the article body. That is honest link-out, not a hidden paywall
> (cross-ref I.3, "Reading the answer").

### Live biomedical databases — queried *before* synthesis

For hard facts, the agent calls live REST APIs and injects the returned records into the synthesis
prompt **before** the model writes, so those answers rest on real records rather than model memory
(gathered in `_gather_evidence`, `research_agent.py:1736-1984`; each call is keyword/context-gated so it
only fires when relevant). The databases actually wired:

| Database | What it answers | Function | Where |
|---|---|---|---|
| **Ensembl** (lookup / symbol / VEP / sequence) | Gene IDs, variant consequences, sequence | `lookup_ensembl_ids` / `search_ensembl_genes` / `lookup_ensembl_vep` / `fetch_ensembl_sequence` | `research_agent.py:463-567` |
| **GTEx** | Median tissue expression | `lookup_gtex_expression` | `research_agent.py:570-596` |
| **ENCODE / UCSC** | Regulatory elements (cCREs) | `lookup_encode_regulatory` | `research_agent.py:599-624` |
| **ClinVar** (NCBI) | Pathogenic variants per gene | `lookup_clinvar_gene` | `research_agent.py:676-706` |
| **MyGene.info** | Gene annotation / symbol → ID | `lookup_mygene` | `research_agent.py:627-651` |
| **GWAS Catalog** (EBI) | SNP → trait associations | `lookup_gwas_catalog` | `research_agent.py:902-987` |
| **Open Targets** (GraphQL) | Target–disease association scores | `lookup_open_targets_gene` | `research_agent.py:990-1041` |
| **Monarch Initiative (HPO/OMIM)** | Gene ↔ phenotype / disease | `lookup_hpo_genes` / `lookup_omim_disease_phenotypes` | `research_agent.py:654-673, 782-796` |

> **Tip — use a facts-shaped question to hit these.** "Ensembl ID for TP53," "VEP consequence of this
> HGVS," "GTEx expression of SCN5A in heart," "ClinVar pathogenic variants in CFTR," "Open-Targets
> ranking for this gene in IBD" — these fire a live lookup, so the answer is grounded in the record, not
> the model's recall.

### The benchmark knowledge DB (tool comparisons)

When your question is a **tool comparison** ("STAR vs HISAT2?"), and the benchmark DB is available and
populated, the agent runs a semantic query against it and attaches a **benchmark-evidence** card of
ranked tools + metrics + the source study's DOI/PMID
(`_query_benchmarks`, `research_agent.py:2000-2044`; DB class `BenchmarkKnowledgeDB`,
`benchmark_knowledge.py:118-154`; results filtered to ≥0.5 similarity).

> **QC gate — benchmark evidence is opt-in and honest-empty.** The card renders **only** when the
> backend attaches `benchmark_evidence` (which requires the benchmark DB to be present and to return a
> match above the similarity floor). No populated DB → no card, never a fabricated ranking. The card's
> UI is covered in I.3 ("Benchmark evidence").

## How retrieval quality is achieved & shown

This is the honesty spine of the backbone. Three mechanisms make the answer both *broader* and
*auditable*:

**Query widening.** A single AND-joined query under-retrieves on specific questions, so
`_build_search_queries` decomposes your question into up to six complementary queries — precise
AND-joined terms first, then the raw natural-language question, then salient term-pairs, then the rarest
singletons — and the pools are merged and de-duplicated by DOI/PMID/title
(`research_agent.py:834-871`, used at `:1624`, merge at `:1636-1649`). This raises recall without
loosening citation grounding downstream.

**Found vs. kept, by object identity.** `_compute_retrieval_stats` counts, per source, how many records
entered the candidate pool (`found`) and how many survived into the papers the answer actually cites
(`kept`) — matched by Python object identity, nothing estimated; it returns `[]` when the pool carries
no source tags (`research_agent.py:2319-2353`). This drives the "How this was searched" bars in I.3,
which are honest-empty by design (cross-ref I.3, "retrieval transparency").

**Conflicts only when real.** `_CONFLICT_INSTRUCTION` asks the synthesis model to emit a machine-parseable
conflicts block **only if** a genuine disagreement exists, and `_parse_conflicts_block` drops anything
without **≥2 distinct positions** on the same point (`research_agent.py:38-51, 2355-2415`). No
disagreement → no conflicts card. It is never manufactured to fill space.

## Reading the answer

The rendered answer — citations, retrieval bars, conflicts, source reader, the always-present boundary,
and the three save/exit actions — is documented in full in **I.3 — Search & evidence**. This chapter does
not repeat that walkthrough. The one backbone fact worth carrying over:

- **Citations carry `abstract` and `relevance_score` when present, but never `locus` / `retrieval_date` /
  `corpus_version`.** The `Citation` dataclass declares those three evidence-boundary fields with
  `None` defaults (`research_agent.py:1176-1193`), and the agent **never assigns** them — so a live
  answer's "cited for: Fig 3B" and per-source "Retrieved …" lines stay hidden. The affordance is built
  ahead of the data pipeline (cross-ref I.3, and Appendix E).

## Pitfalls & tips

> **Pitfall — no patent corpus exists.** `literature_clients.py` exposes only PubMed / arXiv / Semantic
> Scholar. There is no USPTO / Google Patents / Lens integration anywhere in the research agent. A
> patent-worded question returns a *literature-grounded* answer, not a freedom-to-operate opinion. Treat
> it as background and confirm FTO with counsel. (Appendix E.)

> **Pitfall — formatted BibTeX is only for tool citations, not literature.** Literature citations arrive
> with empty `formatted_bibtex` (there is no BibTeX method on the literature citation path;
> `literature_clients.py` provides `format_apa()` but no BibTeX). Server-side formatted BibTeX exists for
> **workflow-tool** citations only. For a literature source, import via its DOI/PMID into your reference
> manager. (Cross-ref I.3, "Per-citation copy"; Appendix E.)

> **Tip — a plain source list is not a shallow search.** If the "How this was searched" bars are absent,
> the backend simply didn't tag this query's pool by source (`_compute_retrieval_stats` returned `[]`) —
> honest-empty, not a bug and not a claim of exhaustiveness.

> **Tip — recency is live, not cached.** Because the three sources and the biomedical DBs are queried
> live per question, an answer reflects those indexes *now*. There is no snapshot version stamp on a
> literature answer (the `corpus_version` field is never populated).

## Outputs & visualization

The retrieval described here surfaces entirely inside the **conversation**, through the answer surface
documented in I.3 (`ResearchResponseDisplay` → `CitationPanel`): the answer text with `[N]` markers, the
per-source found/kept bars, the conflicts card, the source reader (link-out), the boundary block, and the
three exits (Save to project / Make instruction / Check against our data). There is no separate viewer
for the backbone — it is the evidence layer *under* the I.3 UI. See **I.3 — Outputs & visualization**.

![Placeholder: an evidence answer showing the "How this was searched" per-source found/kept bars over a live literature query](../assets/ii03-1-retrieval-bars.png)

## What's not covered

Honest scope — **not** claimed as present; these live in **Appendix E (Coverage & roadmap)**:

- **A patent / freedom-to-operate corpus.** Only PubMed / arXiv / Semantic Scholar are wired
  (`literature_clients.py:581-593`). Patent-worded questions return literature.
- **Pre-formatted APA / BibTeX for literature citations.** Formatted BibTeX is populated for
  workflow-tool citations only; literature citations expose APA formatting but no BibTeX
  (`literature_clients.py`, `format_apa()` only). Import via DOI/PMID.
- **Per-citation locus / recency / corpus version on live answers.** The `Citation` fields exist with
  `None` defaults and are never assigned by the agent (`research_agent.py:1176-1193`).
- **Full-text rendered in the source reader.** Full text is fetched for synthesis; the reader links out
  to the publisher (cross-ref I.3).
- **A packaged benchmark DB in every deployment.** The benchmark-evidence card renders only when the
  benchmark knowledge DB is present and returns a match above the similarity floor
  (`benchmark_knowledge.py:118-154`); otherwise no card.

---
_Verification: this page depends on the coverage-ledger rows under **"## II.3 Literature & evidence
retrieval"** — three literature sources PubMed/arXiv/S2 only, no patents (C); PMC/Europe PMC full-text +
figure/table extraction (C); live biomedical DB lookups before synthesis (C); query widening
`_build_search_queries` (C); found/kept by object identity `_compute_retrieval_stats` (C); conflicts
real-only ≥2 positions (C); Citation fields abstract/relevance emitted, locus/recency/corpus_version
never set (C); benchmark knowledge DB opt-in / honest-empty (C); per-source rate limits (C); and the gap
rows for patents / formatted literature BibTeX / locus-recency / full-text-in-reader / packaged
benchmark DB (🗺️)._
