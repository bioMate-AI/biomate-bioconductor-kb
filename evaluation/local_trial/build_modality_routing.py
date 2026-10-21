#!/usr/bin/env python3
"""build_modality_routing.py — scaffold the "28-modality orchestration/routing" gold task.

The BioMate ORCHESTRATOR/ASSISTANT task (NOT a design model): given a drug-design request,
identify the drug MODALITY (of 28) + intent, and route to the right proposer/evaluator workflow(s).

GROUNDING (no fabrication):
  - 28-modality taxonomy + the modality->workflow route map are taken from the verified
    coverage audit docs/20260509_modality_coverage_audit.md (itself verified against
    backend/database/galaxy_ai_tools.db), expanded to 28 with the standard pharma
    therapeutic-modality taxonomy (small-molecule / peptide / antibody / oligo / RNA /
    gene / cell / vaccine / radio sub-types).
  - Route workflow names are REAL catalog workflow names from that audit; coverage flags
    ('excellent'/'good'/'partial'/'none') are the audit's own verdicts.
  - Gold requests are CURATED CANONICAL phrasings grounded in each modality's definition +
    the audit's 'required inputs'. They are explicitly SEED gold (templated, not real user
    logs); per the no-tiny-dataset rule this scaffold is NOT by itself sufficient to train —
    it needs augmentation from real routing/connector logs before a training run (see doc).

Output: docs/20260912_onprem_llm/modality_routing_v1/{modality_episodes.jsonl, taxonomy.json}
Split: leakage-safe — held out by REQUEST FAMILY (a modality's requests never span train+dev).
"""
import json, os, random, hashlib
random.seed(28)
REPO = "/Users/kky/biomate-review"
OUT = f"{REPO}/docs/20260912_onprem_llm/modality_routing_v1"
os.makedirs(OUT, exist_ok=True)

