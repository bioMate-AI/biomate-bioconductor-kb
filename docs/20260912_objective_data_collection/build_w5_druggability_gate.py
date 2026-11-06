"""W5 — Druggability GATE data builder (modality-fit filter, not a learned score).

Combines three evidence sources for 20 canonical immune targets:
  1. BindingDB (S3 BindingDB_All_202409.tsv.gz, streamed single-pass, matched on
     UniProt primary/secondary accession) -> small-molecule LIGANDABILITY:
     affinity values (Ki/IC50/Kd/EC50), potent-binder counts, MEASURED-inactive
     counts, distinct ChEMBL ligands, organisms.  (see extract_bindingdb.awk)
  2. ChEMBL tractability (druggability_chembl.json) -> mechanisms, action types,
     intended clinical modality (small-molecule vs biologic).
  3. UniProt localization (secreted / membrane / intracellular) + established
     target-family biology -> modality-fit class + PPI-interface / cyclic-peptide
     fit HEURISTIC.

GATE, not a training label:  training_eligible=false.

DISCIPLINE:
  - "untested" != "inactive".  A target with zero BindingDB small-molecule rows is
    NOT declared undruggable-by-small-molecule; it is small-molecule-UNTESTED /
    biologic-validated.  Measured inactivity is counted ONLY from real weak values
    (>=10 uM) and '>' censored high values, reported separately.
  - The cyclic-peptide-fit field is an EXPLICIT HEURISTIC from target class +
    localization + PPI-interface biology.  We have NO measured cyclic-peptide
    engagement data for any of these targets.  See caveats.
"""
import csv, json, re, statistics
from collections import defaultdict
from pathlib import Path

ROOT = Path("/Users/kky/biomate-review/docs/20260912_objective_data_collection")
SCRATCH = Path("/private/tmp/claude-501/-Users-kky/27e09a8b-714d-43a2-840b-03ea9e70b057/scratchpad")

# ---- established target-family biology for the 20 (authoritative for these well-characterized proteins) ----
# ppi_interface=True  -> mechanism of action is disrupting/engaging a protein-protein interface
#                        (cytokine:receptor, ligand trimer, costimulatory pair) rather than a
#                        deep small-molecule orthosteric pocket.  Cyclic peptides excel here.
FAMILY = {
    "IL6R":     dict(family="cytokine receptor (IL-6Ra)",            has_deep_pocket=False, ppi_interface=True),
    "TNF":      dict(family="TNF-superfamily ligand (trimer)",       has_deep_pocket=False, ppi_interface=True),
    "MS4A1":    dict(family="4-TM cell-surface antigen (CD20)",      has_deep_pocket=False, ppi_interface=False),
    "TNFSF13B": dict(family="TNF-superfamily ligand (BAFF)",         has_deep_pocket=False, ppi_interface=True),
    "JAK1":     dict(family="tyrosine kinase (JAK)",                 has_deep_pocket=True,  ppi_interface=False),
    "JAK2":     dict(family="tyrosine kinase (JAK)",                 has_deep_pocket=True,  ppi_interface=False),
    "JAK3":     dict(family="tyrosine kinase (JAK)",                 has_deep_pocket=True,  ppi_interface=False),
    "BTK":      dict(family="tyrosine kinase (TEC/BTK)",             has_deep_pocket=True,  ppi_interface=False),
    "IL17A":    dict(family="secreted cytokine (IL-17 homodimer)",   has_deep_pocket=False, ppi_interface=True),
    "IL23A":    dict(family="secreted cytokine (IL-23 p19/p40)",     has_deep_pocket=False, ppi_interface=True),
    "IL4R":     dict(family="cytokine receptor (IL-4Ra)",            has_deep_pocket=False, ppi_interface=True),
    "IL5":      dict(family="secreted cytokine (IL-5)",              has_deep_pocket=False, ppi_interface=True),
    "TSLP":     dict(family="secreted cytokine (TSLP)",              has_deep_pocket=False, ppi_interface=True),
    "IL5RA":    dict(family="cytokine receptor (IL-5Ra)",            has_deep_pocket=False, ppi_interface=True),
    "CTLA4":    dict(family="Ig-superfamily costimulatory receptor", has_deep_pocket=False, ppi_interface=True),
    "IFNAR1":   dict(family="cytokine receptor (IFNAR1)",            has_deep_pocket=False, ppi_interface=True),
    "S1PR1":    dict(family="lipid GPCR (S1P1)",                     has_deep_pocket=True,  ppi_interface=False),
    "IL1B":     dict(family="secreted cytokine (IL-1b)",             has_deep_pocket=False, ppi_interface=True),
    "IL13":     dict(family="secreted cytokine (IL-13)",             has_deep_pocket=False, ppi_interface=True),
    "IL12B":    dict(family="secreted cytokine (IL-12/23 p40)",      has_deep_pocket=False, ppi_interface=True),
}

