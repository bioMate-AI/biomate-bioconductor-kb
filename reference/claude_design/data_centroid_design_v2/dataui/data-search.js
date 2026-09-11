/* Search & evidence — what a worked example actually returns.
   One case per track (Literature · Databases · Patents · Internal), so clicking
   an example on the cold-start card lands on a real answer surface instead of a
   workflow configuration. Nothing here runs on your data, and every case says
   what was searched, what was dropped, and where each claim came from. */

const R = (id, o) => Object.assign({ id, resolved:true }, o);

window.SEARCH_CASES = {

  /* ── Literature ───────────────────────────────────────────── */
  lit_evidence: {
    id:'lit_evidence', track:'Literature', q:'What is the evidence linking this target to disease?',
    subject:'IL-11 · idiopathic pulmonary fibrosis', took:'6.4 s',
    sources:[{ n:'PubMed', got:412, kept:7 }, { n:'Europe PMC', got:288, kept:3 }, { n:'bioRxiv / medRxiv', got:64, kept:2 }],
    filters:[['Years', '2015–2026'], ['Species', 'human + mouse'], ['Type', 'peer-reviewed & preprint'], ['Evidence', 'primary only']],
    dropped:'752 records dropped — off-topic for this target (631), review or commentary with no primary data (94), retracted or expression-of-concern (3), no accessible full text (24).',
    answer:[
      { lead:'Direction of evidence · consistent', t:'Human fibrotic lung tissue shows raised IL-11 in fibroblasts relative to matched non-fibrotic controls, and the same signal appears in three independently collected cohorts.', refs:['l1','l2'] },
      { t:'Loss of function in mouse models attenuates bleomycin-induced fibrosis, and a neutralising antibody reverses established disease in one of the two reported models — which is the stronger of the two claims and the one worth checking first.', refs:['l3','l4'] },
      { t:'Mechanistically the effect is reported as post-transcriptional: IL-11 drives ERK-dependent translation of fibrogenic proteins rather than transcription of them, which is why earlier transcriptomic screens under-weighted it.', refs:['l5'] }
    ],
    boundary:'Association in human tissue plus causal evidence in mouse is not the same as a validated human target. No interventional human data exists for this target as of the last index date (2 Sep 2026).',
    disagree:{ t:'Where the literature disagrees', s:'Two groups report that the anti-fibrotic effect does not separate from the general anti-inflammatory effect of the antibody backbone. Both are included in the shortlist rather than dropped — a disagreement is a finding, not noise.', refs:['l6','l7'] },
    table:{ cols:['Study', 'System', 'Finding', 'Strength'],
      rows:[['Ng 2019', 'human IPF fibroblasts', 'IL-11 raised 4.1×', 'primary · n=24'],
        ['Schafer 2017', 'mouse bleomycin', 'KO attenuates fibrosis', 'primary · replicated'],
        ['Widjaja 2022', 'mouse, therapeutic dosing', 'reversal of established disease', 'primary · single lab'],
        ['Cook 2021', 'human lung scRNA-seq', 'signal confined to a fibroblast subset', 'primary · n=9'],
        ['Adami 2023', 'mouse', 'effect not separable from backbone', 'contradicting']] },
    refs:{
      l1:R('l1', { kind:'paper', title:'Interleukin-11 is a therapeutic target in idiopathic pulmonary fibrosis', venue:'Science Translational Medicine', year:2019, who:'Ng B. et al.', snippet:'IL-11 protein was elevated in IPF fibroblasts relative to matched controls across three cohorts.' }),
      l2:R('l2', { kind:'paper', title:'A single-cell atlas of the fibrotic human lung', venue:'Nature Medicine', year:2021, who:'Cook S. et al.', snippet:'Expression was confined to a PDGFRA-high fibroblast subset rather than distributed across stromal cells.' }),
      l3:R('l3', { kind:'paper', title:'IL-11 signalling drives fibrosis in the mouse lung', venue:'Nature', year:2017, who:'Schafer S. et al.', snippet:'Genetic loss of the receptor attenuated bleomycin-induced fibrosis.' }),
      l4:R('l4', { kind:'paper', title:'Therapeutic neutralisation reverses established lung fibrosis', venue:'JCI Insight', year:2022, who:'Widjaja A. et al.', snippet:'Antibody dosing after disease onset reduced collagen deposition relative to isotype control.' }),
      l5:R('l5', { kind:'paper', title:'Post-transcriptional control of fibrogenic protein synthesis', venue:'Cell Reports', year:2020, who:'Corden B. et al.', snippet:'ERK-dependent translation, not transcription, accounted for the increase in fibrogenic protein.' }),
      l6:R('l6', { kind:'preprint', title:'Backbone effects confound anti-IL-11 efficacy readouts', venue:'bioRxiv', year:2023, who:'Adami E. et al.', snippet:'Isotype-matched controls narrowed the reported effect size substantially.' }),
      l7:R('l7', { kind:'paper', title:'Reassessing anti-fibrotic antibody benchmarks', venue:'Am J Respir Cell Mol Biol', year:2024, who:'Marchetti L. et al.', snippet:'Reported separation from vehicle did not hold in two of four replicate cohorts.' })
    },
    next:[['run', 'Check this against our own data', 'Differential expression on the fibrosis counts matrix, scored for this pathway'],
      ['save', 'Save the answer into project files', 'Written as a document you can edit — and cite from later']]
  },

  /* ── Databases ────────────────────────────────────────────── */
  db_struct: {
    id:'db_struct', track:'Databases', q:'Pull every reported structure for this target.',
    subject:'IL-11 receptor α · experimental structures', took:'3.1 s',
    sources:[{ n:'PDB', got:31, kept:14 }, { n:'AlphaFold DB', got:2, kept:1 }, { n:'EMDB', got:6, kept:3 }],
    filters:[['Organism', 'H. sapiens'], ['Resolution', '≤ 3.5 Å'], ['Chains', 'receptor present'], ['Obsolete', 'excluded']],
    dropped:'25 entries dropped — non-human orthologue (14), receptor chain absent (6), superseded by a re-refinement (3), resolution above the cut-off (2).',
    answer:[
      { lead:'What exists', t:'Fourteen experimental structures cover the receptor, of which four are complexes with the cytokine and one is a ternary complex with gp130. The complexes are the ones worth modelling against; the apo structures differ in the D2–D3 hinge by up to 4 Å, so a pose built on one is not transferable to the other.', refs:['d1', 'd2'] },
      { t:'Coverage is uneven: the membrane-proximal domain is resolved in only two entries, and the predicted model is the only source for the cytoplasmic tail — flagged as prediction, not measurement.', refs:['d3'] }
    ],
    boundary:'A database answer reports what has been deposited, not what is true. Two of the complexes come from the same laboratory and the same construct, so they are not independent.',
    table:{ cols:['ID', 'Method', 'Resolution', 'Contents', 'Year'],
      rows:[['6O4O', 'X-ray', '2.10 Å', 'receptor D1–D3', 2019],
        ['7QPS', 'cryo-EM', '3.20 Å', 'cytokine · receptor', 2022],
        ['8BF2', 'cryo-EM', '2.80 Å', 'ternary with gp130', 2023],
        ['5E4F', 'X-ray', '2.65 Å', 'receptor D2–D3', 2016],
        ['AF-Q14626', 'prediction', '—', 'full chain · pLDDT 71 in tail', 2024]] },
    refs:{
      d1:R('d1', { kind:'record', title:'PDB 8BF2 — ternary signalling complex', venue:'Protein Data Bank', year:2023, who:'deposited by Metcalfe R. et al.', snippet:'2.80 Å cryo-EM map, receptor and gp130 both resolved.' }),
      d2:R('d2', { kind:'paper', title:'Architecture of the IL-11 signalling complex', venue:'Nature Communications', year:2023, who:'Metcalfe R. et al.', snippet:'Describes the construct and the hinge conformation seen in 8BF2.' }),
      d3:R('d3', { kind:'record', title:'AlphaFold DB — Q14626', venue:'AlphaFold Protein Structure Database', year:2024, who:'model, not experiment', snippet:'pLDDT drops below 75 across the cytoplasmic tail.' })
    },
    next:[['run', 'Model against the best complex', 'Structure work on 8BF2, with the hinge caveat carried through'],
      ['save', 'Save the structure list into project files', 'A table you can edit and re-run the query from']]
  },

  /* ── Patents ──────────────────────────────────────────────── */
  pat_claims: {
    id:'pat_claims', track:'Patents', q:'Who holds composition-of-matter claims on this scaffold?',
    subject:'2-aminopyrimidine-5-carboxamide core', took:'8.7 s',
    sources:[{ n:'EPO · DOCDB', got:186, kept:11 }, { n:'USPTO full-text', got:143, kept:9 }, { n:'WIPO PATENTSCOPE', got:97, kept:4 }],
    filters:[['Claim type', 'composition-of-matter'], ['Status', 'granted + pending'], ['Jurisdictions', 'US · EP · CN · JP'], ['Markush', 'expanded and matched']],
    dropped:'402 filings dropped — method-of-use or formulation claims only (268), scaffold outside every Markush expansion (121), abandoned with no live family member (13).',
    answer:[
      { lead:'Read this as a shortlist, not an opinion', t:'Three live families claim the core itself. The blocking one is EP3 214 076 B1 (Kaneda Pharma): its independent claim 1 expands to your scaffold when R³ is any small alkyl, which covers eleven of your current series.', refs:['p1'] },
      { t:'Two further families claim it only in combination with a defined substituent at the 4-position. Your series avoids that position, so those read as navigable rather than blocking — subject to counsel.', refs:['p2', 'p3'] },
      { t:'The earliest priority in the blocking family is 12 Mar 2016; with the granted term extension in the US it expires 2037, and no post-grant opposition is on file.', refs:['p1', 'p4'] }
    ],
    boundary:'This is a claim-level retrieval, not a freedom-to-operate opinion. Markush expansion is done mechanically and is deliberately over-inclusive; a claim shown here as covering your scaffold still needs a qualified reading.',
    table:{ cols:['Family', 'Assignee', 'Claim', 'Status', 'Earliest priority', 'Read'],
      rows:[['EP3 214 076 B1', 'Kaneda Pharma', 'composition-of-matter', 'granted', '12 Mar 2016', 'blocking'],
        ['US 11,384,088', 'Vantage Bio', 'CoM · 4-substituted only', 'granted', '4 Sep 2018', 'navigable'],
        ['WO 2021/118 442', 'Helion Therapeutics', 'CoM · 4-substituted only', 'pending', '19 Dec 2019', 'navigable'],
        ['CN 114 249 682 A', 'Kaneda Pharma', 'same family as EP3 214 076', 'granted', '12 Mar 2016', 'blocking · CN'],
        ['US 2024/0 155 021', 'unassigned', 'method-of-use', 'pending', '7 Nov 2022', 'not on the core']] },
    refs:{
      p1:R('p1', { kind:'patent', title:'EP3 214 076 B1 — pyrimidine carboxamide derivatives', venue:'European Patent Office', year:2016, who:'Kaneda Pharma K.K.', snippet:'Claim 1: a compound of formula (I) wherein R³ is C1–C4 alkyl…' }),
      p2:R('p2', { kind:'patent', title:'US 11,384,088 B2 — 4-substituted aminopyrimidines', venue:'USPTO', year:2018, who:'Vantage Bio Inc.', snippet:'Claim 1 requires a substituent at the 4-position.' }),
      p3:R('p3', { kind:'patent', title:'WO 2021/118 442 A1', venue:'WIPO', year:2019, who:'Helion Therapeutics', snippet:'International search report cites EP3 214 076 as category X.' }),
      p4:R('p4', { kind:'record', title:'EP register — legal status EP3 214 076', venue:'EPO Register', year:2026, who:'register extract', snippet:'No opposition filed; annual fees paid through 2026.' })
    },
    next:[['run', 'Screen my generated candidates against these claims', 'Every candidate checked against the eleven live claim sets'],
      ['save', 'Save the claim landscape into project files', 'A document counsel can annotate, with the retrieval recorded']]
  },

  /* ── Internal ─────────────────────────────────────────────── */
  int_prior: {
    id:'int_prior', track:'Internal', q:'Have we assayed this scaffold before, and what did we conclude?',
    subject:'aminopyrimidine series · our own record', took:'2.4 s',
    sources:[{ n:'Run history', got:38, kept:4 }, { n:'Project reports', got:19, kept:3 }, { n:'ELN · Benchling', got:212, kept:6 }],
    filters:[['Scope', 'this account'], ['Projects', 'all 4'], ['Since', '2024'], ['Include', 'failed runs']],
    dropped:'256 records dropped — different chemotype (198), no measured endpoint (41), duplicate of a linked record (17). Failed runs were kept deliberately: a negative result is a result.',
    answer:[
      { lead:'Yes — twice, and the second time it was parked', t:'The series was assayed in March 2025 under ADMET screen — series 4 and again in November 2025. Both runs cleared potency and both flagged hERG: 3.1 µM and 4.4 µM against an internal floor of 30 µM.', refs:['i1', 'i2'] },
      { t:'The November report concluded that the liability tracked with amine basicity across the series, and recommended capping pKa below 8 before re-screening. That recommendation was never actioned — no run since then carries the modified core.', refs:['i3'] },
      { t:'One caveat sits in our own record: the March run used assay plate lot B-2214, which the QC audit later marked as drifting. The March number is therefore the weaker of the two.', refs:['i4'] }
    ],
    boundary:'This searches only what has been filed into BioMate. Work that stayed in a local notebook or a spreadsheet on someone’s laptop is invisible here, and the answer cannot tell you it is missing.',
    table:{ cols:['Record', 'Project', 'When', 'Endpoint', 'Conclusion'],
      rows:[['ADMET screen · run 118', 'ADMET screen — series 4', 'Mar 2025', 'hERG 3.1 µM', 'flagged · plate lot suspect'],
        ['ADMET screen · run 204', 'ADMET screen — series 4', 'Nov 2025', 'hERG 4.4 µM', 'flagged · confirmed'],
        ['after-run report v3', 'ADMET screen — series 4', 'Nov 2025', '—', 'cap pKa < 8, then re-screen'],
        ['ELN entry AD-2211', 'ADMET screen — series 4', 'Dec 2025', 'solubility 18 µM', 'acceptable']] },
    refs:{
      i1:R('i1', { kind:'run', title:'ADMET screen — run 118', venue:'BioMate run history', year:2025, who:'A. Dike', snippet:'hERG patch-clamp IC50 3.1 µM; gate 2 flagged.' }),
      i2:R('i2', { kind:'run', title:'ADMET screen — run 204', venue:'BioMate run history', year:2025, who:'A. Dike', snippet:'hERG IC50 4.4 µM on a clean plate lot; gate 2 flagged again.' }),
      i3:R('i3', { kind:'doc', title:'after-run report v3 — series 4', venue:'Project files', year:2025, who:'BioMate · edited by A. Dike', snippet:'Recommends capping amine pKa below 8 before any re-screen.' }),
      i4:R('i4', { kind:'record', title:'QC audit — plate lot B-2214', venue:'Assay quality', year:2025, who:'BioMate quality check', snippet:'Lot marked as drifting after four runs; earlier results down-weighted.' })
    },
    next:[['run', 'Re-screen the capped-pKa analogues', 'The recommendation from November, as an actual run'],
      ['save', 'Save this into project files', 'So the next person asking gets the answer, not the search']]
  }
};

/* Which case an example or a typed question lands on. Falls back to the track's
   own case, so every search example on the cold-start card resolves. */
window.SEARCH_MATCH = [
  [/(patent|freedom.?to.?operate|\bfto\b|composition-of-matter|claims?\b|inside anyone)/i, 'pat_claims'],
  [/(have we|did we|our (last|previous|in-house)|find the last|what did we conclude|baseline)/i, 'int_prior'],
  [/(pull every|reported structure|structures? for|registr|curated|off-?target|trials? targeted)/i, 'db_struct'],
  [/(evidence|literature|\bsar\b|standard for|why do|mechanism|debate)/i, 'lit_evidence']
];
window.TRACK_CASE = { Literature:'lit_evidence', Databases:'db_struct', Patents:'pat_claims', Internal:'int_prior' };
window.searchCaseFor = (q, track) => {
  const hit = (window.SEARCH_MATCH.find(([m]) => m.test(q || '')) || [])[1];
  return SEARCH_CASES[hit] || SEARCH_CASES[TRACK_CASE[track] || 'lit_evidence'];
};
window.REF_KIND = { paper:'paper', preprint:'preprint', patent:'patent', record:'database record', run:'our run', doc:'our report' };
