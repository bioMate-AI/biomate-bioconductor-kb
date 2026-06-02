// Mock data for the BioMate IND Report product.
// All values are illustrative — no real compounds, no real assay numbers.

window.IND_PROJECTS = [
  {
    id: 'p-bm0042',
    molecule: 'BM-0042',
    target: 'EGFR (ErbB1)',
    indication: 'NSCLC, first-line',
    sponsor: 'Acme Therapeutics, Inc.',
    regions: ['FDA', 'EMA', 'NMPA', 'PMDA'],
    status: 'signed',     // 'signed' | 'in_progress' | 'blocked' | 'not_started'
    statusText: 'IND ready · signed 2026-05-04',
    progress: 5,
    active: true,
  },
  {
    id: 'p-bm0031',
    molecule: 'BM-0031',
    target: 'CDK4/6',
    indication: 'Breast cancer',
    sponsor: 'Acme Therapeutics, Inc.',
    regions: ['FDA'],
    status: 'in_progress',
    statusText: 'Draft · step 3/5',
    progress: 3,
  },
  {
    id: 'p-bm0019',
    molecule: 'BM-0019',
    target: 'KRAS G12C',
    indication: 'NSCLC',
    sponsor: 'Acme Therapeutics, Inc.',
    regions: ['EMA', 'PMDA'],
    status: 'signed',
    statusText: 'Signed 2026-04-21',
    progress: 5,
  },
  {
    id: 'p-bm0054',
    molecule: 'BM-0054',
    target: 'BTK',
    indication: 'CLL — Richter transformation',
    sponsor: 'Acme Therapeutics, Inc.',
    regions: ['FDA', 'EMA'],
    status: 'blocked',
    statusText: 'Needs data — Step 3 PBPK',
    progress: 2,
  },
];

