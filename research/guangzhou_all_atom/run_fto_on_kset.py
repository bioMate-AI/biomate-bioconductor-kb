"""FTO/novelty gate on the knowledge-grounded K-sets (αvβ6 + PD-L1).

Reuses drug_novelty_fto.py. αvβ6 gets the decisive SEQUENCE axis vs the known cyclic-RGDL genus
(Trivehexin, avebehexin) + A20FMDV2 — the chemotype the review flags as the real FTO squeeze. PD-L1 runs
the STRUCTURE axis only (no confident public WL12/dmp10/BMS sequences to recite -> sequence axis deferred
to step 3, pull from primary refs; reciting from memory would be fabrication).
"""
import json, time
from dataclasses import asdict
from pathlib import Path
import drug_novelty_fto as nf
from cyclic_llm.knowledge_liability_flags import parse_helm

ROOT = Path(__file__).resolve().parent
LIB_CSV = ROOT / "data/raw/binding_affinity/binding_affinity_v1.csv"
CACHE = ROOT / "data/_registry_cache/novelty_lib_binding_affinity_v1.pkl"

# Known αvβ6 cyclic-RGDL genus (backbones, L one-letter). Cited in repo pharmacophore refs:
#   Trivehexin c[YRGDLAYp(NMe)K]; avebehexin cyclo(FRGDLAFp(NMe)K). A20FMDV2 = FMDV VP1 peptide.
AVB6_GENUS = {"Trivehexin": "YRGDLAYPK", "avebehexin": "FRGDLAFPK",
              "A20FMDV2": "NAVPNLRGDLQVLAQKVART"}

def backbone(helm):
    res, _, _ = parse_helm(helm)
    return "".join(res)

def load(path, key=None):
    d = json.loads(Path(path).read_text())
    blk = d[key] if key else d
    return blk["candidates"]

t0 = time.time()
lib = nf.build_library(str(LIB_CSV), smiles_col="smiles", id_col="id",
                       tag_cols=["is_pdl1", "is_avb6", "target_name", "cyclic_bool"], cache_path=str(CACHE))
print(f"library: {len(lib)} fingerprinted known actives ({time.time()-t0:.0f}s)\n")

out = {}
# ---- αvβ6: structure + sequence (genus) ----
print("=== αvβ6-K  (sequence axis vs Trivehexin/avebehexin/A20FMDV2 genus) ===")
avb6 = []
for c in load("results/knowledge_grounded_candidates_v1.json", key="avb6"):
    seq = backbone(c["helm"])
    v = nf.score_candidate(c["id"], seq=seq, modality="peptide", cyclic=True, library=lib,
                           ref_seqs=list(AVB6_GENUS.values()), restrict_tag=("is_avb6", "True"))
    d = asdict(v); d["backbone"] = seq
    # name the nearest genus member
    if v.max_seq_identity is not None:
        best = max(AVB6_GENUS.items(), key=lambda kv: nf.sequence_identity(seq, kv[1]))
        d["nearest_genus"] = {"name": best[0], "seq": best[1], "identity": round(nf.sequence_identity(seq, best[1]), 3)}
    avb6.append(d)
    ng = d.get("nearest_genus", {})
    print(f"  {c['id']:11s} {seq:20s} seqID={v.max_seq_identity}  structT={v.max_tanimoto}  "
          f"verdict={v.verdict:14s} nearGenus={ng.get('name')}({ng.get('identity')})")
out["avb6"] = avb6

# ---- PD-L1: structure axis only (sequence genus deferred) ----
print("\n=== PD-L1-K  (structure axis only; sequence genus deferred to primary-ref sourcing) ===")
pdl1 = []
for c in load("results/knowledge_grounded_pdl1_v1.json"):
    seq = backbone(c["helm"])
    v = nf.score_candidate(c["id"], seq=seq, modality="peptide", cyclic=not c["helm"].lower().startswith("c-f"),
                           library=lib, restrict_tag=("is_pdl1", "True"))
    d = asdict(v); d["backbone"] = seq
    pdl1.append(d)
    print(f"  {c['id']:11s} {seq:14s} structT={v.max_tanimoto}  verdict={v.verdict}  ({v.structure_status})")
out["pdl1"] = pdl1

out["meta"] = {"library_size": len(lib), "tanimoto_cutoff": nf.DEFAULT_TANIMOTO_CUTOFF,
               "seq_id_cutoff": nf.DEFAULT_SEQ_ID_CUTOFF, "avb6_genus": AVB6_GENUS,
               "notes": ["αvβ6 backbones are L one-letter (stereo/N-methyl stripped) — correct for re-discovery/FTO identity, NOT for activity (see activity-cliff doc).",
                         "PD-L1 sequence-axis FTO deferred: WL12/dmp10/BMS sequences must be pulled from primary refs, not recited from memory."]}
Path("results/fto_novelty_kset.json").write_text(json.dumps(out, indent=2))
print("\nwrote results/fto_novelty_kset.json")
