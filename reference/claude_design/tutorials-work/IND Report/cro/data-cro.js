// BioMate CRO — mock data for all 7 surfaces
// Tagged MOCK: replace with API responses per spec in HANDOFF.md

const MOCK_CAMPAIGN = {
  campaign_id: 'cmp-a4f3b2c1',
  molecule_name: 'BMT-4451',
  target: 'EGFR L858R',
  indication: 'NSCLC',
  round: 3,
  total_compounds: 42,
  last_updated: '2h ago',
  status: 'active',
};

const DMTA_STATE = {
  design: { status: 'done', ts: '2026-04-20 08:41 UTC' },
  make: { status: 'active', ts: '2026-04-19 14:12 UTC' },
  test: { status: 'pending', ts: null },
  analyse: { status: 'pending', ts: null },
};

const TOP_COMPOUNDS = [
  { rank: 1, id: 'CPD-0087', score: 0.89, ad: 'in_domain', round: 2 },
  { rank: 2, id: 'CPD-0043', score: 0.71, ad: 'in_domain', round: 1 },
  { rank: 3, id: 'CPD-0021', score: 0.68, ad: 'out_of_domain', round: 1 },
  { rank: 4, id: 'CPD-0102', score: 0.66, ad: 'in_domain', round: 3 },
  { rank: 5, id: 'CPD-0054', score: 0.61, ad: 'in_domain', round: 2 },
  { rank: 6, id: 'CPD-0033', score: 0.58, ad: 'in_domain', round: 1 },
  { rank: 7, id: 'CPD-0119', score: 0.54, ad: 'out_of_domain', round: 3 },
  { rank: 8, id: 'CPD-0076', score: 0.49, ad: 'in_domain', round: 2 },
  { rank: 9, id: 'CPD-0012', score: 0.42, ad: 'in_domain', round: 1 },
  { rank: 10, id: 'CPD-0097', score: 0.38, ad: 'in_domain', round: 3 },
];

// Surface 2 — validation
const VALIDATION_REPORT = {
  generated_at: '2026-04-20 14:32 UTC',
  criterion_met: { cmax: true, auc: true },
  metrics: {
    cmax: { afe: 1.12, aafe: 1.38, r2: 0.71, within2: 0.76, within3: 0.86 },
    auc: { afe: 1.03, aafe: 1.28, r2: 0.93, within2: 1.00, within3: 1.00 },
  },
  drugs: [
    { name: 'Caffeine', obs_cmax: 2.34, pred_cmax: 2.71, fold: 1.16, ad: 'in_domain' },
    { name: 'Warfarin', obs_cmax: 0.28, pred_cmax: 0.31, fold: 1.11, ad: 'in_domain' },
    { name: 'Ibuprofen', obs_cmax: 24.1, pred_cmax: 18.3, fold: 0.76, ad: 'in_domain' },
    { name: 'Propranolol', obs_cmax: 0.14, pred_cmax: 0.09, fold: 0.64, ad: 'in_domain' },
    { name: 'Quinidine', obs_cmax: 1.8, pred_cmax: 4.1, fold: 2.28, ad: 'in_domain' },
    { name: 'Midazolam', obs_cmax: 0.08, pred_cmax: 0.09, fold: 1.12, ad: 'in_domain' },
    { name: 'Diclofenac', obs_cmax: 2.1, pred_cmax: 1.9, fold: 0.90, ad: 'in_domain' },
    { name: 'Theophylline', obs_cmax: 10.3, pred_cmax: 11.8, fold: 1.14, ad: 'in_domain' },
    { name: 'Metoprolol', obs_cmax: 0.21, pred_cmax: 0.18, fold: 0.86, ad: 'in_domain' },
    { name: 'Omeprazole', obs_cmax: 1.1, pred_cmax: 0.44, fold: 0.40, ad: 'out_of_domain' },
    { name: 'Carbamazepine', obs_cmax: 4.3, pred_cmax: 5.1, fold: 1.19, ad: 'in_domain' },
    { name: 'Diltiazem', obs_cmax: 0.13, pred_cmax: 0.15, fold: 1.15, ad: 'in_domain' },
    { name: 'Nifedipine', obs_cmax: 0.09, pred_cmax: 0.08, fold: 0.89, ad: 'in_domain' },
    { name: 'Verapamil', obs_cmax: 0.18, pred_cmax: 0.55, fold: 3.06, ad: 'out_of_domain' },
    { name: 'Simvastatin', obs_cmax: 0.024, pred_cmax: 0.031, fold: 1.29, ad: 'in_domain' },
    { name: 'Atorvastatin', obs_cmax: 0.035, pred_cmax: 0.029, fold: 0.83, ad: 'in_domain' },
    { name: 'Rosuvastatin', obs_cmax: 0.014, pred_cmax: 0.017, fold: 1.21, ad: 'in_domain' },
    { name: 'Loratadine', obs_cmax: 0.002, pred_cmax: 0.003, fold: 1.50, ad: 'in_domain' },
    { name: 'Fluoxetine', obs_cmax: 0.062, pred_cmax: 0.071, fold: 1.15, ad: 'in_domain' },
    { name: 'Paroxetine', obs_cmax: 0.038, pred_cmax: 0.041, fold: 1.08, ad: 'in_domain' },
    { name: 'Sertraline', obs_cmax: 0.041, pred_cmax: 0.039, fold: 0.95, ad: 'in_domain' },
    { name: 'Citalopram', obs_cmax: 0.094, pred_cmax: 0.087, fold: 0.93, ad: 'in_domain' },
    { name: 'Venlafaxine', obs_cmax: 0.18, pred_cmax: 0.21, fold: 1.17, ad: 'in_domain' },
    { name: 'Diazepam', obs_cmax: 0.31, pred_cmax: 0.28, fold: 0.90, ad: 'in_domain' },
    { name: 'Alprazolam', obs_cmax: 0.012, pred_cmax: 0.014, fold: 1.17, ad: 'in_domain' },
    { name: 'Lorazepam', obs_cmax: 0.019, pred_cmax: 0.017, fold: 0.89, ad: 'in_domain' },
    { name: 'Amitriptyline', obs_cmax: 0.14, pred_cmax: 0.19, fold: 1.36, ad: 'in_domain' },
    { name: 'Imipramine', obs_cmax: 0.081, pred_cmax: 0.093, fold: 1.15, ad: 'in_domain' },
    { name: 'Desipramine', obs_cmax: 0.065, pred_cmax: 0.058, fold: 0.89, ad: 'in_domain' },
    { name: 'Nortriptyline', obs_cmax: 0.11, pred_cmax: 0.13, fold: 1.18, ad: 'in_domain' },
    { name: 'Haloperidol', obs_cmax: 0.006, pred_cmax: 0.008, fold: 1.33, ad: 'in_domain' },
  ],
};

