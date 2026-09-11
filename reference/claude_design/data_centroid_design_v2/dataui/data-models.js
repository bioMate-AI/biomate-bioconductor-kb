/* Model objects — a model is a dataset with a function attached, so it carries
   the same evidence, lineage, versions and blast radius. */
window.MODEL_CARDS = {
  'fold-predict': {
    name:'fold-predict', v:'v2.3', family:'Protein structure', conf:'high', state:'integrated',
    goal:'Predict a protein structure from sequence, with a per-residue confidence field.',
    origin:'open-source · weights pinned at v2.3 · nothing of yours is trained',
    evidence:[['CASP15-style benchmark GDT_TS','0.83','floor 0.75','pass'],['pLDDT vs true error correlation','0.86','floor 0.80','pass'],
              ['Applicability','single chains and small complexes','disordered regions reported, not hidden',''],['Held-out set','public benchmark · 112 targets','ours to re-run, not vendor-reported','']],
    lineage:[['Dataset','public structures to the 2024 cut-off','no data of yours entered this model'],['Training run','external — integrated, not trained here','weights and version pinned'],['Previous version','fold-predict v2.1','superseded 3 Jun — earlier runs still pin v2.1']],
    usedBy:[['Run','IL11RA fold prediction','pLDDT carried per residue into every downstream step'],['Workflow','Cryo-EM batch 12','prediction used only where the map is unresolved']],
    iface:['Python function','fold(sequence: str, mode: str) -> Structure','GPU requested · 1×A100, ~11 min for 400 aa'],
    versions:[['v2.3','3 Jun','GDT_TS 0.83','current'],['v2.1','12 Feb','GDT_TS 0.79','superseded']]
  },
  'molgen': {
    name:'molgen', v:'v4.1', family:'Generative chemistry', conf:'medium', state:'integrated',
    goal:'Propose chemically valid structures under constraints, optionally adapted to your series.',
    origin:'public base v4.1 · your adapter recorded as a delta, never merged into the base',
    evidence:[['Validity','99.4%','floor 99%','pass'],['Uniqueness at 1,000 samples','97%','floor 95%','pass'],
              ['Novelty · not within 1 atom of training','92% adapted / 99% base','floor 95%','flag'],['Held-out set','120 in-house compounds','never seen by the adapter','']],
    lineage:[['Dataset','series_aminopyrimidine.smi · v2','1,204 compounds — the adapter’s only input'],['Training run','Adaptation · LoRA rank 16','2 h 10 m · gate passed with a novelty flag'],['Previous version','molgen v4.1 (base, unadapted)','still callable, unchanged, at its own version']],
    usedBy:[['Design pipeline','Series 4 generation','proposals de-duplicated against the training set before ordering']],
    iface:['Python function','sample(n: int, adapter: str | None) -> list[str]','the adapter is an argument, so base behaviour stays reachable'],
    versions:[['v4.1 + a1','candidate','in-series 71% · novelty flagged','offered'],['v4.1','base','in-series 12%','current']]
  },
  'admet-herg': {
    name:'admet-herg', v:'v3', family:'Molecular property', conf:'high', state:'registered',
    goal:'Predict hERG liability from structure, for safety triage of a compound series.',
    origin:'trained here · 16 Aug · by A. Dike',
    evidence:[['Held-out AUC','0.81','floor 0.75','pass'],['Calibration error','0.04','max 0.10','pass'],
              ['Applicability coverage','92% of series 4','min 80%','pass'],['Held-out set','assay_2026_08.csv · 214 compounds','stratified by scaffold','']],
    lineage:[['Dataset','assay_2026_08.csv · v4','the same dataset object the workflows read'],
             ['Training run','Training · hERG liability — molecular property','16 Aug · 12 min · 4 phases'],
             ['Previous version','admet-herg v2','superseded, not deleted — runs before 16 Aug still pin v2']],
    usedBy:[['Workflow gate','ADMET screen — series 4','safety gate · rejected 1 of 12 proposals'],
            ['Score column','Virtual library ranking','96 compounds re-scored, round 4'],
            ['Rounds loop','Series 4 campaign','surrogate, refits on every assay upload']],
    iface:['Python function','scored(smiles: list[str]) -> list[float]','runs in the workflow sandbox · no container build'],
    versions:[['v3','16 Aug','AUC 0.81 · 3/3 gates','current'],['v2','2 Aug','AUC 0.75 · 3/3 gates','superseded'],['v1','21 Jul','AUC 0.71 · gate failed','not registered']]
  },
  'endpoint-resp': {
    name:'endpoint-resp', v:'v1', family:'Tabular AutoML', conf:'medium', state:'registered',
    goal:'Predict endpoint response from baseline covariates, for cohort stratification.',
    origin:'trained here · 15 Aug · by A. Dike',
    evidence:[['Held-out AUC','0.78','floor 0.72','pass'],['Calibration error','0.04','max 0.10','pass'],
              ['Subgroup stability','0.74–0.80 across sites','min 0.70 in every site','pass'],['Held-out set','cohort_variants.vcf.gz · 84 subjects','held out by site','']],
    lineage:[['Dataset','cohort_variants.vcf.gz · v2','—'],['Training run','Training · Endpoint response — tabular AutoML','15 Aug · 2/2 gates passed'],['Previous version','—','first version']],
    usedBy:[['Workflow','Clinical stratification','predicted column, marked as predicted'],['Report','MG stratification memo','cited with version and confidence']],
    iface:['Python function','scored(table: DataFrame) -> Series','runs in the workflow sandbox'],
    versions:[['v1','15 Aug','AUC 0.78 · 2/2 gates','current']]
  },
  'potency-gp': {
    name:'potency-gp', v:'v2', family:'Molecular property', conf:'high', state:'imported',
    goal:'Predict potency with a calibrated uncertainty, for use as an optimisation surrogate.',
    origin:'your lab · imported 4 Aug',
    evidence:[['Held-out MAE','0.33','max 0.45','pass'],['Interval coverage','94% at 95% nominal','88–98%','pass'],
              ['Held-out set','in-house assay · 410 compounds','provided at import','']],
    lineage:[['Dataset','imported evaluation set','held-out evidence required before any gate may use it'],['Training run','external — not run here','import record kept'],['Previous version','potency-gp v1','superseded 4 Aug']],
    usedBy:[['Rounds loop','Series 4 campaign','surrogate, paired with admet-herg v3']],
    iface:['Container','ghcr.io/yourlab/potency-gp:2.1','fixed environment · GPU requested'],
    versions:[['v2','4 Aug','MAE 0.33','current'],['v1','12 Jun','MAE 0.41','superseded']]
  },
  'struct-conf': {
    name:'struct-conf', v:'v7', family:'External service', conf:'medium', state:'contracted',
    goal:'Per-residue structure confidence, consumed by cryo-EM and folding runs.',
    origin:'vendor · contract to Mar 2027',
    evidence:[['Vendor-reported correlation','0.88','floor 0.80','pass'],['Local spot-check','0.84 on 40 structures','floor 0.80','pass'],
              ['Held-out set','internal validation · 40 structures','ours, not the vendor\u2019s','']],
    lineage:[['Dataset','vendor training data not disclosed','recorded as a known gap'],['Training run','external','—'],['Previous version','struct-conf v6','vendor-superseded 1 Jul']],
    usedBy:[['Workflow','Cryo-EM batch 12','structure confidence, carried per residue into downstream steps']],
    iface:['REST endpoint','POST /v7/confidence','key held in account settings · contract ends Mar 2027'],
    versions:[['v7','1 Jul','corr 0.88','current'],['v6','—','corr 0.85','retired by vendor']]
  }
};