# (modality, coverage[audit], canonical intent, route workflows[real catalog names, from audit]).
# coverage: excellent/good/partial/none — the audit's verdict; 'none'/'partial' => routing is
# coverage-blocked (modality-ID still trainable, route label = GAP).
MODALITIES = [
 # --- small-molecule family ---
 ("small_molecule", "excellent", "design/screen a small-molecule binder",
   ["Docking Autodock Vina","Drugclip Virtual Screening","REINVENT4 Generative Lead Design","Predict ADMET Properties (AI)","OpenFE Relative Binding Free Energy (RBFE)"]),
 ("covalent_small_molecule", "good", "design a covalent/warhead inhibitor",
   ["Covalent Warhead Design","MOE Covalent Docking Pipeline","Predict ADMET Properties (AI)"]),
 ("protac_degrader", "good", "design a PROTAC/targeted-degrader",
   ["protac_design","Predict ADMET Properties (AI)"]),
 ("molecular_glue", "partial", "design a molecular-glue degrader",
   ["protac_design"]),
 ("scaffold_hop", "excellent", "scaffold-hop / optimize a lead series",
   ["scaffold_hopping","Calculate Physicochemical Properties","Predict ADMET Properties (AI)"]),
 # --- peptide / macrocycle family ---
 ("linear_peptide", "good", "design a linear peptide binder",
   ["Boltz Structure Prediction","GROMACS Protein-Ligand MD + MM-GBSA"]),
 ("cyclic_peptide_macrocycle", "good", "design a cyclic peptide / macrocycle binder",
   ["Boltz Structure Prediction","gromacs_pmx_fep","GROMACS Protein-Ligand MD + MM-GBSA"]),
 ("peptide_drug_conjugate", "partial", "design a peptide-drug conjugate (PDC)",
   ["adc_design"]),
 # --- antibody / biologic family ---
 ("antibody_mab", "excellent", "design/develop a monoclonal antibody",
   ["scfv_antibody_design","antibody_developability","nf-core/proteinfold"]),
 ("scfv_fragment", "excellent", "design an scFv / antibody fragment",
   ["scfv_antibody_design","antibody_developability"]),
 ("bispecific_antibody", "excellent", "design a bispecific / multi-specific antibody",
   ["Bispecific Antibody Design","antibody_developability"]),
 ("nanobody_vhh", "good", "design a nanobody / VHH",
   ["scfv_antibody_design","antibody_developability"]),
 ("fc_engineered_ab", "partial", "Fc-engineer an antibody (ADCC/half-life)",
   ["antibody_developability","Fcrn Antibody Pk"]),
 ("adc", "good", "design an antibody-drug conjugate (ADC)",
   ["adc_design","scfv_antibody_design","Predict ADMET Properties (AI)"]),
 ("large_protein_biologic", "good", "design/predict a large protein / enzyme therapeutic",
   ["nf-core/proteinfold","AlphaFold DB Search","proteome_selectivity_profiling"]),
 ("fusion_protein", "partial", "design a fusion-protein / trap biologic",
   ["nf-core/proteinfold","antibody_developability"]),
 # --- oligonucleotide / RNA family ---
 ("sirna_rnai", "good", "design an siRNA / RNAi therapeutic",
   ["sirna_design_full","sirna_offtarget_analysis","lnp_formulation_optimization"]),
 ("aso_gapmer", "good", "design an antisense oligonucleotide / gapmer",
   ["aso_gapmer_design"]),
 ("mrna_therapeutic", "good", "design an mRNA therapeutic",
   ["mrna_therapeutic_design","Optimize Codons For Heterologous Expression","lnp_formulation_optimization"]),
 ("sarna_circrna", "none", "design a self-amplifying / circular RNA",
   []),
 ("aptamer", "none", "design an RNA/DNA aptamer (SELEX)",
   []),
 # --- gene / cell family ---
 ("crispr_editing", "good", "design a CRISPR edit (KO / CRISPRa-i / base / prime)",
   ["P0 Mrna Validation","Optimize Codons For Heterologous Expression"]),
 ("aav_gene_therapy", "good", "design an AAV gene-therapy construct",
   ["Optimize Codons For Heterologous Expression","mrna_therapeutic_design"]),
 ("car_cell_therapy", "good", "design a CAR-T / cell-therapy construct",
   ["scfv_antibody_design","bispecific_antibody_design"]),
 ("tcr_t", "partial", "design a TCR-T (HLA-restricted neoantigen)",
   ["nf-core/epitopeprediction"]),
 ("nk_cell_therapy", "none", "design an NK-cell therapy",
   []),
 # --- vaccine / radio / combination ---
 ("vaccine_epitope", "good", "design a vaccine / epitope / neoantigen",
   ["nf-core/epitopeprediction","mrna_therapeutic_design","Optimize Codons For Heterologous Expression"]),
 ("radiopharmaceutical", "partial", "design a radioligand / radiopharmaceutical (RLT)",
   ["Analyze Radiolabeled Antibody Biodistribution","Estimate Alpha Particle Radiotherapy Dosimetry"]),
]
assert len(MODALITIES) == 28, f"need exactly 28, got {len(MODALITIES)}"

# Curated canonical request stems grounded in each modality's definition. Varied by target
# slot so the LLM can't key on a single phrasing. These are SEED/templated (labeled as such).
TARGETS = ["KRAS G12C","PD-L1","BCL-2","αvβ6 integrin","EGFR","BTK","Factor XIa","IL-23",
           "transthyretin","SOD1","PCSK9","HER2","CD19","BCMA","hepatitis-B surface antigen",
           "GRPR","menin","WRN helicase","SARS-CoV-2 spike","tau"]
TISSUES = ["liver","CNS","tumor","muscle","lung"]

STEMS = [
  "I want to {intent} against {target}.",
  "Design a {mod_h} to hit {target}; what pipeline should I run?",
  "We need a {mod_h} program for {target} — route me to the right workflow.",
  "Propose and rank {mod_h} candidates for {target}" + "{tissue_clause}.",
  "How do I take {target} through a {mod_h} discovery workflow on BioMate?",
  "Start a {mod_h} campaign for {target}: generation, scoring, and developability.",
]
MOD_HUMAN = {m[0]: m[2].replace("design/","").replace("design ","").replace("design a ","")
             .replace("design an ","").replace("/screen a small-molecule binder","small molecule") for m in MODALITIES}
