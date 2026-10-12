"""Deterministic 'obvious-knowledge' liability + SAR flag layer — the gap before docking.

The validation stack already had: a pharmacophore PRESENCE gate (pharmacophore_knowledge.py), a LEARNED
stability predictor (generation_developability.json), Pareto/HVI selection (peptide_select.py), FTO
novelty (drug_novelty_fto.py), and mm-gbsa/docking artifacts. What it did NOT have is a HARD, rule-based
layer that encodes textbook medicinal-chemistry / radiopharmacy knowledge and directly FLAGS or re-ranks
candidates with ZERO compute — no model, no docking. These rules are exact, free, and catch things a
docking score never will (a CMC liability, an off-target-selectivity gap, a dose-limiting-organ charge
problem). Run this FIRST; it can disqualify a candidate before you spend a GPU-hour docking it.

Three rule families:
  (1) UNIVERSAL CMC/chemical liabilities (sequence-motif, cyclic-aware):
        deamidation  N-G (worst), N-S, N-H, N-A ; glutamine slower
        Asp isomerisation / acid cleavage  D-G (worst), D-S, D-P
        oxidation  Met (M), free/odd Cys, Trp(W) hotspot
        (N-terminal Gln->pyroGlu only for LINEAR / disulfide scaffolds — N/A for head-to-tail cyclic)
  (2) αvβ6 radioligand SAR (literature-grounded):
        SELECTIVITY: bare RGD engages ALL RGD integrins (αvβ3/αvβ5/αvβ8/α5β1). β6-selectivity needs the
          EXTENDED motif RGDL-x-x-[L/I] (A20FMDV2 / Trivehexin / avebehexin helix). RGD without it ->
          'pan-RGD, β6-selectivity unconfirmed' (off-target-integrin tox risk).
        RENAL DOSE: kidney is the dose-limiting organ for peptide RLT; cationic peptides are reabsorbed
          in the proximal tubule (megalin/cubilin). Net positive charge on the peptide RAISES kidney dose.
          Each extra Lys/Arg beyond the obligate RGD-Arg is a liability — NOT a 'clearance-tuning' feature.
        LOCK: D-Pro + N-methyl conformational lock expected (else RGD presented uncontrolled).
  (3) PD-L1 macrocycle SAR:
        AGGREGATION/solubility: the cleft-binding chemotype is amphipathic, but an excessively hydrophobic
          / aromatic-clustered face (high GRAVY, aromatic-fraction) flags aggregation + poor solubility.
        Met oxidation; disulfide-scaffold Cys must be EVEN (paired).

Honest scope: these flags are necessary-not-sufficient. PASS here does not mean 'binder' (docking still
decides); HOLD/WATCH here means 'do not spend docking on this until the liability is designed out'. All
rules cite the knowledge; none are learned.
"""
from __future__ import annotations
import argparse, json, re
from pathlib import Path

CATIONIC = set("RK")          # His ~ negligible at pH 7.4, left out deliberately
ANIONIC  = set("DE")
HYDROPHOBIC = set("AILMFWVYC")  # Kyte-Doolittle positive-ish set for a coarse GRAVY sign
AROMATIC = set("FWY")

# cyclic-aware 2-mer liability hotspots: motif -> (severity, mechanism)
DIPEPTIDE_LIABILITIES = {
    "NG": ("hard", "Asn-Gly deamidation hotspot (fastest)"),
    "NS": ("soft", "Asn-Ser deamidation"),
    "NH": ("soft", "Asn-His deamidation"),
    "NA": ("soft", "Asn-Ala deamidation (slower)"),
    "DG": ("hard", "Asp-Gly isomerisation -> isoAsp (fastest)"),
    "DS": ("soft", "Asp-Ser isomerisation"),
    "DP": ("soft", "Asp-Pro acid-labile cleavage"),
}


