# Market-Background Timeline — BioMate Competitors & Comparables

**Date:** 2026-10-05 · **Scope:** Agentic-bio, drug-discovery AI, and immune-adjacent players
relevant to BioMate's positioning (chat → validated-catalog routing → managed cloud execution → QC
auto-loop → auditable report). This is a consolidated, cited, dated reference: founding dates,
funding rounds, product launches, preprint→journal publication dates, and major milestones.

**Reuse basis (read first, extended here):**
- `internal/marketing-research/competitors_ai_agents.md` — founding/funding/results + dates for most agent players.
- `internal/marketing-research/competitors_bioinformatics_platforms.md` — Seqera/Benchling/platform funding.
- `docs/20261005_COMPETITOR_PUB_TIMELINES_AND_OUR_ESTIMATE.md` — preprint→journal timelines (Biomni, Virtual Lab, LongevityBench).
- `docs/marketing/biomate-marketing-strategy.md` §2 — competitor table + market sizing.

**Honesty contract.** Every date/amount below carries a source. Facts carried from the reuse docs
keep their original access date (2026-10-04); facts added by fresh research on 2026-10-05 are marked
"accessed 2026-10-05". **Unverified / soft items are flagged inline and consolidated in §4.** Private-
company funding totals from aggregators (Tracxn, CB Insights, multiples.vc, PitchBook) are labelled
"(aggregator)" and should be treated as directional. Exact journal *accepted* dates are not verifiable
(paywalls) — see §4 and the reuse pub-timeline doc.

---

## 1. Player-by-player reference table

Grouped by category. **Funding** gives cumulative total (where known) and the **last round (date,
amount, lead)**. **Flagship paper** gives preprint date → journal publication (venue).

### 1a. Academic / open agentic-bio

| Player | Founded | Total funding / last round | Key launches & milestones (dated) | Flagship paper (preprint → journal) |
|---|---|---|---|---|
| **Biomni → Phylo** (Stanford Snap lab → Phylo Inc.) | Project 2025 (Stanford); commercialized as **Phylo, Sept 2025** | **$13.5M seed** (a16z + Menlo Ventures), **Sept 2025** [SynBioBeta, 2026-10-04] | bioRxiv **2025-05-30**; **>10,000 labs** (Stanford News 2026-07); Phylo + "Biomni Lab" + Academic Lab Program launch **Sept 2025**; open-source retained (Apache 2.0) | bioRxiv **2025-05-30** → **Science** 393(6813), **2026-07-09** (received 2025-06-02), DOI 10.1126/science.adz4351 |
| **FutureHouse** (nonprofit) | **Sept 2023** (Rodriques & White) | Philanthropic — Eric & Wendy Schmidt (first 2 yrs), OpenPhilanthropy, NSF [FutureHouse About / caproasia, 2026-10-05] | **PaperQA/PaperQA2** Sept 2024; open platform **Crow/Falcon/Owl/Phoenix launched 2025-05-01**; **Robin** multi-agent → ID'd **ripasudil** for dry AMD (2025); **Finch** data-discovery agent | **PaperQA2** arXiv **2409.13740** (Sept 2024) |
| **Edison Scientific** (for-profit FutureHouse spinout) | Spun out **2025** | **$70M seed at $250M valuation**, **Dec 2025** [caproasia, 2026-10-05] | **Kosmos** research agent; launch price **$200/run** (6 free for academics); "~79% reproducible" (vendor/principal claim) | (shares FutureHouse lineage) |
| **The Virtual Lab** (Stanford — Swanson, Zou) | Academic (Stanford); no funding | n/a | LLM-agent team designed **nanobodies for SARS-CoV-2** variants | bioRxiv **2024-11-11** → **Nature** 646(8085):716–723 (**≈ Oct 2025 in-issue**; online ~Jul 2025), DOI 10.1038/s41586-025-09442-9 |

### 1b. Frontier-lab science offerings

