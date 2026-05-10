# BioMate Marketing & Positioning Strategy — 2026-05-09

## The Core Problem: Discovery Gap

BioMate has `OpenFE RBFE`, `TxGNN`, `STATE virtual cell`, `REINVENT4`, `adaptive_trial_design` with O'Brien-Fleming stopping rules, `simcyp_pbpk`, cryo-EM full pipeline. These are tools that cost $50K–$500K/year from Schrödinger, Certara, or Simulations Plus. A pharma scientist who knew BioMate had all this would pay for it immediately. The problem is not what we have — it's that **the product doesn't surface its own depth**.

Marketing sends people to the product. If the product doesn't communicate its value in the first session, marketing spend is wasted. Fix the product surface first.

---

## Layer 1: Fix the Product Surface (before any marketing)

### A. Job-to-be-done entry point
A dedicated page or chat command showing curated capability clusters, not a flat workflow list:
- "I have a compound and need IND-ready ADMET + PBPK" → 6-workflow chain
- "I have a cryo-EM map, I need a depositable structure" → CryoSPARC → ModelAngelo → Phenix
- "My lead has hERG liability, I need optimized analogs" → ADMET → REINVENT4 MPO loop

### B. Capability comparison table
One page: "Tools equivalent to what BioMate covers"

| BioMate Workflow | Commercial Equivalent | Commercial Price |
|---|---|---|
| `OpenFE Relative Binding Free Energy` | Schrödinger FEP+ | ~$100K+/year |
| `simcyp_pbpk` | Simulations Plus SimCYP | ~$40K+/year |
| `nlmixr2_population_pk` | NONMEM (Icon) | ~$30K+/year |
| `REINVENT4 Generative Lead Design` | Schrödinger REINVENT | ~$80K+/year |
| `Predict ADMET Properties (AI)` | StarDrop (Optibrium) | ~$20K+/year |
| `adaptive_trial_design` (MAMS+RAR) | East Adaptive (Cytel) | ~$25K+/year |
| `Retrieve Topk Repurposing Drugs (TxGNN)` | Drug repurposing CRO engagement | ~$50K+/project |

**Stack cost to replicate: ~$500K+/year. BioMate covers it all.**

### C. Proactive routing suggestions in the AI
When a user runs an ADMET workflow and gets a hERG flag, the AI should say:
> "I can also run REINVENT4 in scaffold decoration mode with a hERG penalty to generate optimized analogs — would you like that?"

When a rare disease variant analysis completes:
> "I found variants in [gene]. Would you like me to query TxGNN to identify approved drugs that may be repurposable for this condition?"

This surfaces depth at the moment of relevance, inside the product, with no marketing budget.

---

## Layer 2: Niche Positioning — One Defensible Claim

**The niche:**
> "The only platform that runs IND-ready computational drug development end-to-end — from hit to §2.6 clinical narrative — in a single conversational interface."

**What this means concretely:**
A pharma team uploads a SMILES list on Monday. By Friday they have:
- ADMET screening with QC gates
- PBPK simulation with disease-state adjustments
- BOIN dose escalation design with operating characteristics
- Biomarker enrichment analysis for Phase II enrichment
- §2.6.1 LLM regulatory narrative
- CRO submission package

All in one place. All traceable. All exportable in FDA-compatible formats. No Schrödinger license, no SimCYP consultant, no CRO.

**No competitor does this end-to-end:**
- Benchling: lab data management
- Dotmatics: assay tracking
- Schrödinger: molecular simulation (expensive, siloed)
- Certara: PBPK consulting (people-based, not software)
- Nobody strings these into one conversational workflow with regulatory output

The moat is not individual tools — it is the **integrated workflow from biological question to regulatory-ready output**. That is what has never been done before.

---

## Layer 3: Go-to-Market — Model 3 Mechanics (100 clients × $10K+)

### A. Target the "IND filing crunch" moment
Biotech companies at Series A/B face a specific crunch: lead compound, IND-enabling studies needed, but $500K–$2M CRO engagement is out of reach. They need the ADMET/PBPK/dose package in 4–8 weeks on a ~$50K budget. BioMate is the exact answer.

