# BioMate Texas & National Beta Outreach Strategy
**Created:** 2026-02-25
**Scope:** Texas + DOE Labs + Gulf Coast + Agricultural Belt + Clinical/CRO

---

## The Core Problem with Email Alone

Cold email has a 1–3% open rate and a <0.3% reply rate when sent without prior relationship.
**It cannot be the primary channel — it must be the closing step, not the opening move.**

The key question is: **how do we make them come to us first?**

---

## Public & Inbound Discovery Channels (High Priority)

### 1. GitHub — The Scientific Software Discovery Layer
Researchers discover tools through GitHub. This is where bioinformatics begins.

**Actions:**
- Tag the BioMate GitHub repo with all relevant topics:
  `bioinformatics`, `nextflow`, `galaxy`, `metagenomics`, `rnaseq`, `proteomics`, `cryo-em`, `drug-discovery`, `single-cell`, `nf-core`, `qc`, `reproducibility`, `AI`
- Write README so the first 3 lines explain the value prop: *"Describe your analysis in plain English — BioMate runs the Nextflow pipeline for you"*
- Contribute to nf-core community (GitHub Discussions, issue responses): mention BioMate as a companion orchestration layer
- Open-source a small utility (e.g., the QC threshold database or a standalone metagenomics QC module) — repos with utility components get starred and shared organically
- Star and watch competitor repos — their issue threads are full of researchers with unmet needs

**Expected reach:** Researchers actively searching for nf-core wrappers, Galaxy alternatives, bioinformatics automation

---

### 2. Twitter/X and Mastodon (Academic Bioinfo Community)
The bioinformatics community is extremely active on Twitter and increasingly on Mastodon (`fosstodon.org`, `genomic.social`).

**Actions:**
- Create `@BiomateAI` Twitter/X account
- Post 3x/week: QC threshold explainers, workflow tips, "did you know" posts about BioMate features
- Key hashtags: `#bioinformatics`, `#nfcore`, `#rnaseq`, `#metagenomics`, `#scRNAseq`, `#proteomics`, `#cryoEM`
- Engage directly with researchers posting about pipeline pain points (e.g., "I spent 3 days debugging this Nextflow pipeline" → reply with a demo)
- Follow and engage with key Texas lab Twitter accounts: @TreangenLab, @UT_Bioinformatics, @MDAnderson_Res
- Announce "Texas beta cohort — 50 invite codes" as a limited drop

**Expected reach:** 3,000–15,000 impressions/week if consistent; 1–3 viral posts from QC explainers

---

### 3. Preprint Servers (bioRxiv / medRxiv) — Citation Fishing
Researchers who cite papers BioMate is built on are *already* the target audience.

**Actions:**
- Post a **BioMate preprint on bioRxiv** describing the QC governance framework (draws on Paper 1 content)
  - Title: *"Evidence-Graded Quality Control Governance for Reproducible Bioinformatics at Scale"*
  - Mention Texas pilot users in the Acknowledgments to create regional social proof
- Alert authors who cite nf-core, Galaxy, GATK, DESeq2, CellRanger papers via:
  - Semantic Scholar / Google Scholar citation tracking
  - Automated notification: "We built a governance layer for [tool you cite] — here's a beta code"
- **Submit a Protocol.io method** describing BioMate's RNA-seq QC protocol — protocols.io has millions of views

**Expected reach:** 500–2,000 preprint views; high-quality academic traffic

---

### 4. Bioinformatics Forums & Communities
These are where researchers go when they're stuck — a perfect moment to be helpful.

**Key communities:**
- **Biostars** (biostars.org) — answer questions about pipeline QC, suggest BioMate for complex workflows
- **SEQanswers** (seqanswers.com) — next-gen sequencing forums
- **Reddit: r/bioinformatics** (~120K members) — post a "Show r/bioinformatics: BioMate" launch post
- **nf-core Slack** (nfcore.slack.com) — 10,000+ Nextflow/nf-core users; announce as companion tool
- **Galaxy Community Hub** — BioMate is Galaxy-based; post in Galaxy Hub news
- **EMBL-EBI Training Slack** and **CZI Science Slack**

**Expected reach:** r/bioinformatics launch post can get 500–2,000 views + upvotes; nf-core Slack is very targeted

---

### 5. Conference Presence — The Relationship Accelerator
Cold email sent *after* a conference introduction has 10x the reply rate.