| Player | Founded / formed | Funding | Key launches & milestones (dated) | Flagship / benchmark |
|---|---|---|---|---|
| **Google "AI co-scientist"** (Google Research + Cloud AI + DeepMind) | Program revealed **2025-02-19** | n/a (internal) | Multi-agent hypothesis/proposal system on **Gemini 2.0**; reasoning, not pipeline execution [Google Research, 2026-10-04] | — |
| **OpenAI for Science / GPT-Rosalind** | "OpenAI for Science" team formed **late 2025** (reported; see §4) | **$4M DOE Codex grant** (~2,000 "Genesis" researchers) | **GPT-Rosalind announced 2026-04-16**; **Rosalind Workbench** (NGS Analysis Workbench) **2026-08-28**; **GA 2026-09-11**; **pricing 2026-10-05** [OpenAI, 2026-10-05] | BixBench ~0.751 (vendor) |
| **Anthropic — Claude for Life Sciences** | Announced **2025-10-20** | n/a (Anthropic) | Connectors (Benchling, 10x Genomics, PubMed, bioRxiv/medRxiv, OpenTargets, ChEMBL); **Protocol QA 0.83 vs 0.79 human**; Novo Nordisk 10+ wks → ~10 min; "Claude Science — workflow not a new model" framing **TechCrunch 2026-06-30** | — |

### 1c. Dev-tooling / platforms (BioMate's execution-adjacent lane)

| Player | Founded | Total funding / last round | Key launches & milestones (dated) | Note |
|---|---|---|---|---|
| **Seqera** (fka Seqera Labs; Nextflow Tower) | **2018** (CRG spin-off; Di Tommaso & Floden); Nextflow created 2013 | ~**$53.6M** total; **Series B $26M, 2025-05-06**, led by **Addition** [Crunchbase/Tracxn, 2026-10-05] | $5.5M seed (2021); **Series A €22M/$21.8M Oct 2022** (Addition); **Seqera AI** generate/self-heal nf-core features **June 2025** | Closest execution-adjacent competitor; engineer-facing, nf-core |
| **Benchling (+ Benchling AI)** | **Jan 2012** (Wickramasekara, Singhal) | ~**$411M** / 9 rounds; **Series F $100M, Nov 2021** at **$6.1B** (secondary ~$2.4B, 2024) [PitchBook/Sacra, 2026-10-05] | >1,300 companies / 7,500 academic institutions; **Benchling AI** agents over ELN/LIMS data (exact launch date **unverified** — see §4); new **Data Analysis skill** + products at **SynBioBeta 2026** | ELN/LIMS-embedded; property-prediction, not NGS pipelines |

### 1d. Closed vertically-integrated drug-discovery platforms

| Player | Founded | Funding / public status | Key launches & milestones (dated) | Note |
|---|---|---|---|---|
| **Recursion** (RXRX) | **2013** (Salt Lake City) | **Nasdaq IPO April 2021**; **acquired Exscientia** — agreement **2024-08-08** (~$650M stock), **completed 2024-11-20** | **LOWE** (LLM-Orchestrated Workflow Engine) unveiled at **JPM, Jan 2025**; **REC-4881** (MEK1/2, FAP) first clinical validation of the AI-enabled OS **Dec 2025** [Recursion FY2025, 2026-10-04] | Closed wet+dry loop; not addressable by external data |
| **Insilico Medicine** (3696.HK) | **2014** (Zhavoronkov) | **HKEX IPO 2025-12-30**, **HK$2.28B (~$293M)** — largest 2025 HK biotech IPO; pre-IPO **Series E >$100M** led by Pudong VC + Value Partners (2025) [Cooley/DDW/PRNewswire, 2026-10-05] | Pharma.AI (PandaOmics / Chemistry42 / MMAI Gym); **Nach01** chemistry FM; **rentosertib/ISM001-055** (IPF, gen-AI designed) through **Phase 2**; 28 preclinical candidates / 10 clinical programs | Vertical pharma pipeline |
| **Isomorphic Labs** (Alphabet/DeepMind spinout) | **2021** (Hassabis) | **$600M first external round, March 2025** (Thrive); **Series B $2.1B, 2026-05-12** (Thrive lead; Alphabet, GV, MGX, Temasek, CapitalG, UK Sovereign AI); total **>$2.6B** [Isomorphic/TFN, 2026-10-05] | Co-developed **AlphaFold 3** (May 2024); **IsoDDE** engine announced **Feb 2026**; first AI-designed drugs expected to enter trials **end 2026** | Internal design engine + pharma partners (Lilly, Novartis, J&J) |
| **Owkin** (K Navigator / "Owkin K") | **2016** (Paris/NY) | ~**$304M** (some aggregators $334M) / 8 rounds; **unicorn 2021** via **$180M Sanofi**; **BMS $80M** equity [multiples.vc/Dealroom, 2026-10-05] | **K Navigator** agentic co-pilot launched **2025-05-05** ("20x", 26.5M articles, 19 DBs, MOSAIC data); free for academics | Co-pilot over Owkin's proprietary data; not a user-data executor |