/* Registering is a change to the registry, not a message about one. Both the
   registry row and the model card move, and every surface reads them live. */
window.registerModel = (name, v) => {
  const card = window.MODEL_CARDS[name];
  const row = (window.REGISTRY || []).find(r => r.name === name);
  if (card) { card.versions = [[v, 'just now', 'registered from a candidate', 'current']]
      .concat(card.versions.map(x => x[3] === 'current' ? [x[0], x[1], x[2], 'superseded'] : x));
    card.v = v; card.state = 'registered'; }
  if (row) { row.v = v; row.by = 'registered just now'; }
  else if (card) window.REGISTRY.push({ name:name, v:v, family:card.family, plug:card.iface[0], by:'registered just now', used:'not called yet', conf:card.conf });
  window.notifyVersions && window.notifyVersions();
};

/* The wet-lab return path — the part of the optimisation loop that is not
   compute. A round is the contract: proposals out, an order to the bench,
   results back, then a refit. Latency is weeks, returns are partial, and
   values come back censored — all three are modelled rather than smoothed. */
window.WETLAB = {
  round:4,
  state:'awaiting results',
  ordered:'19 Aug · 12 compounds requested',
  due:'2 Sep · expected · day 14 of a 14-day turnaround',
  back:7, total:12,
  /* How results get in. Three routes, because this is how labs actually work. */
  routes:[
    ['Drop an export', 'plate CSV, ELN or LIMS export', 'mapped once with a template, then auto-mapped on every upload', 'used for this round'],
    ['Connector', 'Benchling · Dotmatics · a LIMS API', 'polled every 6 h; each pull lands as a new dataset version', 'connected'],
    ['Watched intake', 'a per-project address or an instrument folder', 'for instruments that can only email or write to a share', 'available']
  ],
  /* Mapping is a saved template per assay type, not a wizard every time. */
  mapping:{ name:'hERG patch-clamp · plate export v2', saved:'11 Aug',
    cols:[['Compound','well_id → registry id','matched via the order sheet'],
          ['Readout','IC50_uM','µM · from the header'],
          ['Replicates','3 per compound','averaged, spread kept'],
          ['Censoring','">" and "<" preserved','IC50 > 30 stays censored, never coerced to 30'],
          ['QC flag','plate_qc','a failing plate is excluded, not averaged in']] },
  /* Returns, including the ones with no number. This is the anti-survivorship
     mechanism: a proposal that produced no data must say why. */
  returns:[
    ['BM-4471','IC50 34 µM · potency 8.5','measured','improved on both axes'],
    ['BM-4502','IC50 > 30 µM (censored)','measured','censored — kept as an inequality'],
    ['BM-4488','IC50 18 µM','measured','worse than predicted on hERG'],
    ['BM-4519','—','not synthesised','route failed at step 3 — no data, and the model is told so'],
    ['BM-4523','—','insufficient material','2 mg short of the assay minimum'],
    ['BM-4530','—','assay QC failed','plate 7 failed its control; queued for repeat'],
    ['BM-4541','IC50 26 µM','measured','within noise of the prediction']
  ],
  refit:{ policy:'partial refit at 50% returned · full refit on close',
    last:'2 h ago · 7 of 12 results', effect:'surrogate MAE 0.41 → 0.33', next:'admet-herg v4 candidate' }
};

window.TRAIN_CFG = {
  goal:'Predict hERG liability from structure',
  slots:[['Training data','assay_2026_08.csv · v4','resolved from this project\u2019s files'],
         ['Held-out split','20% · stratified by scaffold','recommended — random split leaks scaffold series'],
         ['Label column','herg_ic50_um','detected']],
  params:[['Family','Molecular property','inferred','from the label and the input type'],
          ['Gate floor','held-out AUC \u2265 0.75','override','the current admet-herg v2 result, so a new version must beat it'],
          ['Max training time','2 h','default',''],
          ['Register on pass','ask first','default','a passing model is offered, never registered silently']]
};
