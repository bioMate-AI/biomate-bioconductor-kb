"""Docking gate — the decisive pre-synthesis compute step, wired to the cheap gates upstream.

Pipeline position: pharmacophore PRESENCE -> liability/SAR flags -> FTO -> *** DOCKING *** -> synthesis.
The two cheap gates (knowledge_liability_flags.py, drug_novelty_fto.py) already narrowed 18 hypotheses to a
liability-clean, FTO-aware shortlist. This harness docks ONLY that shortlist, so no GPU/engine time is spent
on a candidate a free rule already disqualified.

HONESTY: there is NO docking binary in this environment (vina/smina/gnina/obabel all absent), so this gate
does NOT fabricate a ΔG. It (1) decides per-candidate DOCK / DOCK_AFTER_FIX / DROP from the upstream gates,
(2) builds REAL 3D ligand conformers (RDKit ETKDGv3 macrocycle embedding) for the DOCK set, and (3) writes a
run manifest naming the receptor target + box + the engine route to execute. Scoring is an explicit,
separate step (BioMate drug_discovery docking workflow, or smina/vina on AWS spot). status stays
'prepared_not_scored' until a real engine returns poses.

ncAA caveat: ligand SMILES here are the L-backbone (stereo/N-methyl stripped) — fine for the embed/box
smoke, NOT for the scoring pose. Production docking must use the full HELM stereochemistry (D-Pro / N-methyl)
via a macrocycle-aware prep; recorded in the manifest.
"""
from __future__ import annotations
import json, sys
from pathlib import Path
from rdkit import Chem
from rdkit.Chem import AllChem
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import drug_novelty_fto as nf

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "results/docking"; LIGDIR = OUT / "ligands"

# Receptor targets. PDB IDs are CANDIDATES to confirm against RCSB before the real run (not asserted
# as final) — the pocket/MIDAS definition is the load-bearing part.
# Receptors reconciled with the canonical pipeline (docs/20260930_CYCLIC_PEPTIDE_END_TO_END_PROCESS.md,
# boltzgen_ourtarget.sh, launch_mmgbsa_pool.sh): αvβ6 = 9xmm (replaces the gapped 4UM9 that broke design),
# PD-L1 = 5O45. The program's trusted physics discriminator is MM-GBSA on a BoltzGen-cofolded COMPLEX, not
# docking (VALIDATION_LADDER / MMGBSA_RESULTS: MM-GBSA >> docking for these cyclic peptides). This docking
# harness is a cheap PRE-MM-GBSA triage / pose-source alternative only, never the deciding scorer.
TARGETS = {
    "avb6": {"receptor_pdb": "9xmm", "chains": "A,B(αV) + β6; native cyclic RGD peptide in chain E",
             "pocket": "RGD cleft at the αv/β6 interface; Asp carboxylate -> β6 MIDAS Ca/Mn (<5 Å of native ligand)",
             "mmgbsa_pocket": "avb6_pocket_truncate.py: both subunits, residues within 10 Å of peptide (4.5 Å contact shell)"},
    "pdl1": {"receptor_pdb": "5O45", "chains": "A (IgV, 129 res); macrocyclic peptide-71 in chain B",
             "pocket": "PD-L1 IgV front β-sheet hydrophobic cleft (PD-1 / antagonist interface; Tyr56/Met115/Ala121)",
             "mmgbsa_pocket": "whole IgV (small single chain — no truncation needed)"},
}

def decide(target, lab, fto):
    """DOCK / DOCK_AFTER_FIX / DROP from the upstream gates (+ carry caveats)."""
    tier = lab["tier"]; notes = []
    # FTO: drop anything occupied on the patent/genus axis
    if fto and fto.get("occupied") is True and (fto.get("max_seq_identity") or 0) >= nf.DEFAULT_SEQ_ID_CUTOFF:
        return "DROP", ["FTO: occupied on genus sequence axis (seqID>=%.2f) -> redesign before any dock"
                        % nf.DEFAULT_SEQ_ID_CUTOFF]
    if fto:
        st = (fto.get("nearest_known_tag") or {}).get("same_target_max_tanimoto")
        if st and st >= nf.DEFAULT_TANIMOTO_CUTOFF:
            notes.append("FTO-watch: close structural analog to the same-target genus (T=%.2f) — novelty caveat" % st)
    fmt = lambda f: f"{f['code']}: {f['detail']}"
    if tier == "HOLD":
        hard = [fmt(f) for f in lab["flags"] if f["severity"] == "hard"]
        return "DOCK_AFTER_FIX", ["liability HOLD: " + "; ".join(hard)] + notes
    if tier == "WATCH":
        soft = [fmt(f) for f in lab["flags"] if f["severity"] == "soft"]
        return "DOCK_AFTER_FIX", ["liability WATCH: " + "; ".join(soft)] + notes
    return "DOCK", notes

