# BioMate AI × Guo et al. ANDV Campaign: Master Implementation Guide
## Executive Summary & Integration Strategy

**Campaign**: Structure-Based Design of ANDV Therapeutics & Vaccines Leveraging Guo et al. Cryo-EM Structures  
**Total Timeline**: 4 months (parallel execution, Weeks 1–20)  
**Total Budget**: $127–200K (across all tracks)  
**Expected Deliverables**: 16 novel inhibitors + 3 vaccine candidates + 2 pre-prints + regulatory-ready CMC package  
**Strategic Impact**: Proof-of-concept for BioMate's orchestration platform across small molecules, biologics, and immunology  

**Repository alignment**: Implementation markdown uses **semantic pseudocode** (intent shaped like Python; often Claude-authored). It does **not** promise literal `biomate.*` imports. Capabilities map to **workflow-orchestrated** drug-development stages in **`docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md`** (~79% platform coverage at last update). Concrete entry points and notation rules are in **`BIOMATE_CAPABILITY_GAP.md`**. Public PDB/EMDB IDs for Guo structures: **`GUO_ET_AL_CELL2026_READING_NOTES.md`**.

---

## CAMPAIGN OVERVIEW: THREE PARALLEL TRACKS

```
                INHIBITOR TRACK              VACCINE TRACK (PLAN A)          VACCINE TRACK (PLAN B)
                ───────────────              ──────────────────────          ──────────────────────
                Weeks 1–20                   Weeks 1–20 (parallel)           Weeks 1–20 (parallel)
                Budget: $44–57K              Budget: $46–71K                 Budget: $79–107K
                Lead: Comp Chem Team         Lead: Structural Bio Team       Lead: Synth Bio Team
                
                Deliverables:                Deliverables:                   Deliverables:
                • 16 novel ANDV GP inhibitors • 3 protein constructs         • 3 mRNA sequences
                • Bioassay validation (IC50)  • Mouse immunogenicity         • 3 LNP formulations
                • SAR analysis               • Neutralization breadth        • 52-week stability data
                • Pre-print (bioRxiv)        • Pre-print (bioRxiv)          • GMP-ready CMC package
                • GitHub library             • GitHub designs               • Regulatory pathway
```

---

## CRITICAL PATH: WEEK-BY-WEEK EXECUTION

### WEEK 1–2: SETUP & DATA ACQUISITION
```
INHIBITOR TRACK:
  ✓ Obtain ANDV GP tetramer structure (download **9P3I** / **9P3Y** from RCSB; see reading notes)
  ✓ Run AutoSite pocket detection (Biomni `run_autosite` / Galaxy tool)
  ✓ Prepare docking libraries (50K compounds)
  Owner: Comp chem lead
  
VACCINE PLAN A:
  ✓ Extract epitope from Guo's ADI-65534 complex
  ✓ Begin cross-species alignment (ANDV/SNV/PUUV)
  Owner: Structural biology team
  
VACCINE PLAN B:
  ✓ Same epitope work as Plan A (Weeks 1–2 overlap)
  ✓ Begin codon optimization design
  Owner: Synthetic biology team
```

### WEEK 3–4: DISCOVERY & DESIGN
```
INHIBITOR:
  ✓ Complete virtual screening (50K → 50 hits)
  ✓ ADMET triage
  Output: Hit list + top 50 compounds for CRO
  
VACCINE A:
  ✓ Complete MHC-peptide predictions
  ✓ Design 3 immunogen constructs
  Output: Construct sequences ready for expression
  
VACCINE B:
  ✓ Complete mRNA sequence optimization
  ✓ Design LNP formulations (top 3)
  Output: Full mRNA designs + LNP specs
  
CRO Orders Placed:
  • Enamine/WuXi Express: 6 inhibitor compounds (delivery Week 5–6)
  • Genscript/SinoBio: 3 proteins (delivery Week 8–12)
  • Ology/Synthego: 3 mRNA GMP (delivery Week 11–12)
  • Evonik/Acuitas: LNP formulation (delivery Week 12–16)
```