// 12 SMILES for the active project, plus ADMET predictions.
window.IND_ADMET = {
  compounds: [
    { id: 'BM-0042', smiles: 'CC(=O)Nc1ccc(Oc2ncnc3[nH]ccc23)cc1', hergIC50: 30, hergRisk: 'clear', dili: 'clear', ames: 'clear', logP: 3.2, mw: 421, ppbr: 0.92, caco2: 28.4, ro5: true, lead: true },
    { id: 'BM-0031', smiles: 'COc1cc2c(cc1OC)c(C)nc(NC1CCCC1)n2',           hergIC50: 0.08, hergRisk: 'flag', dili: 'clear', ames: 'clear', logP: 4.1, mw: 489, ppbr: 0.98, caco2: 12.1, ro5: true },
    { id: 'BM-0019', smiles: 'O=C1NC(=O)C(=Cc2ccc(Cl)cc2)S1',                 hergIC50: 12.4, hergRisk: 'border', dili: 'flag', ames: 'clear', logP: 2.8, mw: 398, ppbr: 0.85, caco2: 31.0, ro5: true },
    { id: 'BM-0054', smiles: 'CC1(C)CC(=O)c2c(O1)c(OC)c(O)c(C(=O)NC1CCCCC1)c2', hergIC50: 30, hergRisk: 'clear', dili: 'clear', ames: 'flag',  logP: 5.8, mw: 612, ppbr: 0.99, caco2: 6.4, ro5: false, ro5Fail: 'MW' },
    { id: 'BM-0073', smiles: 'CCN1CCN(c2ccc(Nc3ncnc4cc(OC)c(OC)cc34)cc2)CC1',  hergIC50: 22.8, hergRisk: 'clear', dili: 'clear', ames: 'clear', logP: 3.8, mw: 446, ppbr: 0.94, caco2: 22.1, ro5: true },
    { id: 'BM-0089', smiles: 'O=C(Nc1ccc(F)cc1)c1ccc(N2CCOCC2)nc1',           hergIC50: 18.5, hergRisk: 'clear', dili: 'clear', ames: 'clear', logP: 2.6, mw: 327, ppbr: 0.78, caco2: 36.5, ro5: true },
    { id: 'BM-0102', smiles: 'CC(C)CC(N)C(=O)Nc1ccc(Cl)c(Cl)c1',              hergIC50: 1.4, hergRisk: 'flag', dili: 'clear', ames: 'clear', logP: 3.4, mw: 289, ppbr: 0.91, caco2: 18.2, ro5: true },
    { id: 'BM-0118', smiles: 'COc1ccc(Cc2c[nH]c3ncccc23)cc1OC',                hergIC50: 26.1, hergRisk: 'clear', dili: 'clear', ames: 'clear', logP: 2.9, mw: 282, ppbr: 0.82, caco2: 33.4, ro5: true },
    { id: 'BM-0134', smiles: 'CC1=NN(C(C)C)C(=O)C1=NNc1ccc(S(N)(=O)=O)cc1',     hergIC50: 8.0,  hergRisk: 'border', dili: 'clear', ames: 'clear', logP: 1.4, mw: 351, ppbr: 0.68, caco2: 14.5, ro5: true },
    { id: 'BM-0156', smiles: 'CCN(CC)CCNC(=O)c1cc(Cl)ccc1OC',                  hergIC50: 21.3, hergRisk: 'clear', dili: 'clear', ames: 'clear', logP: 2.3, mw: 285, ppbr: 0.74, caco2: 34.2, ro5: true },
    { id: 'BM-0171', smiles: 'Cn1nc(C(=O)N2CCC(c3ccc(F)cc3)CC2)cc1C',          hergIC50: 0.32, hergRisk: 'flag', dili: 'flag', ames: 'clear', logP: 4.6, mw: 366, ppbr: 0.96, caco2: 9.8, ro5: true },
    { id: 'BM-0189', smiles: 'OC(=O)c1cc(C(F)(F)F)cn1Cc1cc(Cl)cc(Cl)c1',       hergIC50: 16.7, hergRisk: 'clear', dili: 'clear', ames: 'clear', logP: 3.6, mw: 387, ppbr: 0.89, caco2: 24.0, ro5: true },
  ],
  summary: {
    pass: 8,
    total: 12,
    benchmark: { herg: 0.931, dili: 0.913, ames: 0.934, source: 'TDC scaffold test sets' },
  },
};

// PBPK qualification — 30 drug reference set summary
window.IND_PBPK = {
  refSet: 30,
  refSource: 'EMA/CHMP/EWP/37498/2011',
  model: 'One-compartment · Rodgers & Rowland · Well-stirred liver',
  metrics: {
    cmaxWithin2: 73.3,
    aucWithin2: 100.0,
    afe: 0.61,
    aafe: 1.78,
    emaThreshold: 67,
  },
  status: 'pass',
  ospRange: '65–90%',
  lead: {
    id: 'BM-0042',
    fu: 0.032, vd: 0.91, t12: 8.4, clearance: 11.2, bioavail: 61,
  },
  perDrug: [
    { name: 'Aspirin',       fold: 1.18, pass: true },
    { name: 'Atenolol',      fold: 1.42, pass: true },
    { name: 'Caffeine',      fold: 1.08, pass: true },
    { name: 'Carbamazepine', fold: 1.92, pass: true },
    { name: 'Diazepam',      fold: 1.31, pass: true },
    { name: 'Digoxin',       fold: 2.41, pass: false },
    { name: 'Diltiazem',     fold: 1.74, pass: true },
    { name: 'Erythromycin',  fold: 2.18, pass: false },
    { name: 'Furosemide',    fold: 1.55, pass: true },
    { name: 'Ibuprofen',     fold: 1.12, pass: true },
    { name: 'Indomethacin',  fold: 1.36, pass: true },
    { name: 'Ketoprofen',    fold: 1.41, pass: true },
    { name: 'Lorazepam',     fold: 1.22, pass: true },
    { name: 'Metformin',     fold: 2.18, pass: false },
    { name: 'Midazolam',     fold: 1.62, pass: true },
    { name: 'Naproxen',      fold: 1.18, pass: true },
    { name: 'Phenytoin',     fold: 1.81, pass: true },
    { name: 'Propranolol',   fold: 1.27, pass: true },
    { name: 'Quinidine',     fold: 2.94, pass: false },
    { name: 'Theophylline',  fold: 1.06, pass: true },
    { name: 'Warfarin',      fold: 1.49, pass: true },
    { name: 'Acetaminophen', fold: 1.21, pass: true },
    { name: 'Amitriptyline', fold: 1.66, pass: true },
    { name: 'Cimetidine',    fold: 2.12, pass: false },
    { name: 'Cyclosporine',  fold: 1.88, pass: true },
    { name: 'Glibenclamide', fold: 1.39, pass: true },
    { name: 'Imipramine',    fold: 1.55, pass: true },
    { name: 'Verapamil',     fold: 1.94, pass: true },
    { name: 'Bupropion',     fold: 1.31, pass: true },
    { name: 'Tolbutamide',   fold: 1.43, pass: true },
  ],
};

