"""renal_corpus.py — RadioRenalKB: a PRODUCT — the structured, cross-class radioligand renal-biodistribution
knowledge base + interpretable features + a calibrated renal-retention surrogate + the Gate-A baseline.

This is a PRODUCT, not an αvβ6-only corpus: it spans every radiopeptide class (PSMA, SSTR, GRPR/bombesin,
FAPI, RGD/integrin αvβ3+αvβ6, …) and is reusable across every radioligand programme. Unlike medchem_kb
(assembled public rules → a capability, not a moat), RadioRenalKB is a genuinely PROPRIETARY asset: the raw
biodistribution facts are public, but no one has assembled them into a single structured, renal-protection-
flagged, de-duplicated dataset — "extraction is tedious literature work radiochemistry groups can't do at
scale" (programme doc). The compilation + the derived surrogate are the moat (trade-secret + database right),
defensibly "unique to us," though not patentable.

Premise (BMA-DEC-001 / programme doc): for αvβ6 RLT, affinity/selectivity/target-engagement are ALL MET; the
one open problem is DOSE — renal retention (every published αvβ6 radioligand is kidney dose-limited, T:K < 1).
Benchmark is PUBLIC + numeric: beat 0.66 Gy/GBq (Lu-177-Therahexin); target 0.3 (Pluvicto). The KB generalises
this to any radioligand programme: predict/rank renal retention from interpretable structure features.

This module is the SCAFFOLD:
  1. the schema the surrogate trains on (renal %ID/g timepoints, T:K, renal-protection flag, interpretable
     structure features — NOT learned embeddings; at this n, embeddings memorise);
  2. a SEED corpus of the constructs the programme docs cite, with their real renal numbers;
  3. the interpretable feature set + a net-charge extractor;
  4. Gate A: the surrogate must rank-order kidney retention better than NET CHARGE ALONE on held-out
     constructs — else the field heuristic is sufficient and there is no model. This is the gate to run
     BEFORE any synthesis spend.

The full corpus (300-800 constructs across PSMA/SSTR/GRPR/FAPI/RGD/bombesin) is the literature-extraction
task (BioMate-KB methodology) that follows; this fixes the schema + baseline so extraction has a target.
"""
from __future__ import annotations
import json, os
from dataclasses import dataclass, field, asdict
from typing import Optional

# ---- benchmark (public, numeric) ----
BENCHMARK_GY_PER_GBQ = {"therahexin_FIH": 0.66, "psma617_VISION_corrected": 0.42, "platform_target": 0.30}

# ---- interpretable feature set (programme doc §Featurisation) — NO learned embeddings ----
FEATURES = ["net_charge_pH74", "n_lys", "n_arg", "basic_residue_frac", "logD_pH74", "tpsa", "mol_weight",
            "chelator", "linker_class", "albumin_binder", "cleavable_motif", "radiometal"]


@dataclass
class RenalConstruct:
    """One radiopeptide with paired structure + renal biodistribution. Unknowns stay None (never imputed)."""
    construct_id: str
    target: str
    chemotype: str                      # cyclic_RGD | knottin | linear | ...
    # --- renal / tumour biodistribution (the labels) ---
    kidney_pid_g_1h: Optional[float] = None
    kidney_pid_g_4h: Optional[float] = None
    kidney_pid_g_24h: Optional[float] = None
    tumour_pid_g: Optional[float] = None
    tk_ratio: Optional[float] = None          # tumour:kidney (the dose-limiting number; want > 1)
    kidney_gy_per_gbq: Optional[float] = None  # human dosimetry when available
    # --- experimental context (critical: protection confound) ---
    species: Optional[str] = None
    radiometal: Optional[str] = None
    chelator: Optional[str] = None
    renal_protection: Optional[str] = None     # None=unknown, "none", "lysine_arginine", "succinylated_gelatin"
    # --- interpretable structure features ---
    net_charge_pH74: Optional[float] = None
    n_lys: Optional[int] = None
    n_arg: Optional[int] = None
    logD_pH74: Optional[float] = None
    albumin_binder: Optional[bool] = None
    cleavable_motif: Optional[bool] = None
    source: str = ""
    verified: str = "cited"                    # cited | primary | inferred

    def to_dict(self):
        return asdict(self)


