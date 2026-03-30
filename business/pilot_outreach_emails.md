# BioMate AI — Pilot Study Outreach Emails

**Five personalised emails for pilot study partner recruitment**
**March 2026 | Confidential — Internal Use Only**

---

## Email A — Drug Discovery | UT Southwestern Simmons Cancer Center

**To:** [Bioinformatics Core Director Name], Bioinformatics Core, UT Southwestern Simmons Cancer Center
**From:** [Your Name], BioMate AI
**Subject:** BioMate AI — 4-week pilot for ADMET & molecular docking workflows

---

Dear [Dr. Last Name],

I am writing because UT Southwestern's oncology drug programs are exactly the kind of context where BioMate can save your team real time — and I would like to propose a short, zero-cost pilot to demonstrate that.

BioMate is an AI platform that converts a plain-language research query into a fully parameterised Nextflow workflow — end to end, with QC gates drawn from published community standards. No pipeline configuration by hand. No tool installation. Every run produces an exportable QC audit log and a methods section block your team can drop directly into a manuscript.

For the pilot, I am proposing four weeks focused on two workflows your core likely runs regularly: **ADMET property screening** and **molecular docking**. You provide 10–20 real compounds (SMILES strings) and one researcher to evaluate the outputs. BioMate covers all compute costs. At the end, you get a QC audit log showing per-compound pass rates, hERG and Lipinski flags, and docking scores — plus a side-by-side comparison of time-to-result versus your current process.

There is no data agreement complexity here — compound SMILES are not protected health information, and we can sign a simple one-page data handling agreement before we start.

Would a 20-minute call this week work? I am happy to walk through the platform live.

Best regards,
[Your Name]
BioMate AI
[phone] | [email]

---

## Email B — RNA-seq / Precision Medicine | Texas Children's Hospital

**To:** [Research Scientist / PI Name], Department of Pediatric Oncology, Texas Children's Hospital Research Institute
**From:** [Your Name], BioMate AI
**Subject:** BioMate AI — AI-powered RNA-seq pipeline pilot (pediatric cancer cohorts)

---

Dear [Dr. Last Name],

Pediatric cancer genomics cohorts generate exactly the kind of complex, multi-sample RNA-seq data where pipeline configuration overhead becomes a real bottleneck. I wanted to reach out because BioMate was designed to address this directly — and I think a short pilot on data similar to what your team is already working with could be genuinely useful.

BioMate takes a plain-language description of your analysis and produces a fully configured Nextflow pipeline — FastQC → STAR alignment → DESeq2 differential expression → pathway enrichment via g:Profiler — in under 30 seconds. The platform applies QC gates from ENCODE and published pediatric oncology standards, and generates an HTML report with a methods section block suitable for manuscript submission.

For the pilot, I am proposing a four-week engagement running the full RNA-seq pipeline on a pediatric cancer dataset. We can start with a publicly available GEO dataset (for example, GSE182497 or a comparable pediatric ALL cohort) and transition to your internal cohort data at any point — data governance is handled through the platform's Terms of Service accepted at registration, with no separate agreement required.

Your team gets: a QC report showing mapping rates, duplicate rates, inter-replicate correlation, and differential expression results, plus a ready-to-use methods paragraph. We cover all compute costs.

I would be glad to do a live demo this week if that is easier than a call. Would 20 minutes work?

Best,
[Your Name]
BioMate AI
[phone] | [email]

---

## Email C — Cryo-EM | UT Southwestern Cryo-EM Facility

**To:** [Facility Director Name], Cryo-EM Facility, UT Southwestern Medical Center
**From:** [Your Name], BioMate AI
**Subject:** BioMate AI — automated CryoSPARC SPA pipeline pilot

---

Dear [Dr. Last Name],

Cryo-EM facilities face a consistent challenge: the microscope time is scheduled and optimised, but the downstream SPA processing pipeline is often a bottleneck — parameter tuning, CTF fit, particle picking thresholds. BioMate is designed to remove that bottleneck.