window.IND_LEADS = {
  method: 'Gaussian Process · EHVI acquisition · Morgan fingerprints',
  rounds: 2,
  evaluated: 12,
  inDomain: 10,
  outOfDomain: 2,
  ranking: [
    { rank: 1, id: 'BM-0042', score: 0.89, herg: 'clear', dili: 'clear', ames: 'clear', potency: 4, ad: 'in_domain' },
    { rank: 2, id: 'BM-0118', score: 0.78, herg: 'clear', dili: 'clear', ames: 'clear', potency: 3, ad: 'in_domain' },
    { rank: 3, id: 'BM-0089', score: 0.74, herg: 'clear', dili: 'clear', ames: 'clear', potency: 3, ad: 'in_domain' },
    { rank: 4, id: 'BM-0073', score: 0.72, herg: 'clear', dili: 'clear', ames: 'clear', potency: 3, ad: 'in_domain' },
    { rank: 5, id: 'BM-0031', score: 0.71, herg: 'flag',  dili: 'clear', ames: 'clear', potency: 3, ad: 'in_domain' },
    { rank: 6, id: 'BM-0189', score: 0.69, herg: 'clear', dili: 'clear', ames: 'clear', potency: 2, ad: 'in_domain' },
    { rank: 7, id: 'BM-0019', score: 0.68, herg: 'border', dili: 'flag', ames: 'clear', potency: 3, ad: 'in_domain' },
    { rank: 8, id: 'BM-0156', score: 0.66, herg: 'clear', dili: 'clear', ames: 'clear', potency: 2, ad: 'in_domain' },
    { rank: 9, id: 'BM-0134', score: 0.58, herg: 'border', dili: 'clear', ames: 'clear', potency: 2, ad: 'in_domain' },
    { rank: 10, id: 'BM-0102', score: 0.42, herg: 'flag',  dili: 'clear', ames: 'clear', potency: 2, ad: 'in_domain' },
    { rank: 11, id: 'BM-0054', score: 0.34, herg: 'clear', dili: 'clear', ames: 'flag',  potency: 1, ad: 'out_of_domain' },
    { rank: 12, id: 'BM-0171', score: 0.21, herg: 'flag',  dili: 'flag',  ames: 'clear', potency: 2, ad: 'out_of_domain' },
  ],
};