**Texas-priority conferences:**
| Conference | Location | Month | Audience |
|---|---|---|---|
| **ASHG 2026** | San Diego (but 40% Texas attendees) | Oct 2026 | Human genomics, clinical |
| **AACR Annual Meeting** | Chicago | Apr 2026 | Cancer multi-omics |
| **RECOMB 2026** | TBD | Apr/May 2026 | Computational biology |
| **ISMB/ECCB 2026** | TBD | Jul 2026 | Bioinformatics, all domains |
| **PAG 2027** | San Diego | Jan 2027 | Agricultural genomics |
| **AIChE Annual** | San Diego | Oct 2026 | Energy-biotech, algae |
| **SPE Annual Technical Conference** | Houston | Oct 2026 | Oil & gas + MEOR |
| **Texas Biotech Forum** | Houston/Austin | 2026 | Texas biotech companies |
| **TMC Innovation Symposium** | Houston | 2026 | TMC institutions |

**Recommended actions:**
- Poster presentation at ISMB/ECCB 2026: "BioMate: Evidence-Graded QC Governance for 20+ Bioinformatics Domains"
- Exhibit table at Texas Biotech Forum / TMC Innovation Symposium (regional, lower cost)
- Birds-of-a-Feather session at ISMB: "Reproducibility and QC Standards in Bioinformatics"

---

### 6. LinkedIn — The Institutional Decision-Maker Channel
GitHub reaches researchers; LinkedIn reaches lab directors, core facility managers, department chairs, and CTOs.

**Actions:**
- Create BioMate company LinkedIn page
- Post 2x/week: case studies, QC threshold evidence explainers, "10 bioinformatics workflows in 1 platform" posts
- Use LinkedIn Sales Navigator to find and connect with:
  - Bioinformatics Core Facility Directors at Texas universities
  - PIs at TMC institutions running >100 samples/month
  - CRO genomics service heads
  - R&D directors at Texas biotech companies
- Texas AMI: send direct connection requests to identified A/B priority contacts before cold email

---

### 7. Email Campaigns — The Closing Step
Once a relationship exists (GitHub star, preprint citation, conference meeting, LinkedIn connection), email converts at 15–25%.

**Recommended email sequence:**
1. **Day 0**: Personalized intro (reference their specific research + 2 BioMate workflows)
2. **Day 7**: Follow-up with a demo video link (2-minute screen recording)
3. **Day 14**: Social proof email ("3 Houston labs now using BioMate for X")
4. **Day 21**: Final invite code offer with expiry ("Beta closes Feb 28")

Use `outreach_agent.py --output emails --segment texas --priority A` to generate all Day-0 emails.

---

## Texas-Specific Outreach Strategy

### Phase 1: Houston Medical Center Cluster (Weeks 1–4)
**Why first:** Highest concentration of Priority-A targets, all co-located, TMC Innovation Hub is a natural connector.

**Sequence:**
1. Contact TMC Innovation Hub VP — request an institutional demo slot at TMC3
2. Parallel cold email to MD Anderson, BCM HGSC, UTHealth McWilliams, Houston Methodist
3. Offer a "Houston BioMate Workshop" — free half-day workshop at TMC for 20 PIs/postdocs
4. Use the UTMB Bioinformatics & Genomics Lab (Galveston, 50 miles away) as satellite entry

### Phase 2: Dallas Academic + Clinical (Weeks 3–6)
**Anchor:** UT Southwestern Lyda Hill Bioinformatics Department (Chair: Gaudenz Danuser)

**Sequence:**
1. Cold email to Dr. Danuser + 3 other UTSW faculty; reference multi-omics QC paper angle
2. Parallel to ARPA-H Dallas Hub — frame BioMate as infrastructure for funded startups
3. Children's Medical Center Dallas + Baylor Scott & White for clinical genomics angle

### Phase 3: Austin Biotech (Weeks 5–8)
**Anchor:** NeuroX1 (AI drug discovery startup — direct BioMate overlap)

**Sequence:**
1. LinkedIn + cold email to NeuroX1, Colossal Biosciences, XBiotech
2. Austin startup community: connect with Capital Factory biotech portfolio companies
3. UT Austin CCBB + UTEX algae collection — academic anchor in Austin

### Phase 4: Energy-Biology Vertical (Weeks 6–10)
**Unique angle:** No other bioinformatics platform is targeting the MEOR/bioremediation/algae market.

**Sequence:**
1. Cold outreach to Igenbio (Houston) — most direct product fit
2. Contact Dr. Joshua Yuan (TAMU) about synthetic biology / algae genomics use case
3. Reach out to ExxonMobil Advanced Biofuels research team (LinkedIn, not cold email)
4. UTMB BGL (Dr. Fofanov) — industrial/environmental metagenomics
5. Post in SPE (Society of Petroleum Engineers) online community about MEOR genomics

---

## The Energy-Biology Opportunity (Detailed)

Texas is uniquely positioned at the intersection of the world's largest energy industry and a growing genomics infrastructure. **No other bioinformatics platform is serving this market.**