BioMate converts a plain-language query into a fully configured CryoSPARC Standard Single-Particle Analysis pipeline, including patch CTF estimation, 2D classification, ab initio reconstruction, and homogeneous refinement. QC gates are drawn from EMDB deposition standards — resolution estimate, CTF fit score, and particle count — so researchers know before they submit whether their map meets publication thresholds.

For the pilot, I am proposing a four-to-six week engagement running the SPA pipeline on micrographs from your existing queue, or on an EMDB-deposited dataset if that is easier for a first run. UT Southwestern's facility would contribute one researcher's time to evaluate the outputs; BioMate covers compute. At the end, you receive a refined map plus a QC report with resolution estimate, B-factor, and CTF statistics aligned to EMDB submission requirements.

If this is useful to even a fraction of the datasets moving through your facility, it could meaningfully shorten the time between data collection and manuscript submission for your users.

Would you be open to a brief call to see if this fits anything in your current queue?

Best,
[Your Name]
BioMate AI
[phone] | [email]

---

## Email D — Single-Cell Perturbation | Baylor College of Medicine

**To:** [Research Scientist Name], Center for Cell and Gene Therapy, Baylor College of Medicine
**From:** [Your Name], BioMate AI
**Subject:** BioMate AI — scRNA-seq pilot for cell therapy immune profiling

---

Dear [Dr. Last Name],

Cell therapy programs generate rich single-cell data — and the analytical pipeline from raw counts to a publication-ready cell atlas is still time-consuming to configure correctly. I am reaching out because BioMate can automate that pipeline end to end, and I think it maps well to the kind of work happening at BCM's Center for Cell and Gene Therapy.

BioMate takes a plain-language description and produces a configured Seurat or Scanpy pipeline — QC filtering → normalisation → clustering → UMAP → cell-type annotation — in seconds. The platform flags cells that fall below quality thresholds (mitochondrial fraction, UMI count, doublet probability) using published community standards and produces an annotated cell atlas with a differential abundance report between conditions.

For the pilot, I am proposing a two-month engagement. Month 1: run the full scRNA-seq clustering and cell-type annotation pipeline on your existing single-cell data — you keep all outputs and the QC report. Month 2 (if the data is ready): extend to CRISPR screen integration and perturbation analysis. Your team provides one researcher to evaluate outputs; BioMate covers compute.

The deliverable from Month 1 is an annotated cell atlas, a differential abundance report, and a methods section block ready for a manuscript or grant application.

Would a short demo call this week be useful?

Best,
[Your Name]
BioMate AI
[phone] | [email]

---

## Email E — Multi-Omics / Proteomics | St. Jude Children's Research Hospital

**To:** [Research Scientist / Proteomics Core Director Name], Department of Chemical Biology & Therapeutics, St. Jude Children's Research Hospital
**From:** [Your Name], BioMate AI
**Subject:** BioMate AI — DIA-LC-MS/MS proteomics pipeline pilot

---

Dear [Dr. Last Name],

Large-scale proteomics programs like the ones at St. Jude's Department of Chemical Biology & Therapeutics generate datasets where QC and downstream analysis are genuinely time-consuming — coefficient of variation across replicates, missing value imputation, dynamic range, differential abundance, and pathway enrichment all require careful handling. BioMate is designed to automate exactly that analytical layer.

BioMate takes MaxQuant or DIA-NN output and runs a full downstream QC and analysis pipeline: CV assessment across replicates, missing value rate per protein, dynamic range evaluation, normalisation, differential abundance analysis, and pathway enrichment. QC gates are drawn from published proteomics community standards (CV < 20%, missing values < 30%). The platform outputs an exportable HTML report and a methods section block your team can use directly in a manuscript.

I want to be transparent: we are currently completing a one-week LC-MS agent integration sprint that will connect raw LC-MS/MS instrument output directly to BioMate. The pilot would start the week after that sprint closes. If you are working primarily from MaxQuant or DIA-NN output rather than raw instrument files, we can start immediately.