def embed(seq, cyclic=True):
    smi, status = nf.peptide_to_smiles(seq, cyclic=cyclic)
    if not smi:
        return None, "smiles_fail:" + status
    m = Chem.AddHs(Chem.MolFromSmiles(smi))
    p = AllChem.ETKDGv3(); p.randomSeed = 0; p.useMacrocycleTorsions = True; p.maxIterations = 400
    if AllChem.EmbedMolecule(m, p) != 0:
        return None, "embed_fail"
    try: AllChem.MMFFOptimizeMolecule(m, maxIters=500)
    except Exception: pass
    return m, "ok"

def engine_available():
    import shutil
    for b in ("smina", "vina", "qvina2", "gnina"):
        if shutil.which(b): return b
    return None

def main():
    LIGDIR.mkdir(parents=True, exist_ok=True)
    lab = {t: {r["id"]: r for r in json.load(open(ROOT / f"results/knowledge_liability_{t}.json"))["flags"]}
           for t in ("avb6", "pdl1")}
    ftod = json.load(open(ROOT / "results/fto_novelty_kset.json"))
    cands = {"avb6": json.load(open(ROOT/"results/knowledge_grounded_candidates_v1.json"))["avb6"]["candidates"],
             "pdl1": json.load(open(ROOT/"results/knowledge_grounded_pdl1_v1.json"))["candidates"]}
    fto_by_id = {v["candidate_id"]: v for t in ("avb6","pdl1") for v in ftod[t]}

    manifest = {"engine_available": engine_available(), "status": "prepared_not_scored",
                "targets": TARGETS, "shortlist": {}, "ligand_dir": str(LIGDIR.relative_to(ROOT)),
                "scoring_route": ["CANONICAL (trusted, matches round-1 panels): cofold each sequence into the receptor "
                                  "(BoltzGen/Boltz-2 on 9xmm/5O45) -> COMPLEX -> MM-GBSA rescore (peptide_mmgbsa_run.sh, "
                                  "OpenMM/GBn2/CHARMM36m, EC2 GPU spot) -> rank on the same ΔG scale as pdl1/avb6 round-1",
                                  "Vina docking is only a cheap pre-MM-GBSA pose-source; the program trusts MM-GBSA >> docking"],
                "ncAA_caveat": "ligand SDFs are L-backbone; production scoring must use full-HELM stereochem (D-Pro/N-methyl).",
                "mmgbsa_needs_complex": "MM-GBSA requires a bound receptor+peptide COMPLEX (pose). K-sets are sequence-only -> "
                                        "a pose-generation stage (cofold/dock) MUST precede MM-GBSA."}
    for t in ("avb6", "pdl1"):
        rows = []
        for c in cands[t]:
            cid = c["id"]; seq = "".join(ch for ch in _backbone(c["helm"]))
            decision, notes = decide(t, lab[t][cid], fto_by_id.get(cid))
            rec = {"id": cid, "backbone": seq, "decision": decision, "notes": notes, "ligand_sdf": None}
            if decision in ("DOCK", "DOCK_AFTER_FIX"):
                m, status = embed(seq, cyclic=not c["helm"].lower().startswith("c-f"))
                if m is not None:
                    path = LIGDIR / f"{cid}.sdf"
                    w = Chem.SDWriter(str(path)); w.write(m); w.close()
                    rec["ligand_sdf"] = str(path.relative_to(ROOT)); rec["embed"] = "ok"
                else:
                    rec["embed"] = status
            rows.append(rec)
        manifest["shortlist"][t] = rows
        nd = sum(1 for r in rows if r["decision"]=="DOCK"); naf = sum(1 for r in rows if r["decision"]=="DOCK_AFTER_FIX")
        ndr = sum(1 for r in rows if r["decision"]=="DROP")
        print(f"{t}: DOCK={nd}  DOCK_AFTER_FIX={naf}  DROP={ndr}")
        for r in rows:
            print(f"  {r['decision']:15s} {r['id']:11s} {r['backbone']:20s} embed={r.get('embed','-')}  {'; '.join(r['notes'])[:90]}")
    (OUT/"manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"\nengine_available={manifest['engine_available']}  status={manifest['status']}")
    print(f"wrote {OUT/'manifest.json'} + {len(list(LIGDIR.glob('*.sdf')))} ligand SDFs")

def _backbone(helm):
    from cyclic_llm.knowledge_liability_flags import parse_helm
    res, _, _ = parse_helm(helm); return "".join(res)

if __name__ == "__main__":
    main()