### 1e. Virtual-cell / data-substrate & structure models

| Player | Founded | Funding / last round | Key launches & milestones (dated) | Flagship paper |
|---|---|---|---|---|
| **Tahoe Therapeutics** (fka Vevo; "Tahoe Bio") | **~2024** (exact **unverified** — see §4) | **$30M (2025)** [Forbes **2025-08-11**] | **Tahoe-100M** atlas (100M profiles; 1,100 compounds × 50 lines) bioRxiv **2025-02-20**; **250k+ downloads** (Arc Virtual Cell Atlas) | bioRxiv **2025-02-20** (Tahoe-100M); **Tahoe-x1** bioRxiv **2025-10-23** |
| **Chai Discovery** | **2024** (Meier, Dent, McPartlon, Boitreaud) | **Series C $400M, July 2026** at **$3.8B** post-money; total trajectory: **$30M seed (2024-09-09**, Thrive/OpenAI/Dimension) → **$70M Series A (2025-08-06**, Menlo) → **$130M Series B (Dec 2025**, $1.3B) → **$400M Series C** [BusinessWire/Bloomberg/intuitionlabs, 2026-10-05] | **Chai-1** open structure model **Sept 2024**; **Chai-2** zero-shot antibody/biologics design **June 2025** (16% hit rate reported) | Chai-1 technical report (2024) |

### 1f. Immune / autoimmune-adjacent

| Player | Founded | Total funding / last round | Key milestones (dated) | Note |
|---|---|---|---|---|
| **Immunai** | **Dec 2018** (Israel/NY) | ~**$295M** total; **last round Series B $215M, 2021-10-27**, led by **Koch Disruptive Technologies** (seed $20M May 2020; Series A $60M Feb 2021) [TechCrunch/Times of Israel/Tracxn, 2026-10-05] | "AMICA" immune-cell atlas; immune-cell data → drug-target discovery; closed/internal perturbation loop (referenced in `docs/20260719_WETLAB_CLOSEDLOOP_USECASES_AND_PARTNERS.md`) | Commercial, internal; closest immune-data comparator; **no new public round since 2021** |

---

## 2. Single chronological timeline (foundations → 2026)

**Pre-2023 context**
- **2012** — Benchling founded. **2013** — Recursion founded; Nextflow created (Seqera lineage). **2014** — Insilico Medicine founded. **2016** — Owkin founded. **2018** — Seqera Labs founded; **Immunai founded (Dec)**. **2021** — Recursion IPO (Apr, Nasdaq RXRX); Isomorphic Labs founded; Owkin unicorn (Sanofi $180M); Immunai Series B $215M (Oct); Benchling Series F at $6.1B (Nov).

**2023**
- **Sept** — FutureHouse founded (nonprofit, Schmidt-backed).

**2024**
- **May** — AlphaFold 3 released (DeepMind + Isomorphic Labs).
- **Sept 9** — Chai Discovery $30M seed (OpenAI, Thrive, Dimension); **Chai-1** open structure model released.
- **Sept** — FutureHouse PaperQA2 (arXiv 2409.13740).
- **Nov 11** — The Virtual Lab preprint posted (bioRxiv).
- **Nov 20** — Recursion completes Exscientia acquisition (agreement Aug 8, ~$650M).