### WEEK 5–9: CRO EXECUTION & ITERATION
```
INHIBITOR:
  ✓ CRO delivers Round 1 compounds
  ✓ Bioassays (pseudotype, SPR, selectivity)
  ✓ Bayesian optimizer proposes Round 2 (10 compounds)
  Output: Experimental data + next design cycle
  
VACCINE A:
  ✓ CRO protein expression underway
  ✓ Mouse facility reserve + protocol IACUC approval
  
VACCINE B:
  ✓ GMP mRNA synthesis underway
  ✓ Stability testing protocol initiated (parallel)
```

### WEEK 10–15: OPTIMIZATION & CHARACTERIZATION
```
INHIBITOR:
  ✓ CRO delivers Round 2 compounds
  ✓ Complete bioassay panel
  ✓ SAR analysis + mechanistic insights
  Output: 16 fully characterized inhibitors
  
VACCINE A:
  ✓ CRO proteins delivered
  ✓ QC characterization (SDS-PAGE, DLS, thermal stability)
  ✓ Mouse immunizations begin (Week 9)
  ✓ ELISA titering underway
  
VACCINE B:
  ✓ GMP mRNA delivered
  ✓ LNP encapsulation underway
  ✓ Real-time stability initiated (Week 8, continues through Week 52)
  ✓ Mouse immunizations begin (Week 9)
```

### WEEK 16–18: DATA ANALYSIS & PUBLICATION PREP
```
INHIBITOR:
  ✓ Final SAR analysis complete
  ✓ Docking visualizations generated
  ✓ Manuscript draft (Methods, Results, Figures)
  Output: Pre-print ready
  
VACCINE A:
  ✓ Mouse data complete (pseudotype, ELISPOT, flow)
  ✓ Neutralization breadth analysis
  ✓ Manuscript draft
  Output: Pre-print ready
  
VACCINE B:
  ✓ Mouse data complete (same assays as A)
  ✓ Stability data summary (Weeks 1–16 timepoints analyzed)
  ✓ Manuscript draft + CMC documentation
  Output: Pre-print + regulatory package ready
```

### WEEK 19–20: PUBLICATION & RELEASE
```
INHIBITOR:
  ✓ bioRxiv submission (Week 18)
  ✓ GitHub repository live
  ✓ Social media announcement
  Output: Public data + open science
  
VACCINE A:
  ✓ bioRxiv submission
  ✓ GitHub live (vaccine designs)
  ✓ Academic collaboration offers expected
  
VACCINE B:
  ✓ bioRxiv submission
  ✓ GitHub live (mRNA + LNP + regulatory docs)
  ✓ GMP CRO outreach (contract offers for manufacturing)
```

---

## BUDGET ALLOCATION & PHASING

### TOTAL INVESTMENT BY PHASE

**Phase 1 (Setup & Discovery): Weeks 1–4 (~$5K)**
```
AutoSite pocket analysis          ~$500
Virtual screening (Vina/Glide)    ~$2,000 (cloud compute)
Epitope extraction & alignment    ~$500
mRNA design tools                 ~$1,000
TOTAL                             ~$4,000
```

**Phase 2 (Manufacturing & Synthesis): Weeks 5–16 (~$110–150K)**
```
CRO Inhibitor Synthesis (16 compounds)    $35–50K
CRO Protein Expression (3 constructs)     $19–30K
CRO mRNA Synthesis (3 constructs)         $24–30K
CRO LNP Formulation (9 batches)           $27–36K
TOTAL                                     $105–146K
```

**Phase 3 (Validation & Characterization): Weeks 8–18 (~$15–25K)**
```
Bioassays (pseudotype, selectivity)       $12–18K (all tracks)
Mouse immunogenicity (3 groups × 2 plans) $8–12K
Stability testing (real-time)             $5–8K
TOTAL                                     $25–38K
```