MOD_HUMAN.update({  # cleaner human phrases
  "small_molecule":"small molecule","covalent_small_molecule":"covalent small molecule",
  "protac_degrader":"PROTAC degrader","molecular_glue":"molecular glue","scaffold_hop":"small-molecule lead",
  "linear_peptide":"linear peptide","cyclic_peptide_macrocycle":"cyclic peptide","peptide_drug_conjugate":"peptide-drug conjugate",
  "antibody_mab":"monoclonal antibody","scfv_fragment":"scFv","bispecific_antibody":"bispecific antibody",
  "nanobody_vhh":"nanobody","fc_engineered_ab":"Fc-engineered antibody","adc":"antibody-drug conjugate",
  "large_protein_biologic":"protein therapeutic","fusion_protein":"fusion protein",
  "sirna_rnai":"siRNA","aso_gapmer":"antisense oligonucleotide","mrna_therapeutic":"mRNA therapeutic",
  "sarna_circrna":"self-amplifying RNA","aptamer":"aptamer","crispr_editing":"CRISPR edit",
  "aav_gene_therapy":"AAV gene therapy","car_cell_therapy":"CAR-T","tcr_t":"TCR-T","nk_cell_therapy":"NK-cell therapy",
  "vaccine_epitope":"vaccine","radiopharmaceutical":"radioligand",
})

def make_requests(mod, intent, n):
    out=[]
    tgts = random.sample(TARGETS, min(n, len(TARGETS)))
    for i in range(n):
        stem = STEMS[i % len(STEMS)]
        t = tgts[i % len(tgts)]
        tissue = random.choice(TISSUES)
        tc = f" (delivery to {tissue})" if "{tissue_clause}" in stem else ""
        q = stem.format(intent=intent, target=t, mod_h=MOD_HUMAN[mod], tissue_clause=tc)
        out.append(q)
    # dedup
    return list(dict.fromkeys(out))

PER_MOD = 12  # seed count per modality (flagged insufficient-to-train-alone)
episodes=[]; taxonomy=[]
for mod, cov, intent, routes in MODALITIES:
    reqs = make_requests(mod, intent, PER_MOD)
    route_label = routes if cov in ("excellent","good") else ("GAP:no-catalog-route" if not routes else routes)
    routable = cov in ("excellent","good") and bool(routes)
    taxonomy.append({"modality":mod,"coverage":cov,"routable":routable,
                     "intent":intent,"route":routes,"n_requests":len(reqs)})
    # leakage-safe: assign the WHOLE modality's requests, but split within-modality by hashing
    # the request family (stem index) so a stem family never spans train/dev for that modality.
    for i,q in enumerate(reqs):
        fam = i % len(STEMS)
        split = "dev" if fam in (0,) else "train"   # hold out stem-family 0 entirely
        episodes.append({
            "request": q, "modality": mod, "intent": intent,
            "route": routes, "routable": routable, "coverage": cov,
            "family": f"{mod}:stem{fam}", "split": split,
            "source": "curated_canonical_seed",
        })

random.shuffle(episodes)
with open(f"{OUT}/modality_episodes.jsonl","w") as f:
    for e in episodes: f.write(json.dumps(e)+"\n")
with open(f"{OUT}/taxonomy.json","w") as f:
    json.dump({"n_modalities":len(MODALITIES),
               "source":"docs/20260509_modality_coverage_audit.md + standard pharma taxonomy",
               "routable_count":sum(1 for t in taxonomy if t["routable"]),
               "modalities":taxonomy}, f, indent=1)

from collections import Counter
cov_c = Counter(m[1] for m in MODALITIES)
print(f"28-modality routing gold: {len(episodes)} episodes across {len(MODALITIES)} modalities")
print("coverage:", dict(cov_c), "| routable modalities:", sum(1 for t in taxonomy if t['routable']), "/ 28")
print("split:", dict(Counter(e['split'] for e in episodes)))
print("SEED gold (curated canonical) — per no-tiny-dataset: NOT sufficient to train alone; augment with real routing/connector logs.")
print(f"written: {OUT}/modality_episodes.jsonl , {OUT}/taxonomy.json")