**2025**
- **Feb 19** — Google "AI co-scientist" revealed (Gemini 2.0).
- **Feb 20** — Tahoe-100M preprint (bioRxiv).
- **March** — Isomorphic Labs $600M first external round (Thrive).
- **May 1** — FutureHouse open platform (Crow/Falcon/Owl/Phoenix).
- **May 5** — Owkin K Navigator launched.
- **May 6** — Seqera Series B $26M (Addition).
- **May 30** — Biomni preprint (bioRxiv); **Jun 2** Science submission (received).
- **June** — Seqera AI nf-core generate/self-heal features; **Chai-2** zero-shot biologics design.
- **Aug 6** — Chai Discovery $70M Series A (Menlo).
- **Aug 11** — Tahoe Therapeutics $30M (Forbes).
- **Sept** — Biomni commercialized as **Phylo**; $13.5M seed (a16z + Menlo); Biomni Lab.
- **≈ Oct** — The Virtual Lab in-issue in Nature (vol 646; online ~Jul).
- **Oct 20** — Anthropic Claude for Life Sciences announced.
- **Oct 23** — Tahoe-x1 preprint (bioRxiv).
- **Late 2025** — "OpenAI for Science" team formed (reported); DOE $4M Codex/"Genesis".
- **Dec** — Chai Series B $130M ($1.3B val); Edison Scientific $70M seed ($250M val); Recursion REC-4881 first clinical validation; **Insilico HKEX IPO (Dec 30), HK$2.28B**.

**2026**
- **Jan 26** — MIT Tech Review frames "the Year of AI and Science" (OpenAI push).
- **Feb** — Isomorphic IsoDDE engine announced (claims 2× AlphaFold 3 on a protein–ligand generalization benchmark).
- **Apr 16** — GPT-Rosalind announced (OpenAI).
- **May 12** — Isomorphic Labs **$2.1B Series B** (Thrive-led; total >$2.6B).
- **Jun 30** — Anthropic "Claude Science" framing (TechCrunch).
- **Jul 9** — **Biomni published in Science** (393(6813)).
- **July** — Chai Discovery **$400M Series C** at **$3.8B**.
- **Aug 28** — OpenAI Rosalind Workbench (NGS Analysis Workbench).
- **Sept 11** — GPT-Rosalind GA; **Sept 17** — LongevityBench/Longevity-LLM published in Cell (189(19)).
- **Oct 5** — GPT-Rosalind published pricing takes effect.

---

## 3. What the timeline implies for BioMate

**Funding/validation cadence.** The field is in a steep capital ramp with two distinct motions:
(1) **structure/drug-design and vertical-pharma** players are raising nine- and ten-figure rounds —
Isomorphic $600M (Mar 2025) → $2.1B (May 2026); Chai $30M → $400M at $3.8B inside ~22 months;
Insilico's Dec-2025 HKEX IPO — i.e., capital is flowing fastest to **asset-generating and
structure-prediction** stories, not to execution/orchestration tooling. (2) **Agentic-research**
players validated through **journals and adoption** rather than mega-rounds: Biomni (Science, >10k
labs) and FutureHouse/Edison (Nature-adjacent lineage, modest $70M seed) show the academic→thin-
commercial path. The lesson for BioMate: credibility in the agent lane is still earned by
**peer-reviewed validation + adoption**, and the comparator cadence is **8–13 months preprint→journal**
(Biomni ~13 mo) — consistent with `docs/20261005_COMPETITOR_PUB_TIMELINES_AND_OUR_ESTIMATE.md`.

**Where the crowding is.** Two zones are saturated. (a) **Hypothesis/literature + frontier-model
science copilots** — Google AI co-scientist, OpenAI GPT-Rosalind, Anthropic Claude for Life Sciences,
Owkin K Navigator, FutureHouse — all cluster in 2025–2026 and all stop at **reasoning / lit synthesis /
connector-mediated analysis**. (b) **Closed vertical drug-discovery** — Recursion/LOWE, Insilico,
Isomorphic, Genentech — run real pipelines but **only on their own programs**, unaddressable by an
outside scientist's data. The 2026 convergence point is explicit in Anthropic's own "workflow, not a
new model" framing: the industry agrees the **value is in the execution/workflow layer**, yet the
frontier labs are deliberately shipping models + connectors, not a managed pipeline runner.