# thresholds
POTENT_STRONG = 100.0   # nM
POTENT = 1000.0         # nM (1 uM)
WEAK = 10000.0          # nM (10 uM) -- measured weak/inactive evidence


def parse_val(s):
    if not s: return None
    s = s.strip()
    if not s: return None
    m = re.match(r'^\s*([<>~=]*)\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)', s)
    if not m: return None
    try: v = float(m.group(2))
    except ValueError: return None
    return (m.group(1), v)


def analyze_bindingdb():
    genes = defaultdict(lambda: {"n_rows": 0, "vals": [], "ligands": set(),
                                 "organisms": defaultdict(int), "mtypes": defaultdict(int),
                                 "pot100": 0, "pot1u": 0, "weak": 0, "cens": 0})
    path = SCRATCH / "bindingdb_matched.tsv"
    with open(path) as f:
        for row in csv.reader(f, delimiter="\t"):
            if len(row) < 7: continue
            gene, ki, ic50, kd, ec50, lig, org = row[:7]
            g = genes[gene]; g["n_rows"] += 1
            if org: g["organisms"][org] += 1
            if lig.strip(): g["ligands"].add(lig.strip())
            best = None
            for label, raw in (("Ki", ki), ("IC50", ic50), ("Kd", kd), ("EC50", ec50)):
                pv = parse_val(raw)
                if pv is None: continue
                op, v = pv
                g["mtypes"][label] += 1
                if v > 0: g["vals"].append(v)
                if op == ">":
                    g["cens"] += 1
                    if v >= WEAK: g["weak"] += 1
                    continue
                if best is None or v < best: best = v
                if v >= WEAK: g["weak"] += 1
            if best is not None:
                if best <= POTENT_STRONG: g["pot100"] += 1
                if best <= POTENT: g["pot1u"] += 1
    out = {}
    for gene, g in genes.items():
        vals = g["vals"]
        out[gene] = {
            "n_measurement_rows": g["n_rows"],
            "n_distinct_chembl_ligands": len(g["ligands"]),
            "n_affinity_values": len(vals),
            "measurement_type_counts": dict(g["mtypes"]),
            "min_affinity_nM": min(vals) if vals else None,
            "median_affinity_nM": round(statistics.median(vals), 2) if vals else None,
            "n_potent_le_100nM": g["pot100"],
            "n_potent_le_1uM": g["pot1u"],
            "n_measured_weak_ge_10uM": g["weak"],
            "n_censored_greater_than": g["cens"],
            "top_organisms": dict(sorted(g["organisms"].items(), key=lambda x: -x[1])[:4]),
        }
    return out


def classify(gene, bdb, fam, loc, chembl):
    """Deterministic modality-fit gate + cyclic-peptide-fit heuristic."""
    n_pot = bdb["n_potent_le_1uM"] if bdb else 0
    n_rows = bdb["n_measurement_rows"] if bdb else 0
    intended = chembl.get("intended_modality", "")
    is_sm_intended = any(k in intended for k in ("inhibitor", "modulator")) and "mAb" not in intended

    # small-molecule ligandability tier
    if n_pot >= 200:
        sm_tier = "small-molecule-tractable (validated)"
    elif n_pot >= 20:
        sm_tier = "small-molecule-emerging"
    elif n_rows == 0:
        sm_tier = "small-molecule-untested (no BindingDB small-molecule data)"
    else:
        sm_tier = "small-molecule-weak/limited"

    secreted = loc.get("secreted", False)
    # membrane flag: trust family biology (JAK keyword false-positive guarded)
    fam_str = fam["family"]
    intracellular = fam_str.startswith("tyrosine kinase")
    membrane_surface = ("receptor" in fam_str or "GPCR" in fam_str or "antigen" in fam_str) and not intracellular

    # primary modality classification (the GATE label)
    if fam["has_deep_pocket"] and n_pot >= 200:
        modality_class = "small-molecule"
    elif secreted or membrane_surface:
        # surface / secreted -> antibody-accessible
        modality_class = "biologic (antibody / Fc-fusion accessible)"
        if n_pot >= 20:
            modality_class = "biologic-primary; small-molecule/PPI-inhibitor emerging"
    else:
        modality_class = "biologic" if not is_sm_intended else "small-molecule"

    # cyclic-peptide-fit HEURISTIC (NOT measured)
    cp_reasons = []
    cp = "low"
    if fam["ppi_interface"]:
        cp_reasons.append("mechanism is a protein-protein interface (cytokine:receptor / ligand / costimulatory) — the interface class cyclic peptides are best suited to")
        cp = "candidate"
    if secreted:
        cp_reasons.append("secreted/extracellular — accessible to a non-cell-penetrant cyclic peptide")
    if membrane_surface and not secreted:
        cp_reasons.append("cell-surface extracellular domain — accessible without cell penetration")
    if intracellular:
        cp_reasons.append("intracellular target — a cyclic peptide would need cell penetration (a hard, unsolved constraint) -> poor fit unless a penetrant macrocycle")
        cp = "low"
    if fam["has_deep_pocket"] and not fam["ppi_interface"]:
        cp_reasons.append("deep orthosteric small-molecule pocket already well served by small molecules; cyclic peptide not the differentiating modality")
        if cp != "candidate":
            cp = "low"
    if bdb and bdb["n_potent_le_1uM"] >= 20 and fam["ppi_interface"]:
        cp_reasons.append(f"{bdb['n_potent_le_1uM']} potent (<=1uM) small-molecule/PPI-inhibitor binders in BindingDB prove the interface is chemically engageable (supports macrocycle feasibility, though not cyclic-peptide-specific)")
        cp = "candidate-strong"

    return {
        "small_molecule_ligandability_tier": sm_tier,
        "modality_class": modality_class,
        "target_family": fam_str,
        "has_deep_smallmolecule_pocket": fam["has_deep_pocket"],
        "is_ppi_interface_target": fam["ppi_interface"],
        "localization": {"secreted": secreted, "surface_membrane": bool(membrane_surface),
                         "intracellular": intracellular,
                         "uniprot_subcellular": loc.get("subcellular", [])},
        "cyclic_peptide_fit_heuristic": cp,
        "cyclic_peptide_fit_reasons": cp_reasons,
    }