# ---- SEED corpus: CROSS-CLASS radioligands (the product spans all radiopeptide classes, not αvβ6) ----
# Numbers included only where confident; the renal_protection flag is MANDATORY (mixing protected/unprotected
# silently corrupts the model — the single most common way such a dataset fails). This seed fixes the schema +
# class coverage; the real product is the 300-800-construct literature extraction (BioMate-KB methodology).
SEED = [
    # --- integrin αvβ6 (the lead programme) ---
    RenalConstruct("Lu177-Therahexin", "avb6", "cyclic_RGD", kidney_gy_per_gbq=0.66, species="human",
                   radiometal="177Lu", chelator="DOTA", renal_protection="succinylated_gelatin",
                   source="First-in-human breast, Notni/TRIMT genus", verified="primary"),
    RenalConstruct("Lu177-DOTA-5G", "avb6", "cyclic_RGD", tk_ratio=0.14, species="mouse", radiometal="177Lu",
                   chelator="DOTA", albumin_binder=False, renal_protection="none",
                   source="JNM 64:639 (T:K 0.08@1h, 0.14@72h)", verified="primary"),
    RenalConstruct("Lu177-DOTA-ABM-5G", "avb6", "cyclic_RGD", tk_ratio=0.60, tumour_pid_g=5.0, species="mouse",
                   radiometal="177Lu", chelator="DOTA", albumin_binder=True, renal_protection="none",
                   source="JNM 64:639 (albumin-binder; kidney dose-limiting 5.18 mSv/MBq)", verified="primary"),
    RenalConstruct("Lu177-A20FMDV2", "avb6", "linear", kidney_pid_g_4h=118.64, species="mouse", radiometal="177Lu",
                   renal_protection="none", source="PMC8876964 (renal injury + deaths at 37 MBq)", verified="primary"),
    RenalConstruct("Ga68-Trivehexin", "avb6", "cyclic_RGD", species="human", radiometal="68Ga", chelator="TRAP",
                   renal_protection="none", source="Front Nucl Med (IC50 0.047nM; high renal retention)", verified="primary"),
    # --- PSMA (the benchmark class) ---
    RenalConstruct("Lu177-PSMA-617", "PSMA", "urea_small_molecule", kidney_gy_per_gbq=0.42, species="human",
                   radiometal="177Lu", chelator="DOTA", renal_protection="none",
                   source="VISION; corrected erratum 2026 → 0.42 Gy/GBq (was 0.43)", verified="primary"),
    RenalConstruct("Lu177-PSMA-I&T", "PSMA", "urea_small_molecule", species="human", radiometal="177Lu",
                   chelator="DOTAGA", renal_protection="none",
                   source="Lu-177-PSMA-I&T dosimetry series (kidney a dose-limiting organ)", verified="cited"),
    # --- somatostatin / SSTR (amino-acid-protected — the protection confound exemplar) ---
    RenalConstruct("Lu177-DOTATATE", "SSTR2", "cyclic_octapeptide", species="human", radiometal="177Lu",
                   chelator="DOTA", renal_protection="lysine_arginine",
                   source="NETTER-1 (Strosberg, NEJM 2017); amino-acid renal protection standard-of-care", verified="primary"),
    RenalConstruct("Lu177-DOTATOC", "SSTR2", "cyclic_octapeptide", species="human", radiometal="177Lu",
                   chelator="DOTA", renal_protection="lysine_arginine",
                   source="DOTATOC PRRT dosimetry; amino-acid co-infusion", verified="cited"),
    # --- GRPR / bombesin ---
    RenalConstruct("Lu177-RM2", "GRPR", "bombesin_antagonist", species="human", radiometal="177Lu",
                   chelator="DOTA", renal_protection="none",
                   source="RM2 GRPR-antagonist dosimetry (prostate/breast)", verified="cited"),
    # --- FAPI (fast renal clearance — the low-retention end of the range) ---
    RenalConstruct("Lu177-FAPI-46", "FAP", "quinoline_small_molecule", species="human", radiometal="177Lu",
                   chelator="DOTA", renal_protection="none",
                   source="FAPI-46 dosimetry (rapid renal clearance; short tumour residence the limiter)", verified="cited"),
    RenalConstruct("Lu177-FAP-2286", "FAP", "cyclic_peptide", species="human", radiometal="177Lu",
                   chelator="DOTA", renal_protection="none",
                   source="FAP-2286 (LuMIERE) peptide-targeted FAP RLT", verified="cited"),
    # --- integrin αvβ3 (sibling RGD class) ---
    RenalConstruct("Lu177-DOTA-RGD", "avb3", "cyclic_RGD", species="mouse", radiometal="177Lu",
                   chelator="DOTA", renal_protection="none",
                   source="cyclic-RGD αvβ3 radioligand (renal + hepatobiliary clearance)", verified="cited"),
]


