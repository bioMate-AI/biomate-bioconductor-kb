# Reference Note — Biomni (Stanford general-purpose biomedical AI agent)

> Reference note prepared 2026-10-04 to ground and structurally model BioMate's flagship + RealBio
> manuscripts. Read-only external reference. Full fetched preprint text saved at
> `reference/_fetched/biomni_paper_fulltext.txt`. Repo context: `./Biomni/` (upstream code),
> `backend/*BIOMNI*` and `docs/*BIOMNI*` (our integration/eval analyses).

## Full citation

Biomni exists in two authoritative forms — cite the Science version as the published paper and the
bioRxiv/Stanford PDF for the detailed preprint:

**Published (Science):**
- **Title:** *Autonomous biomedical research with an artificial intelligence agent*
- **Venue:** *Science*, 2025
- **DOI:** 10.1126/science.adz4351
- **URL:** https://www.science.org/doi/10.1126/science.adz4351
- (Exact volume/issue/page not shown on the open landing page; the publisher page returned HTTP 403
  to automated fetch. Confirm volume/page from the Science citation box before final bibliography.)

**Preprint (bioRxiv / Stanford PDF — richer detail, same work under its project name "Biomni"):**
- **Title:** *Biomni: A General-Purpose Biomedical AI Agent*
- **Authors:** Kexin Huang¹*‡, Serena Zhang¹*, Hanchen Wang¹,²*, Yuanhao Qu³,⁴,⁵*, Yingzhou Lu⁵*,
  Yusuf Roohani¹,⁶, Ryan Li¹, Lin Qiu⁷, Gavin Li¹, Junze Zhang³,⁵, Di Yin³,⁵, Shruti Marwaha⁸,
  Jennefer N. Carter⁸, Xin Zhou⁵, Matthew Wheeler⁸, Jonathan A. Bernstein⁹, Mengdi Wang¹⁰, Peng He¹¹,
  Jingtian Zhou⁶, Michael Snyder⁵, Le Cong³,⁵, Aviv Regev², Jure Leskovec¹‡.
  (*equal contribution; ‡corresponding: kexinh@cs.stanford.edu, jure@cs.stanford.edu)
  Affiliations: Stanford (CS, Pathology, Genetics, Medicine, Pediatrics, Cancer Biology), Genentech,
  Arc Institute, Univ. of Washington, Princeton, UCSF.
- **Posted:** 2025-06-02. **DOI:** 10.1101/2025.05.30.656746
- **URLs:** https://www.biorxiv.org/content/10.1101/2025.05.30.656746v1 ·
  PDF: https://www.biorxiv.org/content/10.1101/2025.05.30.656746.full.pdf ·
  PMC: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12157518/ · Stanford: https://biomni.stanford.edu/paper.pdf
- **Live system:** https://biomni.stanford.edu · Code: https://github.com/snap-stanford/biomni

## Abstract (verbatim excerpt from the preprint)

> "Here, we introduce Biomni, a general-purpose biomedical AI agent designed to autonomously execute
> a wide spectrum of research tasks across diverse biomedical subfields. To systematically map the
> biomedical action space, Biomni first employs an action discovery agent to create the first unified
> agentic environment – mining essential tools, databases, and protocols from tens of thousands of
> publications across 25 biomedical domains. Built on this foundation, Biomni features a generalist
> agentic architecture that integrates large language model (LLM) reasoning with retrieval-augmented
> planning and code-based execution, enabling it to dynamically compose and carry out complex
> biomedical workflows – entirely without relying on predefined templates or rigid task flows."

## Agent architecture

Two components:

- **Biomni-E1 — the environment (unified action space).** Built by an **action-discovery LLM agent**
  that read the 100 most-recent papers in each of **25 bioRxiv subject categories**, extracting tasks,
  tools, databases, software. Human-verified. Contents: **150 specialized biomedical tools,
  105 software packages, 59 databases.** Databases handled two ways: (a) big relational DBs via web
  APIs (PDB, OpenTarget, ClinVar) exposed as one natural-language function per DB (LLM parses schema →
  generates queries); (b) non-API DBs downloaded into a local data lake as pandas DataFrames.
  Described as *"the first environment for a biomedical AI agent."*
- **Biomni-A1 — the agent.** Three core innovations: (1) **LLM-based tool selection** that
  retrieves a tailored subset of tools/DBs per query; (2) **code as a universal action interface**
  (loops, parallelization, conditionals; can interleave software/tools/DB/raw-data ops that don't fit
  fixed function signatures — contrasted explicitly with traditional function-calling); (3) **adaptive
  planning** — an initial plan grounded in biomedical knowledge, iteratively refined during execution.
  No hardcoded per-task workflows.

## Benchmark / evaluation

Three evaluation tiers (claim-to-evidence ladder):

1. **Established Q&A benchmarks** — Humanity's Last Exam (HLE) + LAB-Bench (DbQA + SeqQA). vs. 6
   baselines. Results: **DbQA 74.4%** (≈ expert human 74.7%; coding agent ReAct+Code only 40.8%);
   **SeqQA 81.9%** (> human 78.8%); **HLE 17.3%** on a 52-question / 14-subfield subset (base LLM 6.0%,
   coding agent 12.8%, literature agent 12.2%). LAB-Bench used a 45-question dev set + 315 held-out
   test questions, 3 runs, a 12.5% subset due to API cost.