// Document sections — each has coverage, length, and the assembled prose body.
window.IND_DOCUMENT = {
  version: 2,
  shaPrefix: 'a3f9c2d1',
  generatedAt: '2026-05-04 18:41 UTC',
  signed: false,
  signedBy: null,
  characters: 24310,
  sections: [
    {
      id: '2.6.1',
      title: '§2.6.1  Nonclinical Overview: Pharmacology',
      coverage: 'full',
      regions: ['FDA', 'EMA', 'NMPA', 'PMDA'],
      subs: [
        { id: '2.6.1.1', title: 'Overview of Computational Methods', coverage: 'full', wait: null },
        { id: '2.6.1.2', title: 'PBPK Model Qualification', coverage: 'full', wait: null },
        { id: '2.6.1.3', title: 'ADMET Screening Results', coverage: 'full', wait: null },
        { id: '2.6.1.4', title: 'Compound Prioritization', coverage: 'full', wait: null },
        { id: '2.6.1.5', title: 'Applicability Domain Assessment', coverage: 'full', wait: null },
        { id: '2.6.1.6', title: 'Audit Trail and Regulatory Traceability', coverage: 'full', wait: null },
      ],
    },
    { id: '2.6.2', title: '§2.6.2  Nonclinical Overview: Pharmacokinetics', coverage: 'full' },
    { id: '2.6.3', title: '§2.6.3  Nonclinical Overview: Toxicology', coverage: 'full' },
    { id: '2.6.4', title: '§2.6.4  Pharmacology Tabulated Summary', coverage: 'full' },
    { id: '2.6.5', title: '§2.6.5  Pharmacokinetics Tabulated Summary', coverage: 'partial', note: 'CLint data not available — predicted values used' },
    { id: '2.6.6', title: '§2.6.6  Toxicology Tabulated Summary', coverage: 'partial', note: 'No GLP in vivo data — computational only; add wet-lab data to upgrade' },
  ],
};

// Audit findings — keyed by severity
window.IND_AUDIT = {
  findings: [
    { section: '§2.6.2',   severity: 'MINOR', title: 'PBPK within-3-fold metric not reported',
      desc: 'Include within-3-fold percentage as secondary metric per EMA guidance.' },
    { section: '§2.6.1.5', severity: 'MINOR', title: 'Training set composition not documented',
      desc: 'Explicitly document hat-matrix training set for ICH M4 compliance.' },
    { section: '§2.6.1.2', severity: 'INFO',  title: 'AFE < 1 indicates Cmax underprediction',
      desc: 'Systematic underprediction (AFE=0.611) is acknowledged in §2.6.2 narrative.', addressed: true },
    { section: '§2.6.3.2', severity: 'INFO',  title: 'DILI mechanistic tier not implemented',
      desc: 'EMA DILI Tier 2 (reactive metabolite structural alerts) is not yet available.' },
    { section: '§2.6.6',   severity: 'MINOR', title: 'GLP in vivo data not provided',
      desc: 'Section uses computational predictions only — add wet-lab data for full Phase I IND.' },
    { section: '§2.6.1.3', severity: 'INFO',  title: '4 compounds out of applicability domain',
      desc: 'OOD compounds (BM-0054, BM-0171) flagged with limitation note in §2.6.1.5.' },
  ],
  chainRecords: 42,
  chainValid: true,
  lastVerified: '2 min ago',
};

window.IND_REFERENCE_COMPOUNDS = [
  { id: 'ibu', name: 'Ibuprofen', tag: 'all-clear', desc: 'Reference safe profile · no flags' },
  { id: 'ter', name: 'Terfenadine', tag: 'hERG+', desc: 'Known hERG liability · 1996 withdrawal' },
  { id: 'nit', name: 'Nitrofurantoin', tag: 'DILI+', desc: 'Hepatotoxicity signal · DILI Tier 1' },
];