### Use Case 1: MEOR (Microbially Enhanced Oil Recovery)
- **What it is:** Injecting microbes into petroleum reservoirs to produce oil-displacing metabolites (fatty acids, CO2, alcohols)
- **Genomics role:** 16S rRNA and WGS metagenomics characterize the reservoir microbiome; functional annotation identifies metabolite-producing species
- **BioMate fit:** Metagenomics QC + functional annotation workflows; 16S OTU profiling; KEGG/METABOLIC pathway analysis
- **Market:** Every major oil operator in Texas has MEOR research programs
- **Entry point:** Texas A&M Petroleum Engineering Dept + TAMU TIGSS

### Use Case 2: Bioremediation Genomics
- **What it is:** Microbes degrade petroleum contaminants at spill sites
- **Genomics role:** Metagenomics identifies degrader species; functional annotation confirms catabolic gene presence
- **BioMate fit:** Metagenomics + functional annotation + microbiome QC governance
- **Companies:** Igenbio (Houston), Texas Biotech Inc., Advanced Microbial, ETEC
- **Regulatory angle:** EPA compliance reports require standardized, reproducible methods — BioMate's QC audit trail is a direct differentiator

### Use Case 3: Algae Biofuels Synthetic Biology
- **What it is:** Engineered algae strains accumulate high-lipid oil content for biofuel production
- **Genomics role:** Comparative genomics + transcriptomics identifies lipid pathway genes; RNA-seq monitors strain performance
- **BioMate fit:** RNA-seq + WGS + functional annotation + metabolomics integration
- **Companies/labs:** UTEX (UT Austin), TAMU Dr. Joshua Yuan (world record: 43.3 g/m²/day), ExxonMobil (algae program), NREL
- **Angle for BioMate:** "We help you understand *why* your strain performs better — from gene expression to pathway activity"

### Use Case 4: Industrial Fermentation QC
- **What it is:** Scale-up of bio-based chemicals (fatty acids, alcohols, isoprenoids) requires batch-to-batch consistency
- **Genomics role:** RNA-seq monitors culture health; metagenomics detects contamination; proteomics validates enzyme expression
- **BioMate fit:** RNA-seq + proteomics QC with named profiles; FDA 21 CFR Part 11 compliance
- **Market:** Any synthetic biology company doing fermentation (Genomatica, LanzaTech, regional startups)

### Positioning for Energy Companies
> "BioMate is the research execution platform for teams where the biologist has the question and the engineer needs the answer — without hiring a bioinformatician."

---

## National Expansion Priority Order

| Segment | Size | Timeline | Key Hook |
|---|---|---|---|
| Texas (all) | ~82 targets | Month 1–3 | Geographic concentration, energy angle |
| DOE National Labs | ~16 targets | Month 2–4 | BER funding, metagenomics at scale |
| Clinical Labs / CROs | ~18 targets | Month 2–5 | 21 CFR Part 11, FDA audit trails |
| Gulf Coast | ~18 targets | Month 3–5 | Extension of Texas energy corridor |
| Agricultural Belt | ~22 targets | Month 4–7 | Soil microbiome, crop genomics |

---

## Key Metrics to Track

| Metric | Target (Month 3) | Target (Month 6) |
|---|---|---|
| Beta users (Texas) | 50 | 200 |
| Priority-A conversions | 5 | 15 |
| GitHub stars | 200 | 1,000 |
| bioRxiv preprint views | 1,000 | 5,000 |
| Cold email reply rate | >5% | >10% (with prior touchpoint) |
| Energy-sector trials | 2 | 8 |
| DOE lab trials | 1 | 4 |

---

## Budget Sketch (Low-Cost Beta Phase)

| Activity | Cost | Priority |
|---|---|---|
| GitHub + LinkedIn pages | $0 | Now |
| Twitter/X account + content | $0 | Now |
| bioRxiv preprint | $0 | Month 1 |
| Protocol.io method post | $0 | Month 1 |
| r/bioinformatics launch post | $0 | Month 1 |
| nf-core Slack announcement | $0 | Month 1 |
| ISMB 2026 poster | ~$800 registration | Month 4 |
| Texas Biotech Forum exhibit | ~$500 | Month 3 |
| LinkedIn Sales Navigator | ~$100/mo | Month 2 |
| **Total Month 1–3** | **~$600** | |

---

## Quick Wins (This Week)

1. **Tag GitHub repo** with bioinformatics topics (30 minutes)
2. **Create Twitter/X `@BiomateAI`** and post the energy-biology angle (1 hour)
3. **Post in r/bioinformatics**: "Show HN-style: We built a QC governance layer for 20+ bioinformatics domains — beta invite inside" (30 minutes)
4. **Run the agent for Priority-A Texas emails**: `python outreach_agent.py --output emails --segment texas --priority A` — review and send manually (2 hours)
5. **Send the BioMate preprint** to bioRxiv draft queue (pull from Paper 1 intro/methods)