2. **8 new real-world task benchmarks** (never seen in development), spanning genetics, genomics,
   microbiology, pharmacology, clinical medicine: variant prioritization; GWAS causal-gene detection;
   CRISPR perturbation screen design; rare-disease diagnosis; drug repurposing; scRNA-seq cell-type
   annotation; microbiome disease-taxa analysis; patient gene prioritization. No prompt engineering /
   fine-tuning. vs. base LLM (Claude Sonnet 3.7), ReAct+Code, and a Biomni-ReAct ablation. Results:
   Biomni beat base LLM by **+402.3%** avg relative, coding agent by **+43.0%**, Biomni-ReAct by
   **+20.4%**. Trajectories: 6–24 steps/task, 0–4 tools, 1–8 software, 0–3 data-lake items.
3. **3 real-world case studies:** (a) jointly analyzing **458 wearable-sensor Excel files** (CGM +
   temperature, 30 participants) → autonomous 10-step pipeline, found a postprandial thermogenic
   response (avg +2.19 °C); (b) large-scale bioinformatics on raw scRNA-seq + ATAC-seq; (c)
   autonomous wet-lab protocol design.

(Press/Science summary also quotes: **"443 questions spanning 10 kinds of biomedical tasks, average
accuracy 57%,"** and that on three expert-level tasks Biomni matched specialists in a fraction of the
time — these are the Science-version framing numbers; cross-check against the exact figure captions.)

## Headline claims

- First **general-purpose** (not task-specific) biomedical AI agent; first unified agentic
  **environment** for biomedicine.
- Matches/exceeds **human expert** performance on structured DB querying and sequence reasoning.
- Strong **generalization** to unseen real-world tasks with **no task-specific tuning**.
- **Code-centric planning + environment grounding** is the key driver (shown via ablations).
- Vision: "virtual AI biologists" working alongside human scientists.

## How the paper is STRUCTURED and positioned (model this for OUR flagship)

1. **Motivation framed as a scaling-of-expertise crisis:** data abundance >> expert bandwidth;
   fragmented workflows slow discovery. Poses the aspirational question: *"Can we build a virtual AI
   biomedical scientist?"*
2. **Contrast with prior art:** previous agents are *narrow/specialist*; the gap is *generalist*
   breadth — and the technical challenge is coupling reasoning with specialized executable actions.
3. **Two-part system reveal:** environment (E1) first, then agent (A1) — environment-as-moat before
   the agent that uses it. (Directly analogous to BioMate's "the system is the product, not the LLM.")
4. **Three-tier evidence ladder, increasing realism:** established benchmarks → novel held-out
   benchmarks → real-world scientist-in-the-loop case studies. Each tier has explicit baselines and
   **ablations** (Biomni-ReAct) that isolate *why* it works.
5. **Figures:** Fig 1 = system (1a action discovery, 1b E1 environment, 1c A1 architecture);
   Fig 2 = benchmarks (2a Q&A, 2b the 8 real-world tasks); Fig 3 = case studies (3a data, 3b pipeline).
6. **Positioning / tone:** open platform + open invitation ("explore, stress-test, co-create"); heavy
   use of generalization + no-task-specific-tuning as the credibility hook; ends on a field-shaping
   vision statement.

## How this should inform BioMate's flagship + RealBio papers

- **Adopt the 3-tier evidence ladder** (known benchmarks → novel held-out tasks → real-world case
  studies with scientists) as the flagship's results spine. RealBio execution-grading is our Tier-2;
  live AWS-Batch runs / instrument-connector case studies are our Tier-3.
- **Lead with the environment, not the model.** Biomni sells E1 (tools/DBs/software) as the moat
  before A1. BioMate's analogue: the 4,000+ indexed workflows, enriched tool DB, QC auto-loop, and
  execution engine — present these as the unified action space FIRST, then the agent that composes it.
  Reinforces our "model is one component of a composite system" thesis.
- **Use ablations to prove mechanism.** Biomni-ReAct isolates code-centric planning. We should ship a
  comparable ablation (e.g., QC-loop on/off, rule+LLM extraction vs LLM-only) so reviewers see *why*
  BioMate wins, not just that it does.
- **Baselines must include a bare base LLM and a generic coding agent** — the +402% / +43% framing is
  persuasive precisely because of those two reference points. Mirror exactly.
- **Numbers-to-figures discipline:** every headline number ties to a figure panel with explicit
  baselines and run counts (3 runs, held-out sets). Match that rigor in RealBio.
- **Our differentiators to emphasize against Biomni:** Biomni's real-world execution is largely
  Python/code-in-sandbox; BioMate's edge is *production execution* (real Nextflow/nf-core on AWS
  Batch, live SSE, QC gates, instrument connectors, compliance/report outputs) — i.e., we execute
  real pipelines on real infrastructure, not just compose code. Position RealBio's **execution
  grading** (terminal success + S3 output-content checks) as a harder, more real evaluation than
  Biomni's Q&A-heavy benchmarks.

## Local repo context (for the primary session)

- `./Biomni/` — upstream Biomni code + our conversion analyses (e.g.
  `20251129_BIOMNI_TO_GALAXY_CONVERSION_ANALYSIS.md`).
- `backend/*BIOMNI*` — overlap/value/integration analyses
  (`BIOMNI_FUNCTIONS_ANALYSIS_2025-10-13.md`, `CORRECTED_BIOMNI_GALAXY_OVERLAP_2025-10-09.md`,
  `20260116_BIOMNI_VALUE_ANALYSIS.md`, etc.).
- `docs/*BIOMNI*` — our `biomni_eval1` benchmark runs/fixes (routing, instability, failure analyses).
  Useful to show we have already measured ourselves against a Biomni-style capability surface.
