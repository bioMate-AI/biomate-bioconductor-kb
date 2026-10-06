# BioMate — Q4 2026 + Q1 2027 plan and 3-year roadmap

**Date:** 2026-10-05. Capstone synthesis. Supersedes the stale April roadmap (`docs/20260403_BIOMATE_ROADMAP.md`,
phases now past). Reuses `business/BioMate_Business_Plan_2026_v4.md` (pricing/ICP/ask/milestones) and this
session's market work: moat/segment strategy + open-core (`20261005_MOAT_AND_SEGMENT_MARKETING_STRATEGY`),
market-background timeline, pharma-opportunities survey, segment-demand differentiation, Houston/Texas
prospects, competitor marketing strategies. **Forward-looking** (a plan, not a record); built-vs-planned flagged.

## Strategic frame (the spine everything hangs on)
- **Moat = on-prem compliant product + white-glove deployment + continuous support + BD relationships +
  the accumulating validated-catalog/data asset.** **Cloud = the PLG funnel/flywheel** (small biotech +
  researchers) that feeds it. **Open-core** opens the funnel (benchmarks, community edition, connector SDK)
  and keeps the moat closed (trained on-prem LLM, enriched catalog, deploy/support, immune-stratification IP).
- **Timing white-space:** the copilot/reasoning and closed-vertical-pharma lanes are saturated; the
  **managed, QC-gated execution lane + the execution-capable immune-stratification lane have no
  well-capitalized incumbent** — and the 8–13-month preprint→journal cadence makes **late-2026/H1-2027 the
  defensible window**. Move now.
- **Structure:** US company + China subsidiary. US co = US/global pharma BD + IP home + VC + cloud credits;
  China sub = China-market data-residency (hospital wedge) + China grants + Shanghai pharma on-ramps. Known
  tradeoff: the China sub forecloses US federal SBIR (counsel item), outweighed by China market/grants/access.
- **Three goals:** (1) **credibility** (preprints + open benchmarks); (2) **adoption funnel** (cloud PLG +
  open-core); (3) **moat build** (on-prem deploy+support + BD into hospitals-China / pharma / boutique-CRO).

## Q4 2026 (Oct–Dec) — "Credibility live + funnel open + first BD motion"
| Workstream | Actions | Gate/metric |
|---|---|---|
| **Science/credibility (lead move)** | Post the **preprint sprint** this month (RealBio, Bioc-KB×2, anti-TNF, Paper B ready; C1/D/E as finished); release benchmarks CC-BY; capture the **live ADMET QC-gate hero** | ≥4 preprints posted; benchmarks public; hero demo recorded |
| **Product (the moat deliverable)** | Finish spark **CPT+SFT + domainpro eval** (constrained-decoding format guarantee); **productize on-prem deployment** (repeatable installer + support tooling); coding/conversion track (Snakemake converter + the exec-graded benchmark); add the **MGI/BGI connector** (China hospital gap) | domainpro eval number; deployment-installer MVP; MGI/BGI connector |
| **GTM/funnel** | Launch **cloud free/Premium tier** (PLG) + the tutorial/video series; open-core **community edition + connector SDK** scoped | free-tier live; signups tracked; community repo scoped |
| **BD** | **Houston/Texas first-10** outreach (warm first: Liu/BCM w/ drafted pilot; SBMI — Zhao/Zhi/Zheng; Mohan/UH; ImmunoGenesis; TMC Innovation Labs); enter **OpenADMET challenge (by 2026-11-03)**; apply **JLABS Shanghai + Lilly TuneLab + Merck MDSS** | first-10 contacted; OpenADMET entered; ≥2 pharma apps in |
| **Corp/funding** | Counsel on **US+China-sub / SBIR tradeoff**; secure **cloud credits** (AWS Activate/MS Founders/Google/NVIDIA) via US co; **China local talent grants** (Suzhou BioBAY / Shanghai) via sub | counsel memo; ≥1 credit program; ≥1 China grant drafted |

## Q1 2027 (Jan–Mar) — "First pilots + submissions + raise prep"
| Workstream | Actions | Gate/metric |
|---|---|---|
| Science | Preprints → **journal submissions** (NAR / Bioinformatics / Nature Methods per the manuscript plan) | ≥3 submitted |
| Product | Harden deployment from pilot feedback; open-core **community edition + benchmark public release**; serve the on-prem LLM via vLLM | community edition shipped; on-prem serving demo |
| BD / pilots | **First on-prem reference pilot** (a Houston site via the warm ties) + **begin a China hospital** pilot (via sub, data-residency); **first pharma pilot** via an accepted open-innovation program | ≥1 signed on-prem pilot; ≥1 pharma pilot started |
| Funding | **Seed/angel raise** prep + first conversations on the recurring-on-prem + immune-stratification thesis (reuse the business-plan ask); **China NSFC/local** grant submissions | raise deck + ≥3 investor convos; grants submitted |

## 3-year roadmap (Q4 2026 → 2029)
Business-plan milestones reconciled to absolute dates + the moat/funnel/open-core arc. The early-2026 plan's
"$1M ARR by month 12" has **slipped** (this year went to product + science); revised honestly below.

| Year | Theme | Targets (revised, honest) | Funding |
|---|---|---|---|
| **Y1 — Q4'26–Q3'27** | Credibility + funnel + first reference pilots | Preprints posted→submitted; open-core launched; cloud PLG adoption (free→Premium/Team); **1–2 on-prem reference pilots** (Houston + China hospital); **1 pharma pilot**; structure set | Cloud credits + China grants → **seed (H1'27)** |
| **Y2 — Q4'27–Q3'28** | Scale on-prem + recurring revenue | Productized deployment → **5–10 on-prem accounts** (hospital/biotech/CRO) with **support contracts (recurring)**; pharma pilot → **embedded contract**; China market entry via sub; outcome-based pricing live; **SOC 2 (US)**; immune-stratification asset advancing | **Series A** on recurring + pharma-embedded traction |
| **Y3 — Q4'28–2029** | Category leadership (execution + immune-stratification) | Multi-account recurring on-prem; **≥1 pharma partnership at scale** (embedded + asset/milestone); **immune-stratification asset milestone**; 21 CFR 11/GxP as enterprise demands; category-defining position | **Series B / strategic** |

**Cross-cutting tracks (reuse `20260403_BIOMATE_ROADMAP` detail):** access/integration (API → IDE →
instrument connectors); quality/cost (caching, tiered models, on-prem $0-marginal LLM); compliance
(SOC 2 → 21 CFR 11/GxP as enterprise pulls it).

**Pricing (reuse business plan v4):** Free $0 / Premium $29 / Team $79-seat / **Enterprise custom $2K–20K/mo
(on-prem + HIPAA/SLA + CSM = the moat tier)** / outcome-based $25–$1,000/analysis (Y2). Enterprise on-prem +
support is the recurring engine; cloud tiers are the funnel.

## Honesty flags
- Revenue/ARR targets are revised from the early-2026 plan and remain **projections**, not commitments.
- Built-vs-planned: on-prem LLM **in progress** (CPT running); **deployment not yet productized**;
  SOC 2/21 CFR 11 **not certified** (don't claim leadership); immune-stratification is a **program, not a
  validated asset**; CRO/IND UX hidden (roadmap, not live).
- US-SBIR foreclosed by the China sub (deliberate tradeoff; counsel to confirm) — see the opportunities doc.