// Surface 3 — audit
const AUDIT_RECORDS = [
  { id: 1, ts: '2026-04-20 14:32 UTC', who: 'alice@biotech.com', kind: 'user', action: 'INGEST_ASSAY',       resource: 'cmp-a4f3b2c1', payload: '8f3a9bc2d4c1e5f7', hash: '3b7e01a5c0c9a902', prev: '0000000000000000', note: 'genesis' },
  { id: 2, ts: '2026-04-20 14:38 UTC', who: 'alice@biotech.com', kind: 'user', action: 'VALIDATE_MODEL',     resource: 'pbpk.v2',      payload: 'a812bc03ef4512a8', hash: '7c21d93f1a88ffb4', prev: '3b7e01a5c0c9a902' },
  { id: 3, ts: '2026-04-20 14:45 UTC', who: 'system',           kind: 'system', action: 'PROPOSE_ROUND',    resource: 'cmp-a4f3b2c1', payload: 'bb4430199c7d11e8', hash: 'f1a9cc32e510e1b6', prev: '7c21d93f1a88ffb4', detail: 'Round 3, 10 proposals • auto_retrain' },
  { id: 4, ts: '2026-04-20 14:59 UTC', who: 'alice@biotech.com', kind: 'user', action: 'VIEW_PROPOSALS',     resource: 'cmp-a4f3b2c1', payload: 'c1d21200aaa14488', hash: '5e28af11c7b80022', prev: 'f1a9cc32e510e1b6' },
  { id: 5, ts: '2026-04-20 15:01 UTC', who: 'alice@biotech.com', kind: 'esig', action: 'ESIG',              resource: 'EXPORT_CRO_ORDER', payload: '7d3f011aac9b2244', hash: '9c4b1e7833ac4ff0', prev: '5e28af11c7b80022', meaning: 'I approve the synthesis order for campaign cmp-a4f3b2c1 and confirm I have reviewed the compound selection.', sig_id: 'sig_7d3f011a' },
  { id: 6, ts: '2026-04-20 15:01 UTC', who: 'alice@biotech.com', kind: 'user', action: 'EXPORT_CRO_ORDER',  resource: 'cmp-a4f3b2c1', payload: '3312bb09aaccdd71', hash: 'a081baf4c7cc3d19', prev: '9c4b1e7833ac4ff0' },
  { id: 7, ts: '2026-04-20 15:14 UTC', who: 'bob@biotech.com',   kind: 'user', action: 'VIEW_CAMPAIGN',     resource: 'cmp-a4f3b2c1', payload: '91221aabb3309ee4', hash: 'b4a01e8fd550ff0c', prev: 'a081baf4c7cc3d19' },
  { id: 8, ts: '2026-04-20 16:02 UTC', who: 'alice@biotech.com', kind: 'user', action: 'INGEST_ASSAY',       resource: 'cmp-a4f3b2c1', payload: 'fe54aa210abc0911', hash: 'c8912e00aabcde78', prev: 'b4a01e8fd550ff0c' },
  { id: 9, ts: '2026-04-20 16:03 UTC', who: 'system',           kind: 'system', action: 'RETRAIN_TRIGGER',  resource: 'cmp-a4f3b2c1', payload: '120099aabb445577', hash: 'd5a8012f8890ab40', prev: 'c8912e00aabcde78', detail: 'New assay data detected; retraining' },
  { id: 10, ts: '2026-04-20 16:05 UTC', who: 'system',          kind: 'system', action: 'PROPOSE_ROUND',    resource: 'cmp-a4f3b2c1', payload: '44aa009911bbcc00', hash: 'e1b8991af00cc721', prev: 'd5a8012f8890ab40', detail: 'Round 4, 10 proposals • auto_retrain' },
];
const AUDIT_TOTAL = 47;