**Phase 4 (Manuscript & Publication): Weeks 16–20 (~$10–20K)**
```
Manuscript writing & editing              $5–10K
Figure design & generation                $3–5K
Regulatory documentation (Plan B)         $2–5K
TOTAL                                     $10–20K
```

**GRAND TOTAL**: **$144–224K**

**Recommended Allocation**: **$150–180K** (mid-range, realistic)

---

## WHICH VACCINE PLAN TO CHOOSE?

### DECISION MATRIX

| Factor | Plan A (Protein/VLP) | Plan B (mRNA-LNP) | Recommendation |
|--------|----------------------|-------------------|---|
| **Scientific Risk** | Lower (protein easier to validate) | Moderate (manufacturing dependency) | Choose Plan A if... cautious |
| **Timeline (to Phase 1)** | 21 weeks | 14 weeks (7 week savings) | Choose Plan B if... speed critical |
| **Pandemic Deployment** | 9–12 months | 6 months | Choose Plan B if... pandemic focus |
| **Regulatory Precedent** | Limited (unique vaccine) | Strong (COVID mRNA) | Choose Plan B if... regulatory confidence needed |
| **Manufacturing Complexity** | Standard (biotech sector knows) | Specialized (microfluidics) | Choose Plan A if... supply chain constrained |
| **Cost/Dose** | $20–50 | $2–5 | Choose Plan B if... global access is goal |
| **Cold Chain** | −20°C or colder | 4°C (easier logistics) | Choose Plan B if... deploying to resource-limited settings |
| **Budget Required** | $46–71K | $79–107K | Choose Plan A if... budget tight |

### SCENARIOS WHERE EACH WINS

**Choose Plan A (Protein/VLP) if**:
- Budget is constrained (<$60K available)
- Regulatory pathway speed is NOT critical
- You want to de-risk scientific validation (protein folding is well-understood)
- Academic partnerships are primary channel (universities know protein expression)