def parse_helm(helm: str):
    """Parse a cyclo(...)/disulfide HELM-ish string into ordered residues with modifications.
    Returns (residues, mods) where residues is a list of 1-letter AA, mods is a parallel list of dicts
    {d_stereo, n_methyl}. Also returns scaffold flags (cyclic, disulfide, n_cys)."""
    s = helm.strip()
    disulfide = "disulfide" in s.lower()
    cyclic = s.lower().startswith("cyclo(")
    # strip wrapper / annotation
    if cyclic:
        inner = s[s.index("(") + 1: s.rindex(")")]
    else:
        inner = s.split(" (")[0]            # drop "(disulfide C1-C9)" annotation
    toks = [t for t in inner.split("-") if t]
    residues, mods = [], []
    for t in toks:
        t = t.strip()
        d_stereo = n_methyl = False
        core = t
        if core.startswith("[") and core.endswith("]"):
            core = core[1:-1]
        if core.startswith("NMe"):
            n_methyl = True; core = core[3:]
        elif core.startswith("d") and len(core) >= 2 and core[1].isupper():
            d_stereo = True; core = core[1:]
        aa = core[:1].upper()
        if aa.isalpha():
            residues.append(aa)
            mods.append({"d_stereo": d_stereo, "n_methyl": n_methyl})
    return residues, mods, {"cyclic": cyclic, "disulfide": disulfide, "n_cys": residues.count("C")}


def _cyclic_dimers(residues, cyclic):
    seq = "".join(residues)
    pairs = [seq[i:i+2] for i in range(len(seq) - 1)]
    if cyclic and len(seq) >= 2:
        pairs.append(seq[-1] + seq[0])        # wrap-around
    return pairs


def flag_candidate(cand, target):
    """Return flags + a knowledge tier (PASS / WATCH / HOLD) for one candidate dict with a 'helm' field."""
    helm = cand.get("helm") or cand.get("sequence") or ""
    residues, mods, scaf = parse_helm(helm)
    seq = "".join(residues)
    flags = []  # each: {severity, code, detail}

    # ---- (1) universal CMC liabilities (cyclic-aware) ----
    for dp in _cyclic_dimers(residues, scaf["cyclic"]):
        if dp in DIPEPTIDE_LIABILITIES:
            sev, mech = DIPEPTIDE_LIABILITIES[dp]
            flags.append({"severity": sev, "code": f"cmc:{dp}", "detail": mech})
    if "M" in seq:
        flags.append({"severity": "soft", "code": "cmc:Met-ox", "detail": "methionine oxidation liability"})
    # free/odd cysteines (paired disulfide scaffold with even Cys is fine)
    if scaf["n_cys"] and scaf["n_cys"] % 2 == 1:
        flags.append({"severity": "hard", "code": "cmc:free-Cys", "detail": f"odd Cys count ({scaf['n_cys']}) -> unpaired thiol / scrambling"})

    net_charge = sum(1 for a in seq if a in CATIONIC) - sum(1 for a in seq if a in ANIONIC)

    # ---- (2) αvβ6 radioligand SAR ----
    if target == "avb6":
        wrapped = seq + seq[:6] if scaf["cyclic"] else seq
        has_rgd = "RGD" in wrapped
        # β6-selectivity element in the VALIDATED cyclic nonapeptide class = RGDL (Leu C-terminal to Asp):
        # Trivehexin RGDLAY, avebehexin RGDLAF are β6-selective WITHOUT the full RGDLxxL/I helix. So RGDL is
        # the selectivity gate; RGDLxxL/I (linear A20FMDV2 class) is a BONUS affinity feature, not required.
        has_rgdl = "RGDL" in wrapped
        extended_affinity = bool(re.search(r"RGDL[A-Z]{2}[LI]", wrapped)) or bool(re.search(r"RGDL[LI]", wrapped))
        if has_rgd and not has_rgdl:
            flags.append({"severity": "hard", "code": "sar:pan-RGD",
                          "detail": "RGD without the RGD-L selectivity element -> pan-integrin (αvβ3/αvβ5/αvβ8); β6-selectivity lost (off-target tox)"})
        if extended_affinity:
            flags.append({"severity": "note", "code": "sar:extended-affinity",
                          "detail": "carries RGDL-[L/I] extended high-affinity motif (A20FMDV2 class) — affinity BONUS beyond the Trivehexin/avebehexin baseline"})
        has_lock = any(m["d_stereo"] and residues[i] == "P" for i, m in enumerate(mods)) or any(m["n_methyl"] for m in mods)
        if not has_lock:
            flags.append({"severity": "hard", "code": "sar:no-lock", "detail": "no D-Pro / N-methyl conformational lock"})
        # renal dose: kidney is dose-limiting; extra cationic residues raise kidney uptake
        extra_cationic = sum(1 for a in seq if a in CATIONIC) - 1  # minus the obligate RGD-Arg
        if net_charge > 0:
            flags.append({"severity": "soft", "code": "sar:renal-charge",
                          "detail": f"net peptide charge +{net_charge} (extra cationic={max(extra_cationic,0)}); cationic peptides are reabsorbed in the proximal tubule -> HIGHER kidney dose (dose-limiting organ). Added Lys/Arg worsens, not 'tunes', renal clearance."})

    # ---- (3) PD-L1 macrocycle SAR ----
    if target == "pdl1":
        if not seq:
            return {"id": cand.get("id"), "helm": helm, "flags": [{"severity": "hard", "code": "parse", "detail": "unparseable"}], "tier": "HOLD"}
        hydro_frac = sum(1 for a in seq if a in HYDROPHOBIC) / len(seq)
        arom_frac = sum(1 for a in seq if a in AROMATIC) / len(seq)
        if hydro_frac > 0.6:
            flags.append({"severity": "soft", "code": "sar:aggregation",
                          "detail": f"hydrophobic fraction {hydro_frac:.2f} > 0.60 -> aggregation / poor solubility risk (amphipathic is wanted, all-hydrophobic is not)"})
        if arom_frac > 0.45:
            flags.append({"severity": "soft", "code": "sar:aromatic-stack",
                          "detail": f"aromatic fraction {arom_frac:.2f} > 0.45 -> π-stacking aggregation risk"})
        if scaf["disulfide"] and scaf["n_cys"] % 2 == 1:
            flags.append({"severity": "hard", "code": "sar:disulfide-unpaired", "detail": "disulfide scaffold with odd Cys"})

    hard = [f for f in flags if f["severity"] == "hard"]
    soft = [f for f in flags if f["severity"] == "soft"]
    tier = "HOLD" if hard else ("WATCH" if soft else "PASS")
    return {"id": cand.get("id"), "helm": helm, "seq": seq, "net_charge": net_charge,
            "n_hard": len(hard), "n_soft": len(soft), "flags": flags, "tier": tier}