// Surface 4 — auto retrain
const PROPOSALS = [
  { rank: 1, smiles: 'CC(=O)Nc1ccc(O)cc1CC(=O)NC', score: 0.87, ci_lo: 0.79, ci_hi: 0.95, ad: 'in_domain' },
  { rank: 2, smiles: 'COc1cc2c(cc1OC)C(=O)N(C)CC2', score: 0.83, ci_lo: 0.74, ci_hi: 0.92, ad: 'in_domain' },
  { rank: 3, smiles: 'c1ccc(cc1)CC(=O)NCCN1CCOCC1', score: 0.71, ci_lo: 0.58, ci_hi: 0.84, ad: 'out_of_domain' },
  { rank: 4, smiles: 'Clc1ccc(cc1)S(=O)(=O)NC(C)(C)C', score: 0.68, ci_lo: 0.60, ci_hi: 0.76, ad: 'in_domain' },
  { rank: 5, smiles: 'Nc1nc2c(ncn2C(C)C)c(=O)[nH]1', score: 0.64, ci_lo: 0.51, ci_hi: 0.77, ad: 'in_domain' },
  { rank: 6, smiles: 'CN1CCN(CC1)c1ccc2c(c1)nc(N)n2C', score: 0.61, ci_lo: 0.54, ci_hi: 0.68, ad: 'in_domain' },
  { rank: 7, smiles: 'O=C(Nc1ccc(F)cc1)c1ccncc1', score: 0.58, ci_lo: 0.41, ci_hi: 0.75, ad: 'out_of_domain' },
  { rank: 8, smiles: 'CCOc1ccc(cc1)C(=O)NC(C)C(=O)NC', score: 0.55, ci_lo: 0.48, ci_hi: 0.62, ad: 'in_domain' },
  { rank: 9, smiles: 'Cc1ccc2nc(NC3CCN(C)CC3)nc2c1', score: 0.53, ci_lo: 0.46, ci_hi: 0.60, ad: 'in_domain' },
  { rank: 10, smiles: 'OC(=O)c1ccc(cc1)OCc1ccc(Cl)cc1', score: 0.49, ci_lo: 0.42, ci_hi: 0.56, ad: 'in_domain' },
];

const PROPOSAL_HISTORY = [
  { round: 3, ts: '2026-04-20 14:45 UTC', n: 10, trigger: 'auto_retrain' },
  { round: 2, ts: '2026-04-20 11:03 UTC', n: 10, trigger: 'manual' },
  { round: 1, ts: '2026-04-20 08:41 UTC', n: 10, trigger: 'manual' },
];

// Surface 6 — IND sections
const IND_SECTIONS = [
  { id: '2.6.1.1', title: 'Overview of Methods',        status: 'ok',   meta: 'ready' },
  { id: '2.6.1.2', title: 'PBPK Model Qualification',   status: 'ok',   meta: '31 drugs, EMA ✓' },
  { id: '2.6.1.3', title: 'ADMET Predictions',          status: 'ok',   meta: '42 compounds' },
  { id: '2.6.1.4', title: 'Compound Prioritization',    status: 'ok',   meta: 'Round 3 data' },
  { id: '2.6.1.5', title: 'Applicability Domain',       status: 'ok',   meta: 'coverage: 89%' },
  { id: '2.6.1.6', title: 'Audit Trail',                status: 'warn', meta: '47 records, valid' },
];

// Users list for audit filter
const AUDIT_USERS = ['all', 'alice@biotech.com', 'bob@biotech.com', 'system'];

const AUDIT_ACTIONS = ['all', 'INGEST_ASSAY', 'VALIDATE_MODEL', 'PROPOSE_ROUND', 'VIEW_PROPOSALS', 'EXPORT_CRO_ORDER', 'ESIG', 'VIEW_CAMPAIGN', 'RETRAIN_TRIGGER'];

Object.assign(window, {
  MOCK_CAMPAIGN, DMTA_STATE, TOP_COMPOUNDS, VALIDATION_REPORT,
  AUDIT_RECORDS, AUDIT_TOTAL, AUDIT_USERS, AUDIT_ACTIONS,
  PROPOSALS, PROPOSAL_HISTORY, IND_SECTIONS,
});