def main():
    bdb_all = analyze_bindingdb()
    loc_all = json.load(open(SCRATCH / "uniprot_localization.json"))
    gene_uniprot = json.load(open(SCRATCH / "gene_uniprot.json"))
    chembl_list = json.load(open(ROOT / "druggability_chembl.json"))
    chembl_by_gene = {r["gene"]: r for r in chembl_list}

    records = []
    for gene in FAMILY:
        bdb = bdb_all.get(gene)
        fam = FAMILY[gene]
        loc = loc_all.get(gene, {})
        chembl = chembl_by_gene.get(gene, {})
        cls = classify(gene, bdb, fam, loc, chembl)
        rec = {
            "gene": gene,
            "uniprot": gene_uniprot.get(gene, [None])[0],
            "intended_clinical_modality": chembl.get("intended_modality"),
            "chembl_id": chembl.get("chembl_id"),
            "chembl_n_mechanisms": chembl.get("n_mechanisms"),
            "chembl_action_types": chembl.get("action_types"),
            "bindingdb_ligandability": bdb or {
                "n_measurement_rows": 0, "note": "no BindingDB rows matched this UniProt accession — small-molecule UNTESTED (NOT proven inactive)"},
            **cls,
            "training_eligible": False,
        }
        records.append(rec)

    # tallies
    sm = [r["gene"] for r in records if r["modality_class"].startswith("small-molecule")]
    biologic = [r["gene"] for r in records if r["modality_class"].startswith("biologic")]
    ppi = [r["gene"] for r in records if r["is_ppi_interface_target"]]
    cp_cand = [r["gene"] for r in records if r["cyclic_peptide_fit_heuristic"].startswith("candidate")]
    cp_low = [r["gene"] for r in records if r["cyclic_peptide_fit_heuristic"] == "low"]
    sm_untested = [r["gene"] for r in records
                   if r["bindingdb_ligandability"].get("n_measurement_rows", 0) == 0]

    summary = {
        "workstream": "W5",
        "role": "GATE (druggability modality-fit filter — not a learned score)",
        "intended_program_modality": "cyclic peptides",
        "n_targets": len(records),
        "sources": {
            "bindingdb": "s3://knowledge-datasets-1759951976/biomni_data_lake/BindingDB_All_202409.tsv.gz (BindingDB_All_202409); streamed single-pass, matched on UniProt SwissProt primary/secondary accession (cols 43/44)",
            "chembl": "druggability_chembl.json (public ChEMBL API)",
            "uniprot": "rest.uniprot.org localization/keywords",
        },
        "tallies": {
            "small_molecule_modality": {"n": len(sm), "genes": sm},
            "biologic_modality": {"n": len(biologic), "genes": biologic},
            "ppi_interface_targets": {"n": len(ppi), "genes": ppi},
            "cyclic_peptide_fit_candidates_heuristic": {"n": len(cp_cand), "genes": cp_cand},
            "cyclic_peptide_fit_low_heuristic": {"n": len(cp_low), "genes": cp_low},
            "small_molecule_untested_in_bindingdb": {"n": len(sm_untested), "genes": sm_untested},
        },
        "discipline": [
            "GATE not training label; training_eligible=false for every record.",
            "'untested' != 'inactive': targets with zero BindingDB small-molecule rows are small-molecule-UNTESTED, NOT declared undruggable. Measured inactivity counted only from real weak values (>=10 uM) and '>' censored high values, reported separately per target.",
            "modality_class and cyclic_peptide_fit_heuristic are HEURISTICS from target class + localization + PPI-interface biology + BindingDB ligandability — NOT measured cyclic-peptide engagement.",
        ],
        "caveats_what_druggable_by_cyclic_peptide_actually_requires_that_we_DONT_have": [
            "NO measured cyclic-peptide binding for any of the 20 targets. BindingDB affinities here are overwhelmingly small molecules; the counts prove the INTERFACE is chemically engageable, not that a cyclic peptide binds it.",
            "No structural epitope/hotspot analysis (interface area, hotspot residue density, pocket vs flat interface) — a flat interface can still be a poor cyclic-peptide site.",
            "No membrane-permeability assessment. Intracellular targets (JAK1/2/3, BTK) would require cell-penetrant macrocycles — an unsolved general problem; 'PPI-interface' heuristic does NOT rescue them.",
            "No selectivity / paralog cross-reactivity data (e.g. JAK1 vs JAK2, IL12B shared p40 with IL23).",
            "No developability (protease stability, half-life, manufacturability) or PK for a peptide format.",
            "BindingDB coverage is literature/patent-biased: absence of rows reflects what has been screened, not intrinsic undruggability.",
            "Target-family / PPI-interface / pocket flags are curated from established biology for these 20 well-characterized proteins; not machine-derived from a structure database.",
        ],
        "training_eligible": False,
    }

    (ROOT / "W5_druggability_gate.json").write_text(
        json.dumps({"summary": summary, "targets": records}, indent=2) + "\n")

    # ---- markdown ----
    md = []
    md.append("# W5 — Druggability GATE (modality-fit filter)\n")
    md.append("Role: **GATE** (modality-fit filter, not a learned score). "
              "Intended program modality: **cyclic peptides**. `training_eligible=false`.\n")
    md.append(f"Targets: **{len(records)}**. Sources: BindingDB_All_202409 (S3, streamed single-pass, "
              "matched on UniProt accession), ChEMBL tractability, UniProt localization.\n")
    md.append("## Tallies\n")
    md.append(f"- **Small-molecule modality:** {len(sm)} — {', '.join(sm)}")
    md.append(f"- **Biologic modality:** {len(biologic)} — {', '.join(biologic)}")
    md.append(f"- **PPI-interface targets (cyclic-peptide-relevant class):** {len(ppi)} — {', '.join(ppi)}")
    md.append(f"- **Cyclic-peptide-fit CANDIDATES (heuristic):** {len(cp_cand)} — {', '.join(cp_cand)}")
    md.append(f"- **Cyclic-peptide-fit LOW (heuristic):** {len(cp_low)} — {', '.join(cp_low)}")
    md.append(f"- **Small-molecule UNTESTED in BindingDB (NOT inactive):** {len(sm_untested)} — {', '.join(sm_untested)}\n")
    md.append("## Per-target\n")
    md.append("| Gene | Family | Modality class | SM ligandability | BindingDB potent<=1uM | Measured weak>=10uM | Distinct ligands | PPI iface | Cyclic-peptide fit |")
    md.append("|---|---|---|---|---|---|---|---|---|")
    for r in records:
        b = r["bindingdb_ligandability"]
        md.append(f"| {r['gene']} | {r['target_family']} | {r['modality_class']} | "
                  f"{r['small_molecule_ligandability_tier']} | {b.get('n_potent_le_1uM','-')} | "
                  f"{b.get('n_measured_weak_ge_10uM','-')} | {b.get('n_distinct_chembl_ligands','-')} | "
                  f"{'yes' if r['is_ppi_interface_target'] else 'no'} | {r['cyclic_peptide_fit_heuristic']} |")
    md.append("\n## Discipline\n")
    for d in summary["discipline"]:
        md.append(f"- {d}")
    md.append("\n## Caveats — what \"druggable by cyclic peptide\" actually requires that we DON'T have\n")
    for c in summary["caveats_what_druggable_by_cyclic_peptide_actually_requires_that_we_DONT_have"]:
        md.append(f"- {c}")
    md.append("")
    (ROOT / "W5_druggability_gate.md").write_text("\n".join(md) + "\n")

    print(json.dumps(summary["tallies"], indent=2))
    print("\nWrote W5_druggability_gate.json and .md")


if __name__ == "__main__":
    main()