def run_file(path, target):
    data = json.loads(Path(path).read_text())
    cands = data.get("candidates") or data.get("avb6", {}).get("candidates") or []
    out = [flag_candidate(c, target) for c in cands]
    order = {"PASS": 0, "WATCH": 1, "HOLD": 2}
    # within a tier, a candidate carrying an affinity/selectivity BONUS note sorts first
    bonus = lambda r: -sum(1 for f in r["flags"] if f["severity"] == "note")
    out.sort(key=lambda r: (order[r["tier"]], bonus(r), r["n_hard"], r["n_soft"]))
    return out


def main():
    ap = argparse.ArgumentParser(description="Deterministic obvious-knowledge liability + SAR flags (pre-docking).")
    ap.add_argument("--candidates", required=True)
    ap.add_argument("--target", required=True, choices=["avb6", "pdl1"])
    ap.add_argument("--out")
    a = ap.parse_args()
    rows = run_file(a.candidates, a.target)
    print(f"KNOWLEDGE LIABILITY/SAR FLAGS [{a.target}] — pre-docking, zero-compute\n")
    for r in rows:
        print(f"  {r['tier']:5s} {r['id']:11s} net{r['net_charge']:+d}  {r['seq']}")
        for f in r["flags"]:
            print(f"        [{f['severity']}] {f['code']}: {f['detail']}")
    npass = sum(1 for r in rows if r["tier"] == "PASS")
    print(f"\n  tiers: PASS={npass}  WATCH={sum(1 for r in rows if r['tier']=='WATCH')}  HOLD={sum(1 for r in rows if r['tier']=='HOLD')}")
    if a.out:
        Path(a.out).parent.mkdir(parents=True, exist_ok=True)
        Path(a.out).write_text(json.dumps({"target": a.target, "n": len(rows), "flags": rows}, indent=2))
        print(f"  wrote {a.out}")


if __name__ == "__main__":
    main()