St. Jude would contribute one researcher's time to evaluate the outputs; BioMate covers all compute. Deliverable: an exportable QC report and methods section text at the end of the pilot.

Would you be open to a 20-minute call to discuss whether this fits anything in your current queue?

Best,
[Your Name]
BioMate AI
[phone] | [email]

---

---

## Contact Information Still Needed Before Sending

The following specific information must be obtained before these emails can be sent. None of the named contacts below have been verified — do not send until each item is confirmed.

### Email A — UT Southwestern Simmons Cancer Center (Drug Discovery)

- [ ] **Full name and title** of the Bioinformatics Core Director at Simmons Cancer Center. The core may be directed through the Harold C. Simmons Comprehensive Cancer Center or the Department of Bioinformatics. Candidate: search the UT Southwestern faculty directory at `profiles.utsouthwestern.edu`.
- [ ] **Direct email address** for the Core Director.
- [ ] **Confirm active oncology drug program** — identify the most relevant PI running computational drug discovery work to personalise further if needed.

### Email B — Texas Children's Hospital Research Institute (RNA-seq)

- [ ] **Full name, title, and department** of the most relevant PI or Research Scientist working on pediatric cancer RNA-seq at TCH Research Institute. Candidates to investigate: Department of Pediatric Oncology, the Cancer and Hematology Centers at TCH, or the affiliated Baylor College of Medicine pediatric oncology group.
- [ ] **Direct institutional email address** (tchealth.org or bcm.edu depending on the PI's primary appointment).
- [ ] **Confirm whether they prefer to start with a public GEO dataset** or upload internal cohort data directly — this affects the pitch framing.

### Email C — UT Southwestern Cryo-EM Facility (Cryo-EM)

- [ ] **Full name and title** of the Cryo-EM Facility Director or the academic lead for the facility. UT Southwestern's cryo-EM resources may sit under the Lyda Hill Department of Bioinformatics or the Structural Biology program — confirm current leadership.
- [ ] **Direct email address** for the Facility Director.
- [ ] **Current instrument queue status** — if there is a known backlog or active grant-funded structural biology program, reference it in the email to improve relevance.

### Email D — Baylor College of Medicine, Center for Cell and Gene Therapy (scRNA-seq)

- [ ] **Full name and title** of the Research Scientist or PI most actively working on scRNA-seq or immune profiling at BCM's Center for Cell and Gene Therapy. The Center's website (`bcm.edu/research/centers/cell-and-gene-therapy`) lists principal investigators — identify the best fit.
- [ ] **Direct institutional email address** (bcm.edu).
- [ ] **Confirm whether CRISPR screen data is already collected** or still in planning — this affects whether Month 2 of the pilot is realistic in the near term.

### Email E — St. Jude Children's Research Hospital (Proteomics)

- [ ] **Full name and title** of the relevant Research Scientist or Proteomics Core Director at the Department of Chemical Biology & Therapeutics. The St. Jude faculty directory (`stjude.org/directory`) should have current leadership.
- [ ] **Direct email address** — St. Jude uses `stjude.org` addresses.
- [ ] **Confirm timing of LC-MS agent integration sprint completion** — the email currently says "one week"; update to a specific calendar date once the sprint has a firm delivery date, so the email does not create an open-ended commitment.
- [ ] **Confirm whether their primary data output is MaxQuant, DIA-NN, or raw instrument files** — this affects which version of the pilot offer is most relevant.

### All Emails — General Items

- [ ] **Your name and title** at BioMate AI (replace `[Your Name]` in the From field and sign-off).
- [ ] **Sender email address and phone number** — confirm the outreach email address to use (e.g., `pilots@biomate.ai` or a personal address).
- [ ] **Calendar link** — add a Calendly or equivalent scheduling link to all emails to reduce friction on the "book a call" ask.
- [ ] **Legal review of pilot terms** — confirm that the "BioMate covers compute costs" offer is approved internally before sending, and that the Data Use Agreement template is ready to attach or reference.

---

*BioMate AI LLC | biomate.ai | Pilot Program 2026 | Confidential*