**How to find them**: Watch Crunchbase/BioSpace for "Series A" + "preclinical" + "IND". One SDR generates a qualified lead list weekly. Outreach message: "You're 6 months from IND. Here's how we compress 3 months of CRO work into 2 weeks."

### B. Academic-to-industry translation labs
University pharma/medicinal chemistry groups that consult for industry or spin out companies. They have the science but not the $500K software stack. BioMate at $500–$2K/month is cheaper than one Schrödinger seat. Reachable at ACS, AAPS, SLAS conferences or direct LinkedIn/ResearchGate outreach.

### C. CROs as channel partners
Mid-size CROs (not top-5) need computational capabilities to stay competitive but can't afford full Schrödinger/Certara stacks. BioMate API/white-label tier lets a CRO sell "AI-augmented ADMET + PBPK" while BioMate runs the backend. Distribution without a sales force.

### D. Technical content (not ads)
The target buyer reads papers and technical blogs. Highest-ROI content:
1. **Case study**: "IND-ready PBPK package for a hERG-flagged compound in 72 hours" — real numbers, real outputs
2. **Technical post**: "Why TxGNN + variant calling changes rare disease drug discovery" → demo link (Towards Data Science / LinkedIn)
3. **Benchmark publication**: Publish BioMate ADMET/PBPK/BOIN benchmark scores publicly — scientist credibility comes from verifiable performance claims

---

## Execution Sequence

### This week
- [ ] Write capability comparison table as in-product page (`/capabilities` route)
- [ ] Add proactive suggestions in AI: ADMET hERG flag → offer REINVENT4; raredisease VCF → offer TxGNN chain
- [ ] Fix routing rules so TxGNN/OpenFE/STATE/GEARS/REINVENT4 are discoverable from plain-English queries

### This month
- [ ] Build siRNA generation workflow (closes the generation → off-target loop)
- [ ] Publish one case study (use a published compound like imatinib — run full IND stack, document every output)
- [ ] Add FDA audit trail JSON to clinical trial workflows

### This quarter
- [ ] IND crunch outreach campaign (Crunchbase + BioSpace Series A list)
- [ ] CRO channel partner outreach (5 mid-size CROs)
- [ ] Conference presence: AAPS, SLAS (poster/talk on BioMate benchmark results)
- [ ] ADMET → REINVENT4 closed MPO loop workflow

---

## Therapeutic Modality Coverage (updated 2026-05-09)

BioMate covers every major modality in active clinical development:

| Modality | Status | Key workflows |
|---|---|---|
| Small molecule | Excellent | ADMET, REINVENT4, OpenFE RBFE, PBPK, BOIN |
| mRNA therapeutics | Good (chain needed) | P0_mrna_validation, lnp_formulation_optimization |
| siRNA / RNAi | Good | sirna_design_full → sirna_offtarget_analysis |
| Antibody (mAb, scFv, bispecific) | Good | scfv_antibody_design, bispecific_antibody_design, antibody_developability |
| CRISPR gene editing | Good | crisprDesign, crisprScore, MAGeCK, GEARS |
| Vaccines / epitopes | Good | nf-core/epitopeprediction, codon optimization |
| Large protein / cryo-EM | Good | CryoSPARC, RELION, nf-core/proteinfold |
| Radiopharmaceuticals | Partial | Dosimetry, radiolabeled antibody PK |
| ADC | Partial gap | Antibody + payload ADMET separate; no integrated ADC workflow |
| CAR-T / cell therapy | Partial gap | scFv design + scRNA-seq separate; no CAR construct workflow |
| PROTAC / molecular glue | Gap | Nothing indexed |

**Three additions that complete full modality coverage:**
1. **ADC workflow** — fastest growing cancer drug class; no platform has this end-to-end
2. **PROTAC/degrader** — complete gap; 5 compounds in Phase II/III
3. **mRNA full pipeline** — chain existing pieces; minimal work; very high market signal

---

## The One-Sentence Pitch

> "BioMate is the AI platform that takes a drug candidate from molecule to IND submission package — across every major therapeutic modality — in a single conversation, replacing $500K/year of disconnected pharma software and a 6-person specialist team."