// Section preview snippets (the right-panel document viewer renders these).
window.IND_SECTION_BODY = {
  '2.6.1.1': `The nonclinical pharmacology evaluation of BM-0042 was conducted using an integrated computational CRO platform (BioMate v1.0). The package integrates ADMET-AI v2.0 property prediction, a PBPK simulation engine (one-compartment, Rodgers & Rowland tissue distribution), and a Gaussian-process lead-ranking module. All computational claims in this document are reproducible from the run manifest (Section §2.6.1.6).`,
  '2.6.1.2': `The PBPK model was qualified against a 30-drug reference set (EMA/CHMP/EWP/37498/2011). Cmax predictions fell within 2-fold of observed values for 22/30 drugs (73.3%, exceeding the EMA acceptance criterion of ≥67%). AUC predictions fell within 2-fold for 30/30 drugs (100.0%). The absolute average fold error (AAFE) was 1.78; the average fold error (AFE) was 0.611, indicating a slight tendency toward Cmax underprediction. This systematic bias is acknowledged below and accounted for in safety-margin reasoning.`,
  '2.6.1.3': `ADMET screening of 12 candidate compounds across 41 endpoints (hERG, DILI, Ames, PPBR, Caco-2, BBB, CYP2D6/3A4/2C9, P-gp) was performed using ADMET-AI v2.0. 8 of 12 compounds passed all gating criteria (hERG IC50 ≥ 10 µM per Redfern 2003 / ICH S7B; DILI predicted-negative; Ames predicted-negative; Lipinski Ro5). BM-0042 (lead) is clear on all four gates with predicted hERG IC50 > 30 µM and CL_int_pred = 11.2 µL/min/mg.`,
  '2.6.1.4': `Compounds were ranked by an EHVI Gaussian-process surrogate over the four ADMET gates plus a potency surrogate (Morgan-fingerprint similarity to known EGFR-L858R inhibitors). BM-0042 ranked #1 with composite score 0.89, followed by BM-0118 (0.78) and BM-0089 (0.74).`,
  '2.6.1.5': `Applicability-domain assessment used a hat-matrix leverage cutoff at 3× the mean of the training set. 10/12 compounds are within the applicability domain. BM-0054 (Ames flag, OOD) and BM-0171 (multi-flag, OOD) are reported with explicit limitation statements in line with FDA/EMA AI Guidance (January 2026).`,
  '2.6.1.6': `Every claim in this document is traceable to a source artifact via the BioMate run manifest. Manifest entries include input SMILES, parameter values, model versions, and SHA-256 hashes of intermediate outputs. The audit chain (42 entries for this campaign) is tamper-evident and was verified at sign time.`,
  '2.6.2':   `Predicted pharmacokinetics for BM-0042: f_u = 0.032 (plasma protein binding 96.8%), Vd = 0.91 L/kg, t½ = 8.4 h, CL = 11.2 µL/min/mg microsomes, predicted bioavailability F = 61%. Predictions are within the acceptance band of the PBPK qualification reported in §2.6.1.2. Cmax underprediction (AFE = 0.611) is conservatively addressed by applying a 2× safety factor on the predicted free-drug exposure when reasoning about NOAEL margin.`,
  '2.6.3':   `Computational toxicology screening (DILI, Ames, hERG, cardiotoxicity, nephrotoxicity, mitochondrial toxicity) did not return positive findings for BM-0042. Mechanistic-tier evaluation (reactive metabolite structural alerts under EMA DILI Tier 2 protocol) is currently unavailable and is flagged as a limitation. GLP in vivo studies are required to complete §2.6.3 for a full Phase I IND.`,
  '2.6.4':   `Pharmacology summary tables conform to ICH M4 §2.6.4 format. Tables include: 4.1 Primary pharmacology · 4.2 Secondary pharmacology · 4.3 Safety pharmacology (hERG IC50 > 30 µM) · 4.4 Pharmacodynamic drug interactions (none identified).`,
  '2.6.5':   `Pharmacokinetics summary tables (§2.6.5) include predicted absorption, distribution, metabolism, and excretion endpoints. Note: measured CL_int values are not yet available; predicted CL_int is used and flagged accordingly per FDA M&S Guidance (December 2018).`,
  '2.6.6':   `Toxicology summary tables (§2.6.6) include single-dose, repeated-dose, genotoxicity, carcinogenicity, reproductive, and local-tolerance categories. All values in this section are computational predictions; wet-lab GLP data is required to upgrade this section to "Full" coverage for an IND submission.`,
};