**The timing white-space.** The one lane repeatedly left open is a **managed, reproducible, QC-gated
execution product** that takes a scientist's own data, routes it across a large validated workflow
catalog, runs it on scalable cloud compute, auto-remediates QC failures, and emits auditable reports.
Seqera is the only execution-adjacent player — but it is **engineer-facing nf-core dev tooling**, and
its funding cadence ($26M Series B, May 2025) shows this lane is **not where the mega-capital is
chasing**, i.e., it is contested by far fewer, far smaller players than the copilot and asset-generation
lanes. BioMate's two-part positioning exploits exactly this gap:
1. **Execution-first.** None of the 2025–2026 copilots (and neither Biomni's full-privilege Python
   sandbox nor Kosmos's ad-hoc code) advertise catalog-routed managed execution with a QC auto-loop and
   auditable provenance — a reproducibility/compliance story the sandbox agents cannot credibly tell.
2. **Immune-stratification depth.** The immune-adjacent comparator (Immunai) **has not raised a public
   round since 2021** and is a closed/internal data play — leaving an **open, execution-capable immune
   analysis lane** uncontested by a well-capitalized incumbent. BioMate's immune-stratification focus
   therefore faces thin direct competition precisely where the broader field is most crowded (generic
   copilots) and most closed (vertical pharma).

**Timing read.** The copilot land-grab peaked Oct-2025→mid-2026 (Claude LS, GPT-Rosalind, Rosalind
Workbench). The execution layer is still forming. A BioMate preprint + adoption push in **late 2026 /
H1 2027** (per the pub-timeline doc) lands while the execution-reproducibility lane is uncrowded and
before any frontier lab productizes a managed pipeline runner — the defensible window.

---

## 4. Unverified / soft items (honesty flags)

- **Exact journal "accepted" dates** — not verifiable (Science/Nature/Cell pages return paywalls/403);
  preprint and in-issue publish dates are solid, submit→accept is derived. See
  `docs/20261005_COMPETITOR_PUB_TIMELINES_AND_OUR_ESTIMATE.md` §1.
- **Benchling AI exact launch date** — not pinned to a primary PR; the product is live and shipped new
  "skills" at SynBioBeta 2026, but the first-launch date is unverified.
- **Tahoe Therapeutics founding year (~2024)** and the "fka Vevo" lineage — not confirmed in a primary
  source during this pass; $30M (2025) and the preprint dates are verified.
- **"OpenAI for Science" team formation date** — "late 2025" is inferred from reporting (MIT Tech Review
  2026-01-26), not a single dated primary PR. GPT-Rosalind's own dates (Apr/Aug/Sept/Oct 2026) are from
  OpenAI pages and are solid.
- **Insilico Series E amount (">$100M")** — from pre-IPO reporting; the **HKEX IPO HK$2.28B (~$293M)** is
  verified (Cooley/PRNewswire).
- **Owkin total funding** — aggregators disagree ($304M vs $334M); the $180M Sanofi (unicorn, 2021) and
  $80M BMS equity line items are consistent across sources.
- **Private funding totals** labelled "(aggregator)" (Seqera ~$53.6M, Owkin, Immunai ~$295M, Benchling
  ~$411M) are from Tracxn/CB Insights/PitchBook/multiples.vc — directional, not audited filings.
- **The Virtual Lab Nature in-issue date (≈ Oct 2025)** — approximate; online date reported ~Jul 2025.
- **Vendor claims** (Owkin "20x", Benchling "~2x", Kosmos "79% reproducible / 6 months in a day",
  "superhuman literature" claims) are marketing, not independent benchmarks — do not cite as measured.

---

## 5. Primary sources (added 2026-10-05; reuse-doc sources retained in those docs)

- Chai Discovery: [BusinessWire Series A 2025-08-06](https://www.businesswire.com/news/home/20250806670137/en/Chai-Discovery-Announces-$70-million-Series-A-To-Transform-Molecular-Design); [Bloomberg seed 2024-09-09](https://www.bloomberg.com/news/articles/2024-09-09/openai-thrive-capital-back-six-month-old-ai-drug-discovery-startup); Series B/C via intuitionlabs/allsci (aggregator).
- Immunai: [TechCrunch Series B 2021-10-27](https://techcrunch.com/2021/10/27/immunai-announces-a-215m-series-b-as-its-immune-cell-atlas-matures/); [Times of Israel](https://www.timesofisrael.com/israeli-biotech-startup-immunai-raises-215m-for-drug-discovery-platform/); Tracxn (aggregator, total ~$295M).
- Benchling: [Sacra](https://sacra.com/c/benchling/); [PitchBook](https://pitchbook.com/profiles/company/61617-16); [Contrary research](https://research.contrary.com/company/benchling).
- Recursion/Exscientia: [Recursion IR — combination completed](https://ir.recursion.com/news-releases/news-release-details/recursion-and-exscientia-two-leaders-ai-drug-discovery-space); [GEN](https://www.genengnews.com/topics/artificial-intelligence/recursion-to-acquire-exscientia-combining-ai-drug-pioneers/).
- Insilico: [PRNewswire HKEX IPO](https://www.prnewswire.com/news-releases/insilico-medicine-lists-on-hong-kong-stock-exchange-showing-ai-drug-discovery-momentum-with-2025s-largest-hong-kong-biotech-ipo-302650606.html); [Cooley](https://www.cooley.com/news/coverage/2025/2025-12-30-insilico-medicine-announces-hk$2-28-billion-ipo); [DDW](https://www.ddw-online.com/insilico-medicine-becomes-2025s-largest-hong-kong-biotech-ipo-39723-202601/).
- Seqera: [Crunchbase Series B 2025-05-06](https://www.crunchbase.com/funding_round/seqera-labs-series-b--b105459a); [Series A €22M, CRG](https://www.crg.eu/en/news/crg-spin-seqera-labs-raises-22-million-euros-series-funding).
- Isomorphic: [Isomorphic on X, $2.1B Series B](https://x.com/IsomorphicLabs/status/2054189884034678895); [TechFundingNews](https://techfundingnews.com/deepmind-spinout-isomorphic-labs-closes-2-1b-from-thrive-capital-gv-alphabet-for-ai-drug-discovery/); $600M [PR Newswire, 2025-03](https://www.prnewswire.com/news-releases/isomorphic-labs-announces-600-million-funding-to-further-develop-its-next-generation-ai-drug-design-engine-and-advance-therapeutic-programs-into-the-clinic-302415534.html).
- Owkin: [multiples.vc](https://multiples.vc/private-comps/owkin); [Dealroom](https://dealroom.co/companies/owkin/).
- FutureHouse/Edison: [caproasia (Edison $70M seed)](https://www.caproasia.com/2025/12/19/united-states-futurehouse-spinout-ai-commercial-startup-edison-scientific-raised-70-million-in-seed-funding-at-250-million-valuation-futurehouse-co-founded-in-2023-as-non-profit-ai-research-lab-by/); [TechCrunch platform launch 2025-05-01](https://techcrunch.com/2025/05/01/futurehouse-releases-ai-tools-it-claims-can-accelerate-science/).
- OpenAI for Science: [Introducing GPT-Rosalind](https://openai.com/index/introducing-gpt-rosalind/); [MIT Tech Review 2026-01-26](https://www.technologyreview.com/2026/01/26/1131728/inside-openais-big-play-for-science/).

> Sources already captured (with access dates) for Biomni/Phylo, Anthropic, Google AI co-scientist,
> Owkin K Navigator, Tahoe, Virtual Lab, and the publication timelines live in
> `internal/marketing-research/competitors_ai_agents.md` and
> `docs/20261005_COMPETITOR_PUB_TIMELINES_AND_OUR_ESTIMATE.md` — not re-listed here to avoid drift.