def net_charge_baseline_score(c: RenalConstruct) -> Optional[float]:
    """Gate-A baseline: the FIELD heuristic. Higher net positive charge -> more renal retention (worse T:K).
    Returns a retention proxy (higher = worse) from net charge alone; None if charge unknown."""
    if c.net_charge_pH74 is None:
        return None
    return float(c.net_charge_pH74)


def gate_a_protocol():
    return {"gate": "A — model validity",
            "test": ">=50 held-out published constructs never seen in training",
            "pass": "surrogate rank-orders kidney retention (Spearman on log kidney %ID/g 24h or T:K) "
                    "STRICTLY better than net_charge_baseline_score alone",
            "fail_action": "STOP — the field heuristic suffices; there is no model (do before synthesis spend)",
            "baseline": "net_charge_pH74 alone"}


def write_seed(path=None):
    path = path or os.path.join(os.path.dirname(os.path.abspath(__file__)), "renal_seed_corpus.jsonl")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for c in SEED:
            f.write(json.dumps(c.to_dict()) + "\n")
    return path


if __name__ == "__main__":
    import collections
    p = write_seed()
    with_renal = [c for c in SEED if c.tk_ratio is not None or c.kidney_gy_per_gbq is not None or c.kidney_pid_g_4h is not None]
    by_class = collections.Counter(c.target for c in SEED)
    by_prot = collections.Counter(c.renal_protection or "unknown" for c in SEED)
    print(f"RadioRenalKB (PRODUCT) — seed: {len(SEED)} constructs across {len(by_class)} target classes "
          f"({len(with_renal)} with renal numbers) -> {os.path.relpath(p)}")
    print(f"  classes: {dict(by_class)}")
    print(f"  renal_protection split (the confound): {dict(by_prot)}")
    print(f"  interpretable features ({len(FEATURES)}): {FEATURES}")
    print(f"  benchmark (Gy/GBq): beat {BENCHMARK_GY_PER_GBQ['therahexin_FIH']} (Therahexin), target {BENCHMARK_GY_PER_GBQ['platform_target']} (Pluvicto)")
    print("\nGate A (run BEFORE synthesis spend):")
    for k, v in gate_a_protocol().items():
        print(f"  {k}: {v}")
    print("\nPRODUCT status: proprietary cross-program compilation (unique-to-us; trade-secret + database right, "
          "NOT patentable). NEXT = extract the full 300-800-construct corpus (PSMA/SSTR/GRPR/FAPI/RGD/bombesin) "
          "via the BioMate-KB literature methodology; renal_protection flag mandatory (exclude, never impute).")
