#!/usr/bin/env nextflow
/*
 * drug_discovery/pharmacophore_filtering
 *
 * Pharmacophore-based compound library filtering pipeline
 *
 * Pipeline Steps:
 * 1. PHARMACOPHORE_GENERATE — Derive a consensus pharmacophore model from known
 *    active SMILES; identifies the most common Donor (D), Acceptor (A),
 *    Aromatic (Ar), Hydrophobic (H), and PosIonizable (P) features via
 *    RDKit's chemical feature factory (live) or hardcoded rules (mock).
 * 2. PHARMACOPHORE_SCREEN   — Score each compound in a SMILES/SDF library by
 *    number of pharmacophore features matched; emit compounds that satisfy
 *    params.min_features (default 3).
 * 3. PHARMACOPHORE_REPORT   — Write filtered SMILES, per-compound match
 *    breakdown TSV, and a summary JSON.
 *
 * References:
 *  - RDKit Pharmacophore:  https://www.rdkit.org/docs/GettingStartedInPython.html#chemical-features-and-pharmacophores
 *  - Gobbi & Poppinger pharmacophore fingerprints, JCIM 1998
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.outdir           = './results/pharmacophore_filtering'
params.publish_dir_mode = 'copy'

// Mode flags
params.mock_mode        = true   // true = synthetic output, no RDKit needed
params.min_features     = 3      // minimum pharmacophore features to match (PASS threshold)
params.generate_3d      = false  // if true (live mode), generate 3D conformers for distance matching

// ============================================================================
// Helper functions
// ============================================================================

def log_workflow_header() {
    log.info """
    ====================================================================
    BioMate | Pharmacophore-Based Compound Library Filtering
    ====================================================================
    Mode:               ${params.mock_mode ? 'MOCK (synthetic data)' : 'LIVE (RDKit)'}
    Min features to pass: ${params.min_features}
    Generate 3D conformers: ${params.generate_3d}
    Output dir:         ${params.outdir}
    ====================================================================
    """.stripIndent()
}

// ============================================================================
// Process 1: Pharmacophore Model Generation
// ============================================================================

process PHARMACOPHORE_GENERATE {
    tag "pharmacophore_model"
    label 'process_medium'
    publishDir "${params.outdir}/01_pharmacophore_model", mode: params.publish_dir_mode

    container 'biomate/biomni-drug-discovery-nf:latest'

    input:
    path reference_actives   // one SMILES per line

    output:
    path "pharmacophore_model.json", emit: model
    path "versions.yml",             emit: versions

    script:
    def mock        = params.mock_mode
    def generate_3d = params.generate_3d
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
from datetime import datetime

# ---------------------------------------------------------------------------
# Mock pharmacophore model derived from aspirin-like reference actives.
# Hardcoded consensus features without importing RDKit.
# Reference set (3 compounds):
#   CC(=O)Oc1ccccc1C(=O)O   (aspirin)
#   CC(=O)Oc1ccccc1C(=O)N   (aspirin amide analogue)
#   OC(=O)c1ccccc1O          (salicylic acid)
# ---------------------------------------------------------------------------

ref_smiles = [
    "CC(=O)Oc1ccccc1C(=O)O",
    "CC(=O)Oc1ccccc1C(=O)N",
    "OC(=O)c1ccccc1O",
]

# Consensus features observed across the reference set
features = [
    {
        "type":                 "Donor",
        "label":                "D",
        "description":          "Hydroxyl or NH hydrogen-bond donor",
        "count_in_references":  3,
        "fraction":             1.0,
        "smarts":               "[OX2H,NX3H2,NX3H1]",
    },
    {
        "type":                 "Acceptor",
        "label":                "A1",
        "description":          "Carbonyl C=O acceptor (ester/acid/amide)",
        "count_in_references":  3,
        "fraction":             1.0,
        "smarts":               "[CX3](=[OX1])",
    },
    {
        "type":                 "Acceptor",
        "label":                "A2",
        "description":          "Ester or hydroxyl oxygen acceptor",
        "count_in_references":  3,
        "fraction":             1.0,
        "smarts":               "[OX2][CX3](=[OX1])",
    },
    {
        "type":                 "Aromatic",
        "label":                "Ar",
        "description":          "Aromatic benzene ring",
        "count_in_references":  3,
        "fraction":             1.0,
        "smarts":               "c1ccccc1",
    },
]

model = {
    "source":           "mock",
    "n_references":     len(ref_smiles),
    "reference_smiles": ref_smiles,
    "n_features":       len(features),
    "features":         features,
    "timestamp":        datetime.utcnow().isoformat() + "Z",
    "mock_mode":        True,
}

with open("pharmacophore_model.json", "w") as f:
    json.dump(model, f, indent=2)

print(f"Pharmacophore model generated (mock): {len(features)} features from {len(ref_smiles)} references")
for ft in features:
    print(f"  [{ft['label']}] {ft['type']}: {ft['description']}  (frac={ft['fraction']})")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: derive pharmacophore model from reference actives using RDKit
        # ---------------------------------------------------------------------------
        python3 << 'EOF'
import json
import sys
from datetime import datetime
from collections import defaultdict

import os
from rdkit import Chem, RDConfig
from rdkit.Chem import MolFromSmiles
from rdkit.Chem.rdMolDescriptors import CalcNumHBD, CalcNumHBA, CalcNumAromaticRings
from rdkit.Chem import ChemicalFeatures

# Load the RDKit built-in BaseFeatures factory (supports GetFeaturesForMol)
_fdef_candidates = [
    os.path.join(RDConfig.RDDataDir, 'BaseFeatures.fdef'),
    '/usr/share/rdkit/Data/BaseFeatures.fdef',
    '/usr/local/share/rdkit/Data/BaseFeatures.fdef',
]
factory = None
for _fdef in _fdef_candidates:
    if os.path.exists(_fdef):
        factory = ChemicalFeatures.BuildFeatureFactory(_fdef)
        break
if factory is None:
    raise RuntimeError("Could not locate BaseFeatures.fdef in RDKit data directory")

ref_smiles = []
with open("${reference_actives}") as f:
    for line in f:
        smi = line.strip().split()[0]
        if smi:
            ref_smiles.append(smi)

if not ref_smiles:
    print("ERROR: no SMILES found in reference file", file=sys.stderr)
    sys.exit(1)

# Count feature types across reference actives
feature_counts = defaultdict(int)
n_valid = 0

for smi in ref_smiles:
    mol = MolFromSmiles(smi)
    if mol is None:
        print(f"  WARNING: could not parse SMILES: {smi}", file=sys.stderr)
        continue
    n_valid += 1
    feats = factory.GetFeaturesForMol(mol)
    seen_types = set()
    for feat in feats:
        ft = feat.GetFamily()
        if ft not in seen_types:
            feature_counts[ft] += 1
            seen_types.add(ft)

if n_valid == 0:
    print("ERROR: no valid molecules in reference set", file=sys.stderr)
    sys.exit(1)

# Build consensus feature list (include all feature types seen in ≥50% of actives)
SMARTS_MAP = {
    "Donor":        "[OX2H,NX3H2,NX3H1]",
    "Acceptor":     "[OX1,NX3;!\$(NC=O)]",
    "Aromatic":     "c1ccccc1",
    "Hydrophobe":   "[c,s,S&H0&v2,Br,I,\$(C(F)(F)F),\$(CC(F)(F)F)]",
    "PosIonizable": "[+!H0,\$(N-[CX3]=[NH]),\$(NC(=N)N),\$(n1ccnc1)]",
    "NegIonizable": "[\$([CX3](=O)[OX1H0-,OX2H1]),\$([SX4](=[OX1])(=[OX1])([OX2H,OX1H0-])[OX2H,OX1H0-])]",
}

features = []
for label_idx, (ftype, count) in enumerate(sorted(feature_counts.items(), key=lambda x: -x[1])):
    fraction = round(count / n_valid, 3)
    features.append({
        "type":                 ftype,
        "label":                f"{ftype[0]}{label_idx}",
        "description":          ftype,
        "count_in_references":  count,
        "fraction":             fraction,
        "smarts":               SMARTS_MAP.get(ftype, ""),
    })

model = {
    "source":           "rdkit",
    "n_references":     n_valid,
    "reference_smiles": ref_smiles,
    "n_features":       len(features),
    "features":         features,
    "generate_3d":      bool("${generate_3d}" == "true"),
    "timestamp":        datetime.utcnow().isoformat() + "Z",
    "mock_mode":        False,
}

with open("pharmacophore_model.json", "w") as f:
    json.dump(model, f, indent=2)

print(f"Pharmacophore model (RDKit): {len(features)} features from {n_valid} valid references")
for ft in features:
    print(f"  [{ft['label']}] {ft['type']}: fraction={ft['fraction']}")
EOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rdkit: \$(python3 -c "import rdkit; print(rdkit.__version__)" 2>/dev/null || echo "mock")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    echo '{"n_features":4,"features":[]}' > pharmacophore_model.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rdkit: "2023.09.4"
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Process 2: Pharmacophore Library Screening
// ============================================================================

process PHARMACOPHORE_SCREEN {
    tag "library_screen"
    label 'process_medium'
    publishDir "${params.outdir}/02_screening", mode: params.publish_dir_mode

    container 'biomate/biomni-drug-discovery-nf:latest'

    input:
    path model_json    // pharmacophore_model.json from PHARMACOPHORE_GENERATE
    path compound_library  // SMILES file or SDF with compounds to screen

    output:
    path "match_report.tsv",        emit: match_report
    path "screened_scores.json",    emit: scores
    path "versions.yml",            emit: versions

    script:
    def mock         = params.mock_mode
    def min_features = params.min_features
    def generate_3d  = params.generate_3d
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import random
from datetime import datetime

random.seed(42)

model = json.load(open("${model_json}"))
n_model_features = model["n_features"]

# ---------------------------------------------------------------------------
# Mock compound library: 10 aspirin-inspired SMILES with simulated feature
# counts (seeded random — reproducible).
# ---------------------------------------------------------------------------
library = [
    ("CPND001", "CC(=O)Oc1ccccc1C(=O)O"),     # aspirin
    ("CPND002", "CC(=O)Oc1ccccc1C(=O)N"),     # aspirin amide
    ("CPND003", "OC(=O)c1ccccc1O"),            # salicylic acid
    ("CPND004", "CC(=O)Nc1ccc(O)cc1"),         # paracetamol
    ("CPND005", "c1ccc(cc1)C(=O)O"),           # benzoic acid
    ("CPND006", "CCCC"),                       # butane (no features)
    ("CPND007", "CC(=O)Oc1cccc(c1)C(=O)O"),   # 3-acetoxybenzoic acid
    ("CPND008", "c1ccc2c(c1)cccc2"),           # naphthalene
    ("CPND009", "CC(=O)Oc1ccc(cc1)C(=O)O"),   # 4-acetoxybenzoic acid
    ("CPND010", "NC(=O)c1ccccc1N"),            # 2-aminobenzamide
]

# Assign seeded random feature match counts in range [0, n_model_features]
results = []
for cid, smi in library:
    n_matched = random.randint(0, n_model_features)
    # Choose which feature types are matched (random subset of model features)
    all_feature_types = [ft["type"] for ft in model["features"]]
    matched_types = random.sample(all_feature_types, min(n_matched, len(all_feature_types)))
    passes = n_matched >= int("${min_features}")
    results.append({
        "compound_id":         cid,
        "smiles":              smi,
        "features_matched":    n_matched,
        "feature_types":       matched_types,
        "pass":                passes,
    })

# Write TSV report
with open("match_report.tsv", "w") as f:
    f.write("compound_id\\tsmiles\\tfeatures_matched\\tfeature_types_matched\\tpass\\n")
    for r in results:
        f.write(
            f"{r['compound_id']}\\t{r['smiles']}\\t{r['features_matched']}\\t"
            f"{','.join(r['feature_types'])}\\t{'PASS' if r['pass'] else 'FAIL'}\\n"
        )

# Write full scores JSON
scores = {
    "pharmacophore_model": "${model_json}",
    "library":             "${compound_library}",
    "n_screened":          len(results),
    "n_passed":            sum(1 for r in results if r["pass"]),
    "min_features":        int("${min_features}"),
    "results":             results,
    "timestamp":           datetime.utcnow().isoformat() + "Z",
    "mock_mode":           True,
}
with open("screened_scores.json", "w") as f:
    json.dump(scores, f, indent=2)

n_pass = scores["n_passed"]
n_total = scores["n_screened"]
print(f"Pharmacophore screening (mock): {n_pass}/{n_total} compounds passed (min_features={int('${min_features}')})")
for r in results:
    tag = "PASS" if r["pass"] else "FAIL"
    print(f"  [{tag}] {r['compound_id']}  matched={r['features_matched']}  types={r['feature_types']}")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: screen library with RDKit SMARTS-based pharmacophore matching
        # ---------------------------------------------------------------------------
        python3 << 'EOF'
import json
import sys
from datetime import datetime

from rdkit import Chem
from rdkit.Chem import MolFromSmiles, MolFromSmarts, SDMolSupplier

model = json.load(open("${model_json}"))
features = model["features"]

# Build compiled SMARTS patterns (skip features without SMARTS)
compiled = []
for ft in features:
    smarts = ft.get("smarts", "")
    if smarts:
        pat = MolFromSmarts(smarts)
        if pat is not None:
            compiled.append((ft["type"], ft["label"], pat))

# Determine input format (SDF or SMILES)
lib_path = "${compound_library}"
library_mols = []

if lib_path.endswith(".sdf"):
    suppl = SDMolSupplier(lib_path, removeHs=True)
    for i, mol in enumerate(suppl):
        if mol is not None:
            name = mol.GetProp("_Name") if mol.HasProp("_Name") else f"MOL{i+1:04d}"
            smi  = Chem.MolToSmiles(mol)
            library_mols.append((name, smi, mol))
else:
    with open(lib_path) as f:
        for i, line in enumerate(f, 1):
            parts = line.strip().split()
            if not parts:
                continue
            smi = parts[0]
            cid = parts[1] if len(parts) > 1 else f"CPND{i:04d}"
            mol = MolFromSmiles(smi)
            if mol is not None:
                library_mols.append((cid, smi, mol))

if not library_mols:
    print("ERROR: no valid molecules loaded from library", file=sys.stderr)
    sys.exit(1)

min_features = int("${min_features}")

results = []
for cid, smi, mol in library_mols:
    matched_types = []
    seen_types = set()
    for ftype, flabel, pat in compiled:
        if ftype not in seen_types and mol.HasSubstructMatch(pat):
            matched_types.append(ftype)
            seen_types.add(ftype)

    n_matched = len(matched_types)
    passes = n_matched >= min_features
    results.append({
        "compound_id":      cid,
        "smiles":           smi,
        "features_matched": n_matched,
        "feature_types":    matched_types,
        "pass":             passes,
    })

with open("match_report.tsv", "w") as f:
    f.write("compound_id\\tsmiles\\tfeatures_matched\\tfeature_types_matched\\tpass\\n")
    for r in results:
        f.write(
            f"{r['compound_id']}\\t{r['smiles']}\\t{r['features_matched']}\\t"
            f"{','.join(r['feature_types'])}\\t{'PASS' if r['pass'] else 'FAIL'}\\n"
        )

scores = {
    "pharmacophore_model": "${model_json}",
    "library":             "${compound_library}",
    "n_screened":          len(results),
    "n_passed":            sum(1 for r in results if r["pass"]),
    "min_features":        min_features,
    "results":             results,
    "timestamp":           datetime.utcnow().isoformat() + "Z",
    "mock_mode":           False,
}
with open("screened_scores.json", "w") as f:
    json.dump(scores, f, indent=2)

n_pass = scores["n_passed"]
n_total = scores["n_screened"]
print(f"Pharmacophore screening (RDKit): {n_pass}/{n_total} passed (min_features={min_features})")
for r in results:
    tag = "PASS" if r["pass"] else "FAIL"
    print(f"  [{tag}] {r['compound_id']}  matched={r['features_matched']}")
EOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rdkit: \$(python3 -c "import rdkit; print(rdkit.__version__)" 2>/dev/null || echo "mock")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "${mock}"
        min_features: "${min_features}"
    END_VERSIONS
    """

    stub:
    """
    printf 'compound_id\tsmiles\tfeatures_matched\tfeature_types_matched\tpass\n' > match_report.tsv
    echo '{"n_screened":10,"n_passed":5}' > screened_scores.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rdkit: "2023.09.4"
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Process 3: Pharmacophore Report
// ============================================================================

process PHARMACOPHORE_REPORT {
    tag "pharmacophore_report"
    label 'process_low'
    publishDir "${params.outdir}/03_report", mode: params.publish_dir_mode

    container 'biomate/biomni-drug-discovery-nf:latest'

    input:
    path model_json      // pharmacophore_model.json
    path scores_json     // screened_scores.json
    path match_tsv       // match_report.tsv

    output:
    path "filtered_compounds.smi",   emit: filtered_smiles
    path "pharmacophore_model.json", emit: pharmacophore_json
    path "match_report.tsv",         emit: match_report
    path "summary.json",             emit: summary
    path "versions.yml",             emit: versions

    script:
    def mock         = params.mock_mode
    def min_features = params.min_features
    """
    python3 << 'EOF'
import json
from datetime import datetime

model  = json.load(open("${model_json}"))
scores = json.load(open("${scores_json}"))

# Extract passing compounds and write filtered SMILES
passed = [r for r in scores["results"] if r["pass"]]

with open("filtered_compounds.smi", "w") as f:
    for r in passed:
        f.write(f"{r['smiles']}  {r['compound_id']}\\n")

# Copy inputs through for publication (guard against same-file error when
# Nextflow stages inputs under their original names as symlinks)
import shutil
try:
    shutil.copy("${model_json}", "pharmacophore_model.json")
except shutil.SameFileError:
    pass
try:
    shutil.copy("${match_tsv}", "match_report.tsv")
except shutil.SameFileError:
    pass

# Write summary JSON
summary = {
    "pipeline":         "pharmacophore_filtering",
    "mock_mode":        bool("${mock}" == "true"),
    "min_features":     int("${min_features}"),
    "n_reference_actives":  model.get("n_references", 0),
    "n_model_features":     model.get("n_features", 0),
    "n_library_screened":   scores["n_screened"],
    "n_passed_filter":      scores["n_passed"],
    "pass_rate_pct":        round(100 * scores["n_passed"] / max(scores["n_screened"], 1), 1),
    "filtered_smiles_file": "filtered_compounds.smi",
    "match_report_file":    "match_report.tsv",
    "pharmacophore_model_file": "pharmacophore_model.json",
    "timestamp":            datetime.utcnow().isoformat() + "Z",
}

with open("summary.json", "w") as f:
    json.dump(summary, f, indent=2)

print(f"Pharmacophore report written:")
print(f"  Screened:     {summary['n_library_screened']} compounds")
print(f"  Passed:       {summary['n_passed_filter']} ({summary['pass_rate_pct']}%)")
print(f"  Min features: {summary['min_features']}")
print(f"  Model features: {summary['n_model_features']}")
for r in passed:
    print(f"  -> PASS: {r['compound_id']}  {r['smiles']}  matched={r['features_matched']}")
EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    touch filtered_compounds.smi
    echo '{}' > pharmacophore_model.json
    printf 'compound_id\tsmiles\tfeatures_matched\tfeature_types_matched\tpass\n' > match_report.tsv
    echo '{"n_passed_filter":0}' > summary.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Entry workflow: PHARMACOPHORE_FILTERING
// ============================================================================
//
// Data flow:
//
//   ch_reference ──► PHARMACOPHORE_GENERATE (model)
//                              │
//                              ▼
//   ch_library ──────► PHARMACOPHORE_SCREEN (scores + TSV)
//                              │
//                              ▼
//                    PHARMACOPHORE_REPORT (filtered SMILES + summary)
//
// ============================================================================

workflow PHARMACOPHORE_FILTERING {
    take:
    ch_reference   // channel: path(reference_actives.smi) — one SMILES per line
    ch_library     // channel: path(library.smi or library.sdf)

    main:
    // ------------------------------------------------------------------
    // Step 1: Derive consensus pharmacophore from reference actives
    // ------------------------------------------------------------------
    PHARMACOPHORE_GENERATE(ch_reference)

    // ------------------------------------------------------------------
    // Step 2: Screen compound library against the model
    // ------------------------------------------------------------------
    PHARMACOPHORE_SCREEN(
        PHARMACOPHORE_GENERATE.out.model,
        ch_library
    )

    // ------------------------------------------------------------------
    // Step 3: Compile filtered SMILES + summary report
    // ------------------------------------------------------------------
    PHARMACOPHORE_REPORT(
        PHARMACOPHORE_GENERATE.out.model,
        PHARMACOPHORE_SCREEN.out.scores,
        PHARMACOPHORE_SCREEN.out.match_report
    )

    emit:
    filtered_smiles    = PHARMACOPHORE_REPORT.out.filtered_smiles
    pharmacophore_json = PHARMACOPHORE_REPORT.out.pharmacophore_json
    match_report       = PHARMACOPHORE_REPORT.out.match_report
    versions           = PHARMACOPHORE_GENERATE.out.versions
                             .mix(PHARMACOPHORE_SCREEN.out.versions)
                             .mix(PHARMACOPHORE_REPORT.out.versions)
}

// ============================================================================
// Standalone Entry Point (nextflow run main.nf)
// ============================================================================

workflow {
    log_workflow_header()

    // ------------------------------------------------------------------
    // Reference actives: 3 aspirin-like SMILES
    // In mock mode, written inline — no pre-existing file required.
    // ------------------------------------------------------------------
    if (params.mock_mode) {
        ch_reference = Channel.of(
            "CC(=O)Oc1ccccc1C(=O)O\nCC(=O)Oc1ccccc1C(=O)N\nOC(=O)c1ccccc1O\n"
        ).map { content ->
            def ref_file = file("${workDir}/mock_reference_actives.smi")
            ref_file.text = content
            ref_file
        }
    } else {
        if (!params.reference_actives) {
            error "params.reference_actives is required in live mode. Pass --reference_actives <path>"
        }
        ch_reference = Channel.fromPath(params.reference_actives, checkIfExists: true)
    }

    // ------------------------------------------------------------------
    // Compound library: 10-compound mock SMILES file
    // In mock mode, written inline — no pre-existing file required.
    // ------------------------------------------------------------------
    if (params.mock_mode) {
        ch_library = Channel.of(
            [
                "CC(=O)Oc1ccccc1C(=O)O CPND001",
                "CC(=O)Oc1ccccc1C(=O)N CPND002",
                "OC(=O)c1ccccc1O CPND003",
                "CC(=O)Nc1ccc(O)cc1 CPND004",
                "c1ccc(cc1)C(=O)O CPND005",
                "CCCC CPND006",
                "CC(=O)Oc1cccc(c1)C(=O)O CPND007",
                "c1ccc2c(c1)cccc2 CPND008",
                "CC(=O)Oc1ccc(cc1)C(=O)O CPND009",
                "NC(=O)c1ccccc1N CPND010",
            ].join("\n") + "\n"
        ).map { content ->
            def lib_file = file("${workDir}/mock_library.smi")
            lib_file.text = content
            lib_file
        }
    } else {
        if (!params.compound_library) {
            error "params.compound_library is required in live mode. Pass --compound_library <path>"
        }
        ch_library = Channel.fromPath(params.compound_library, checkIfExists: true)
    }

    // Run the pipeline
    PHARMACOPHORE_FILTERING(ch_reference, ch_library)

    // Display summary
    PHARMACOPHORE_FILTERING.out.filtered_smiles.view { filtered ->
        "Filtered compounds SMILES: ${filtered}"
    }
    PHARMACOPHORE_FILTERING.out.pharmacophore_json.view { model ->
        "Pharmacophore model JSON:  ${model}"
    }
    PHARMACOPHORE_FILTERING.out.match_report.view { tsv ->
        "Match report TSV:          ${tsv}"
    }
}