**Choose Plan B (mRNA-LNP) if**:
- Pandemic preparedness is the strategic goal (BioMate's value prop)
- You want to compete with Moderna/BioNTech (platform play)
- Cold chain logistics matter (4°C vs. −80°C is huge advantage)
- Manufacturing scalability is critical (6 months → 1000 doses vs. 9 months → 100 doses)

### OPTIMAL STRATEGY: DO BOTH

**Phased Approach**:
```
Q2 2026: Execute Inhibitor Track + Vaccine Plan A (full proof-of-concept)
         Budget: $90K, Timeline: 4 months
         Deliverable: Two pre-prints + mouse data + regulatory package

Q3 2026: Launch Vaccine Plan B (mRNA optimization track)
         Use Plan A mouse data to support Plan B regulatory pathway
         Budget: Additional $90K (incremental)
         Deliverable: GMP-ready mRNA-LNP platform + 1-year stability data

Q4 2026: Integrate results for Series A narrative
         "BioMate executed two parallel vaccine development tracks in parallel,
          de-risking both protein and mRNA approaches. mRNA chosen for pandemic
          deployment. Both validated with mouse immunogenicity."
```

---

## SERIES A NARRATIVE

### "BioMate Solved the ANDV Problem in 4 Months Using Its Orchestration Platform"

**Headline Story**:
> "What would take a traditional biotech 2–3 years, BioMate completed in 4 months: structure-based design of novel ANDV therapeutics and vaccines, validated experimentally, ready for regulatory filing."

**Key Talking Points**:

1. **Structural Biology as Input**
   - Guo et al.'s cryo-EM structures = "the invasion keys to hantavirus"
   - BioMate's orchestration layer = "turns structures into treatments"

2. **Three Simultaneous Tracks**
   - Inhibitor design (DMTA loop): 16 novel compounds, IC50 validation
   - Vaccine design (epitope discovery): 3 immunogens, mouse immunogenicity
   - Manufacturing pathway (mRNA-LNP): GMP-ready, 6-month deployment

3. **Speed Advantage**
   - Traditional: Target → Hit → Lead → Preclinical → IND ≈ 3 years
   - BioMate: Target (Guo's structure) → Lead (our DMTA) → IND-ready ≈ 4 months
   - Savings: $2–5M in R&D spend, 18+ months in timeline

4. **Pandemic Readiness Proof**
   - If hantavirus pandemic emerges: mRNA vaccine deployable in 6 months
   - Next pathogen: Apply same platform (genomics → vaccine in 8 weeks)
   - This is the AI startup capability the world needs post-COVID

5. **Customer Use Case**
   - Biotech CMO/CRO now offer "AI-accelerated discovery" to pharma clients
   - One license deal = $10M+ in contract value
   - BioMate becomes the infrastructure layer for urgent discovery

---

## IMPLEMENTATION CHECKLIST FOR CLAUDE CODE

### PRE-CAMPAIGN (Before Week 1)

- [ ] **Download deposited coordinates** (RCSB / EMDB) — **9P3I**, **9P3Y**; optional **9P3X / 9P3M / 9P3L** for ensemble modeling (see `GUO_ET_AL_CELL2026_READING_NOTES.md`). Optional: contact lead author only for **reagents** (e.g. antibodies), not PDB access.

- [ ] **CRO Selection & Vetting**
  - [ ] Inhibitor synthesis: Enamine / WuXi Express (vetted pricing)
  - [ ] Protein expression: Genscript / Sino Biologics (mammalian expertise)
  - [ ] mRNA GMP synthesis: Ology / Synthego / Aldevron (GMP certified)
  - [ ] LNP formulation: Evonik / Acuitas / Arcturus (microfluidic equipment)
  - [ ] Bioassays: Charles River / Inotiv (pseudotype + ELISPOT capability)

- [ ] **Budget Approval & Fund Allocation**
  - [ ] Confirm $150K seed round allocation for campaign
  - [ ] Establish vendor accounts (setup A/P, SOWs)
  - [ ] Insurance & liability coverage for animal studies

- [ ] **Regulatory & Compliance**
  - [ ] IACUC approval (mouse protocol) — submit Week 1
  - [ ] Vivarium reservation (mouse facility)
  - [ ] Biosafety review (if live hantavirus work planned; probably not)
  - [ ] Publication clearance (pre-press embargo with collaborators)

- [ ] **Partner Coordination**
  - [ ] Draft outreach email to Guo Luqiang (template provided)
  - [ ] Identify academic collaborators for mouse work (university contacts)
  - [ ] Media/PR plan (embargo until bioRxiv submission)

---

### WEEKLY EXECUTION TASKS

**Week 1:**
- [ ] Download / checksum deposited structures (**9P3I**, **9P3Y**; optional ensemble PDBs)
- [ ] Submit IACUC protocol for mouse studies
- [ ] Reserve mouse facility (Weeks 9–16)
- [ ] Generate docking libraries (50K compounds)

**Weeks 2–3:**
- [ ] Complete AutoSite pocket identification
- [ ] Begin cross-species epitope alignment
- [ ] Design LNP formulation matrix
- [ ] Place inhibitor CRO order (6 compounds, delivery Week 5–6)

**Weeks 4–5:**
- [ ] Complete virtual screening (Vina → Glide → DiffDock)
- [ ] Finalize immunogen construct designs
- [ ] Complete mRNA sequence optimization
- [ ] Place protein/mRNA CRO orders

**Weeks 6–10:**
- [ ] Monitor inhibitor CRO synthesis + bioassays
- [ ] Monitor protein expression + QC
- [ ] Monitor GMP mRNA synthesis
- [ ] Perform Bayesian optimization (Round 2 inhibitors)
- [ ] Begin mouse immunizations (Week 9)

**Weeks 11–15:**
- [ ] Receive LNP-formulated batches
- [ ] Continue mouse immunogenicity assays
- [ ] Complete Round 2 inhibitor synthesis + assays
- [ ] Initiate real-time stability testing

**Weeks 16–18:**
- [ ] Finalize all experimental data
- [ ] Generate figures & tables
- [ ] Draft manuscripts (all 3 tracks)
- [ ] Complete GitHub repository structure

**Weeks 19–20:**
- [ ] Submit pre-prints (bioRxiv)
- [ ] Release GitHub repositories
- [ ] Announce results (press/social media)
- [ ] Initiate academic collaboration outreach

---

## SUCCESS CRITERIA (GO/NO-GO AT WEEK 16)

### INHIBITOR TRACK: HARD STOP if
- ❌ <10 compounds show IC50 < 3 µM (weak hits)
- ❌ >50% of compounds fail ADMET (prediction model poor)
- ❌ Predicted vs. measured IC50 correlation r < 0.5 (docking unreliable)

### VACCINE PLAN A: HARD STOP if
- ❌ Zero compounds show neutralization across any species
- ❌ CD8+ T-cell response undetectable (<50 SFU/million)
- ❌ Protein constructs aggregate/misfold (>20% aggregation)

### VACCINE PLAN B: HARD STOP if
- ❌ LNP encapsulation efficiency <75%
- ❌ Stability at 4°C <4 weeks (shelf-life too short)
- ❌ Transfection efficiency <50% in vitro

### IF ANY HARD STOPS TRIGGERED:
→ Pivot to Plan A only (less risky)
→ Reduce scope (1 vaccine construct instead of 3)
→ Extend timeline (6 months instead of 4)
→ Reallocate budget to de-risking steps

---

## DOCUMENTATION PACKAGES FOR CLAUDE CODE

### INPUT FILES NEEDED:
1. `ANDV_INHIBITOR_TRACK_IMPLEMENTATION.md` (this archive)
2. `ANDV_VACCINE_PLAN_A_PROTEIN_VLP_IMPLEMENTATION.md`
3. `ANDV_VACCINE_PLAN_B_mRNA_LNP_IMPLEMENTATION.md`
4. Guo et al. structures — **RCSB download** (9P3I, 9P3Y, …) per `GUO_ET_AL_CELL2026_READING_NOTES.md`
5. Library SDF files (vendor-provided)

### OUTPUT DELIVERABLES:
1. **Python Pipeline Code**
   - `workflow_inhibitor_discovery.py`
   - `workflow_vaccine_epitope.py`
   - `workflow_vaccine_mrna.py`
   - `workflow_lnp_formulation.py`

   **BioMate routing (in silico)**: Epitope and MHC binding steps map to the indexed pipeline **`nf-core/epitopeprediction`** (workflow DB id **12700**), not a literal `workflow_vaccine_epitope.py` in this repository. See `BIOMATE_CAPABILITY_GAP.md` and the BioMate note at the end of `ANDV_VACCINE_PLAN_A_PROTEIN_VLP_IMPLEMENTATION.md`.

2. **Data Processing Scripts**
   - `analyze_docking_results.py`
   - `process_bioassay_data.py`
   - `integrate_stability_data.py`
   - `generate_figures.py`

3. **CRO Specification Templates**
   - `cro_order_inhibitor_synthesis.txt`
   - `cro_order_protein_expression.txt`
   - `cro_order_mrna_synthesis.txt`
   - `cro_order_lnp_formulation.txt`

4. **Manuscript Templates**
   - `manuscript_inhibitor_outline.md`
   - `manuscript_vaccine_plan_a_outline.md`
   - `manuscript_vaccine_plan_b_outline.md`

5. **GitHub Repository Structure**
   - Directory trees for all three projects
   - README templates
   - LICENSE files (CC-BY 4.0)

6. **Regulatory Documentation**
   - CMC module outline (Plan B)
   - IACUC protocol template
   - GMP manufacturing SOP template

---

## RISK MITIGATION

### TECHNICAL RISKS & CONTINGENCIES

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Coordinate quality / construct mismatch (DM-eVLP vs assay WT) | Medium | Medium | Document which PDB maps to which assay; use ensemble 9P3X/M/L if needed |
| Virtual screening hits weak (IC50 > 5 µM) | Medium | Medium | Pre-screen compounds for druggability; use more stringent filters |
| mRNA GMP synthesis delays | Low | High | Select backup CRO (Synthego, Ology both capable) |
| LNP stability poor at 4°C (<4 weeks) | Low | High | Pivot to −20°C formulation (less pandemic-friendly but workable) |
| Mouse immunogenicity weak | Medium | High | Use Freund's adjuvant (stronger but less clinical-relevant) |
| Timeline slippage (delays from CROs) | Medium | Medium | Add 2-week buffer in planning; parallel execution of independent workstreams |

### CONTINGENCY TIMELINE

```
If inhibitor hits are weak (Week 10):
  → Focus on vaccine tracks (not a campaign failure)
  → Pivot inhibitor to ADMET optimization only (no in vitro validation)

If one vaccine plan underperforms (Week 14):
  → Lean on other plan (publish separately)
  → Don't force combined manuscript

If critical manufacturing delay (Week 12):
  → Execute animal studies with stock LNP formulations (not optimized)
  → De-scope optimization, focus on immunogenicity proof

If timeline slips to Week 24 (6-month campaign):
  → Still acceptable for Series A narrative
  → "More rigorous validation" messaging
```

---

## SERIES A TALKING POINTS

### When Pitching This Campaign to Investors

**"Investors, here's why this matters:"**

> "In 4 months, BioMate's AI orchestration platform went from zero to IND-ready inhibitors and vaccines for a 40% fatal-rate virus. We didn't invent new biology. We orchestrated existing tools (docking, mRNA synthesis, LNP formulation) through an AI layer that made non-coding scientists productive.

> This proves our thesis: **the rate-limiting step in biotech is not science—it's engineering. Orchestration. Automation of decision-making.**

> We can now apply this same playbook to any pathogen. Next novel virus emerges? We have an 8-week mRNA vaccine deployed before public health even issues a travel warning.

> Our customers are biotech companies, CDMOs, and governments. One licensing deal with a pharma company = $10–50M. One government contract for pandemic preparedness = $100M+.

> This ANDV campaign is not a research project. It's a market validation study showing our platform works at scale."

---

## SUCCESS METRICS FOR SERIES A

### Financial Impact
- ✅ One academic collaboration offer → Co-authored paper (profile-building)
- ✅ One CRO/CDMO inquiry re: "AI-accelerated discovery services" ($5–10M potential)
- ✅ One government contact (CDC/DARPA/BARDA) → Pandemic preparedness discussion
- ✅ Media coverage (Science Daily, STAT News, Nature News) → 50K+ impressions

### Scientific Impact
- ✅ 2 pre-prints on bioRxiv (inhibitor + vaccine)
- ✅ 16 novel compounds + 3 vaccine candidates as public goods (GitHub)
- ✅ Proof that BioMate's platform enables multi-modality drug discovery (small molecules, biologics, immunology)
- ✅ Regulatory package ready for IND submission (if partners want to advance)

### Strategic Impact
- ✅ Differentiation from competitors (Benchling is LIMS; BioMate is scientist assistant)
- ✅ Proof of pandemic deployment speed (6 months vs. traditional 2–3 years)
- ✅ Evidence for AI moat (not just faster, but fundamentally different approach)
- ✅ Customer testimonials from CROs/biotech ("We used BioMate to...")

---

## NEXT STEPS: IMMEDIATE ACTIONS (This Week)

### For Yaoyun:

1. **Contact Guo Luqiang**
   - Email: Contact via UT Austin biomedical informatics directory
   - Subject: "Collaborative Application of AI-Driven Drug Discovery to Your ANDV Structures"
   - Attachment: "ANDV_Guo_Collaboration_Proposal.pdf" (draft provided)

2. **Secure Budget Approval**
   - Confirm $150–180K allocation from seed round
   - Internal meeting: FP&A + technical founders to approve CRO spending

3. **Establish Vendor Relationships**
   - [ ] Schedule calls with Enamine/WuXi, Genscript, Ology, Evonik
   - [ ] Negotiate pricing (bulk discounts if multi-track)
   - [ ] Set up accounts & establish SOWs

4. **Initiate Regulatory Work**
   - [ ] Submit IACUC protocol (Week 1)
   - [ ] Reserve mouse facility
   - [ ] Compliance review (biosafety, IRB clearance if needed)

5. **Assemble Teams**
   - [ ] Comp Chem: Lead inhibitor track (1 FTE)
   - [ ] Structural Bio: Lead vaccine epitope work (1 FTE)
   - [ ] Synth Bio: Lead mRNA optimization (0.5 FTE)
   - [ ] Immunology: Support mouse assay design (0.5 FTE)

---

## FINAL WORD: WHY THIS CAMPAIGN MATTERS FOR BIOMATE

This isn't just a vaccine/inhibitor development project. **This is proof of BioMate's core value proposition:**

> **"BioMate is the AI orchestration layer that turns scientists into 10x researchers. Not by replacing them, but by automating the boring parts (parameter optimization, design cycles, data integration) so they can focus on creative thinking."**

ANDV campaign demonstrates:
- ✅ Multi-modality orchestration (small molecules + biologics + immunology)
- ✅ Speed (4 months instead of 2–3 years)
- ✅ Regulatory readiness (IND-ready package, not just research)
- ✅ Public health impact (open-source, pandemic-relevant)
- ✅ Commercial potential (CRO/pharma customers, licensing models)

**If this campaign succeeds, BioMate's Series A becomes:**
- **Headline**: "The AI Company Behind Novel ANDV Therapeutics"
- **Positioning**: "Not a discovery tool. An orchestration platform."
- **Valuation**: Justify $50–100M Series A on proof-of-concept (Guo structures → ready-to-file package in 4 months)

---

## CONTACT & COLLABORATION

**For Yaoyun to send to collaborators:**

```
Subject: BioMate AI × Guo et al. ANDV Campaign: Collaboration Opportunity

Dear Dr. Guo,

Your Cell paper on Andes virus glycoprotein structures is foundational work that enables 
rational antiviral design. BioMate AI has built a computational orchestration platform 
for drug discovery spanning structure-based design, immunogen engineering, and manufacturing 
optimization. We'd like to propose a collaboration:

Over the next 4 months, BioMate will apply its platform to your ANDV structures to design:

1. NOVEL ANDV INHIBITORS (15–20 compounds)
   - Structure-based docking → ADMET optimization → synthetic validation
   - Predicted vs. measured IC50 correlation
   - Publication: "Structure-Based Design of ANDV Glycoprotein Inhibitors"

2. BROAD-SPECTRUM VACCINE CANDIDATES (3 immunogens)
   - Epitope discovery from your structures
   - Cross-reactivity modeling (ANDV/SNV/PUUV)
   - Mouse immunogenicity proof-of-concept
   - Publication: "Rational Immunogen Design for Broad-Spectrum Hantavirus Protection"

TIMELINE: 4 months to pre-prints + GitHub release (open science)
COST TO YOU: Zero (BioMate funds all CRO & animal work)
BENEFIT: Co-authorship on high-impact follow-up papers + acceleration of your program's 
         translational pipeline

Would you be open to a call to discuss?

Best regards,
Yaoyun [BioMate AI]
```

---

**Campaign Status**: READY FOR IMPLEMENTATION  
**Last Updated**: April 2026  
**Prepared For**: Claude Code automated execution

