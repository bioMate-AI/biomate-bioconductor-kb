"""Library QC, bound-conformation priors with leave-one-target-out (LOTO) stability, and exports (workstream K3). Runs on EC2.

usage: python aggregate.py --features features.jsonl --meta meta.jsonl --out OUTDIR [--exclude-targets FILE]

Target = the receptor's UniProt accession set (RCSB reference sequence identifiers of the receptor chains). Entries whose
receptor chains carry no UniProt accession get target `NOUNIPROT:<pdb_id>` (each its own target, i.e. the LOTO stays conservative).
A prior is tagged with n_complexes, n_targets and a sha256 of the sorted target list it was computed from, so any prior can be
recomputed with a given target set excluded (arm G / held-out targets): build_priors(rows, exclude_targets=...).
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
import os
import sys
from typing import Dict, List

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rcsb_meta as M  # noqa: E402

STD1 = "ACDEFGHIKLMNPQRSTVWY"
# pre-registered stability thresholds for a prior to be exported with a non-zero default weight
STABLE = {"min_targets": 20, "median_tvd": 0.05, "max_tvd": 0.25}


def load(features_path: str, meta_path: str) -> List[Dict]:
    meta = {}
    for l in open(meta_path):
        d = json.loads(l); meta[d["rcsb_id"].upper()] = d
    rows = []
    for l in open(features_path):
        d = json.loads(l)
        if not d.get("ok"):
            continue
        m = meta.get(d["pdb_id"].upper(), {})
        cu = M.chain_uniprot(m) if m else {}
        accs = sorted({a for ch in d.get("rec_chains", []) for a in cu.get(ch, [])})
        d["receptor_uniprot"] = accs
        d["target_key"] = "+".join(accs) if accs else f"NOUNIPROT:{d['pdb_id']}"
        cit = (m.get("rcsb_primary_citation") or {})
        d["doi"] = cit.get("pdbx_database_id_DOI"); d["pubmed"] = cit.get("pdbx_database_id_PubMed")
        d["cit_title"] = cit.get("title"); d["cit_year"] = cit.get("year")
        d["title"] = (m.get("struct") or {}).get("title")
        rc = (m.get("rcsb_entry_info") or {}).get("resolution_combined")
        d["resolution_rcsb"] = rc[0] if rc else None
        d["affinity"] = [dict(x, source="RCSB") for x in (m.get("rcsb_binding_affinity") or [])]
        ba = d.get("biolip_affinity") or {}
        for k, vals in ba.items():
            for v in vals:
                d["affinity"].append({"source": "BioLiP2:" + k, "raw": v})
        rows.append(d)
    return rows


def qc_flags(d: Dict) -> List[str]:
    f = []
    if d["n_covalent_to_receptor"] > 0:
        f.append("covalent_to_receptor")
    if not (5 <= d["n_res"] <= 30):
        f.append("length_outside_5_30")
    if d["primary_cyclisation"] == "none":
        f.append("no_closure_redetected")
    elif d["ring_residues"] < 4:
        f.append("ring_lt4")
    if d.get("cyclization_type") and d["primary_cyclisation"] != "none" and not d.get("agree_cyclisation", True):
        f.append("manifest_label_disagrees")
    if d["n_iface_res"] == 0:
        f.append("no_interface")
    return f


def library(rows: List[Dict]) -> List[Dict]:
    """QC + dedupe: drop covalent/short/long/no-closure/no-interface entries; keep the best-resolution entry per (target, sequence)."""
    keep = {}
    for d in rows:
        d["qc"] = qc_flags(d)
        hard = [x for x in d["qc"] if x != "manifest_label_disagrees"]
        if hard:
            continue
        key = (d["target_key"], d["seq"], d["primary_cyclisation"])
        res = d["resolution_rcsb"] if d["resolution_rcsb"] is not None else (d.get("resolution") or 99.0)
        if key not in keep or res < keep[key][0]:
            keep[key] = (res, d)
    return [v[1] for v in keep.values()]


def _hash_targets(ts) -> str:
    return hashlib.sha256("\n".join(sorted(ts)).encode()).hexdigest()[:16]


def _tvd(p: Dict, q: Dict) -> float:
    ks = set(p) | set(q)
    return 0.5 * sum(abs(p.get(k, 0.0) - q.get(k, 0.0)) for k in ks)


def _norm(c: collections.Counter, smooth: float = 0.0, support=None) -> Dict:
    keys = list(support) if support is not None else list(c)
    tot = sum(c.get(k, 0) for k in keys) + smooth * len(keys)
    return {k: (c.get(k, 0) + smooth) / tot for k in keys} if tot > 0 else {}


# ---- statistics (each returns a dict of categorical probabilities or {'rate': x}) ----
def stat_ring(rows, cls):
    c = collections.Counter(min(max(r["ring_residues"], 4), 30) for r in rows if r["primary_cyclisation"] == cls)
    return _norm(c, 0.0, range(4, 31)), sum(c.values())


def stat_turn_presence(rows, cls):
    sel = [r for r in rows if r["primary_cyclisation"] == cls]
    c = collections.Counter()
    for r in sel:
        for t in {t["type"] for t in r["beta_turns"]}:
            c[t] += 1
    return {k: c.get(k, 0) / len(sel) for k in ("I", "I'", "II", "II'")} if sel else {}, len(sel)


def stat_position_rates(rows, cls=None):
    """Rates of D residues / N-methyl / cis amide at interface vs non-interface positions."""
    nd_i = nd_o = nm_i = nm_o = ni = no = 0
    for r in rows:
        if cls and r["primary_cyclisation"] != cls:
            continue
        ifs = set(r["iface_res"])
        for i in range(r["n_res"]):
            if i in ifs:
                ni += 1; nd_i += r["is_d"][i]; nm_i += r["is_nme"][i]
            else:
                no += 1; nd_o += r["is_d"][i]; nm_o += r["is_nme"][i]
    out = {"d_rate_interface": nd_i / ni if ni else None, "d_rate_other": nd_o / no if no else None,
           "nme_rate_interface": nm_i / ni if ni else None, "nme_rate_other": nm_o / no if no else None}
    return out, ni + no


def stat_residue_enrichment(rows, cls=None):
    ci, co = collections.Counter(), collections.Counter()
    for r in rows:
        if cls and r["primary_cyclisation"] != cls:
            continue
        ifs = set(r["iface_res"])
        for i, a in enumerate(r["seq"]):
            if a in STD1:
                (ci if i in ifs else co)[a] += 1
    ti, to = sum(ci.values()) + 20, sum(co.values()) + 20
    return {a: math.log2(((ci.get(a, 0) + 1) / ti) / ((co.get(a, 0) + 1) / to)) for a in STD1}, ti + to - 40


def stat_nh(rows, cls=None):
    n = intra = rec = free = 0
    for r in rows:
        if cls and r["primary_cyclisation"] != cls:
            continue
        n += r["n_backbone_nh"]; intra += r["n_nh_intra_hbond"]; rec += r["n_nh_receptor_hbond"]; free += r["n_nh_free"]
    return ({"nh_intra": intra / n, "nh_receptor": rec / n, "nh_free": free / n} if n else {}), n


STATS = {
    "ring_residues": (stat_ring, "categorical", ["disulfide", "head_to_tail", "amide_like", "thioether"]),
    "beta_turn_presence": (stat_turn_presence, "rates", ["disulfide", "head_to_tail", "amide_like", "thioether"]),
    "position_rates": (stat_position_rates, "rates", [None, "disulfide", "head_to_tail"]),
    "residue_enrichment": (stat_residue_enrichment, "rates", [None, "disulfide", "head_to_tail"]),
    "nh_fate": (stat_nh, "rates", [None, "disulfide", "head_to_tail"]),
}


def _deviation(full: Dict, loto: Dict, kind: str) -> float:
    if kind == "categorical":
        return _tvd(full, loto)
    ks = [k for k in full if full[k] is not None and loto.get(k) is not None]
    return max((abs(full[k] - loto[k]) for k in ks), default=0.0)


def build_priors(rows: List[Dict], exclude_targets=frozenset(), do_loto: bool = True) -> Dict:
    rows = [r for r in rows if r["target_key"] not in exclude_targets]
    targets = sorted({r["target_key"] for r in rows})
    out = {"n_complexes": len(rows), "n_targets": len(targets), "targets_sha256": _hash_targets(targets),
           "excluded_targets_sha256": _hash_targets(exclude_targets) if exclude_targets else None, "priors": {}}
    by_t = collections.defaultdict(list)
    for r in rows:
        by_t[r["target_key"]].append(r)
    for name, (fn, kind, classes) in STATS.items():
        for cls in classes:
            val, n = fn(rows, cls) if name not in ("position_rates", "residue_enrichment", "nh_fate") else fn(rows, cls)
            if not val or n == 0:
                continue
            key = f"{name}|{cls or 'all'}"
            entry = {"stat": name, "class": cls or "all", "kind": kind, "value": val, "n": n}
            if do_loto and len(targets) >= 3:
                devs, flips = [], 0
                for t in targets:
                    sub = [r for tt in targets if tt != t for r in by_t[tt]]
                    v2, n2 = fn(sub, cls)
                    if not v2:
                        continue
                    devs.append(_deviation(val, v2, kind))
                    if kind == "categorical" and max(val, key=val.get) != max(v2, key=v2.get):
                        flips += 1
                if devs:
                    entry["loto"] = {"n_targets": len(targets), "median_dev": round(float(np.median(devs)), 4),
                                     "p95_dev": round(float(np.percentile(devs, 95)), 4), "max_dev": round(float(np.max(devs)), 4),
                                     "argmax_flips": flips}
                    entry["stable"] = bool(len(targets) >= STABLE["min_targets"] and entry["loto"]["median_dev"] <= STABLE["median_tvd"]
                                           and entry["loto"]["max_dev"] <= STABLE["max_tvd"]) if kind == "categorical" else \
                        bool(len(targets) >= STABLE["min_targets"] and entry["loto"]["max_dev"] <= STABLE["max_tvd"])
            out["priors"][key] = entry
    return out


def snippets(priors: Dict) -> List[Dict]:
    """Plain-text retrieval snippets with provenance counts (each derived from the numbers in priors)."""
    sn = []
    P = priors["priors"]
    tag = f"n={priors['n_complexes']} complexes, {priors['n_targets']} targets (set {priors['targets_sha256']})"
    for cls in ("disulfide", "head_to_tail", "amide_like", "thioether"):
        e = P.get(f"ring_residues|{cls}")
        if e:
            v = e["value"]; tot = e["n"]
            cdf = np.cumsum([v[k] for k in sorted(v)])
            q = lambda p: sorted(v)[int(np.searchsorted(cdf, p))]
            sn.append({"id": f"STR-RING-{cls}", "text": f"Experimentally determined target-bound cyclic peptides closed by {cls.replace('_', ' ')}: "
                       f"ring spans {q(0.25)}-{q(0.75)} residues (IQR), median {q(0.5)} (n={tot} complexes).", "provenance": tag, "stable": e.get("stable")})
    e = P.get("position_rates|all")
    if e:
        v = e["value"]
        sn.append({"id": "STR-POSRATES", "text": "At peptide positions in contact with the target, D-residue rate "
                   f"{v['d_rate_interface']:.3f} vs {v['d_rate_other']:.3f} elsewhere; N-methyl rate {v['nme_rate_interface']:.3f} vs "
                   f"{v['nme_rate_other']:.3f} elsewhere (n={e['n']} positions).", "provenance": tag, "stable": e.get("stable")})
    e = P.get("nh_fate|all")
    if e:
        v = e["value"]
        sn.append({"id": "STR-NH", "text": f"Backbone amide NH groups in bound cyclic peptides: {v['nh_intra']:.2f} intramolecularly H-bonded, "
                   f"{v['nh_receptor']:.2f} H-bonded to the receptor only, {v['nh_free']:.2f} free (n={e['n']} NH groups).", "provenance": tag, "stable": e.get("stable")})
    e = P.get("residue_enrichment|all")
    if e:
        top = sorted(e["value"].items(), key=lambda kv: -kv[1])[:5]; bot = sorted(e["value"].items(), key=lambda kv: kv[1])[:5]
        sn.append({"id": "STR-RESENRICH", "text": "Residues enriched at the interface (log2 odds interface vs other positions): "
                   + ", ".join(f"{a} {x:+.2f}" for a, x in top) + "; depleted: " + ", ".join(f"{a} {x:+.2f}" for a, x in bot) + f" (n={e['n']} positions).",
                   "provenance": tag, "stable": e.get("stable")})
    return sn


def potentials(priors: Dict) -> List[Dict]:
    """Sequence-level potentials (log-probability tables) for the K loader / U1 soft rules. Default weight is 0 unless the prior is stable."""
    pot = []
    for key, e in priors["priors"].items():
        if e["stat"] == "ring_residues":
            tab = {str(k): math.log(max(v, 1e-4)) for k, v in e["value"].items()}
            pot.append({"id": f"POT-{key}", "feature": "ring_residues", "applies_to": f"closure={e['class']}", "log_prob": tab,
                        "n": e["n"], "default_weight": 0.5 if e.get("stable") else 0.0, "stable": bool(e.get("stable")), "loto": e.get("loto"),
                        "targets_sha256": priors["targets_sha256"]})
        elif e["stat"] == "position_rates" and e["class"] == "all":
            v = e["value"]
            pot.append({"id": "POT-posrates", "feature": "interface_position_rates", "value": v, "n": e["n"], "default_weight": 0.0,
                        "stable": bool(e.get("stable")), "loto": e.get("loto"), "targets_sha256": priors["targets_sha256"],
                        "note": "interface-position labels need a target; informational for retrieval, not a decoder potential"})
    return pot


def summary(rows_all: List[Dict], lib: List[Dict]) -> Dict:
    c = collections.Counter
    return {"n_rows_ok": len(rows_all), "qc_flag_counts": dict(c(f for r in rows_all for f in r["qc"])),
            "n_library": len(lib), "n_targets": len({r["target_key"] for r in lib}),
            "by_primary_cyclisation": dict(c(r["primary_cyclisation"] for r in lib)),
            "by_method": dict(c(r["method"] for r in lib)),
            "n_with_ncaa": sum(1 for r in lib if r["nonstd_resnames"]), "n_with_D": sum(1 for r in lib if r["n_d"] > 0),
            "n_with_nme": sum(1 for r in lib if r["n_nme"] > 0), "n_with_cis_amide": sum(1 for r in lib if r["n_cis_amide"] > 0),
            "n_with_affinity": sum(1 for r in lib if r["affinity"]), "n_with_doi": sum(1 for r in lib if r["doi"]),
            "manifest_vs_redetected_disagree": sum(1 for r in rows_all if "manifest_label_disagrees" in r["qc"]),
            "median_resolution": float(np.median([r["resolution_rcsb"] for r in lib if r["resolution_rcsb"]])) if any(r["resolution_rcsb"] for r in lib) else None}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--features", required=True); ap.add_argument("--meta", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--exclude-targets", default=None)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    rows_all = load(a.features, a.meta)
    lib = library(rows_all)
    toks = {l.strip() for l in open(a.exclude_targets) if l.strip()} if a.exclude_targets else set()
    # a token excludes every target whose key equals it or whose accession set contains it (e.g. a UniProt accession of a held-out arm-G target)
    ex = frozenset(k for k in {r["target_key"] for r in lib} if k in toks or (set(k.split("+")) & toks))
    pri = build_priors(lib, ex)
    if ex:
        json.dump(sorted(ex), open(os.path.join(a.out, "priors_excluded_targets.json"), "w"))
    json.dump(summary(rows_all, lib), open(os.path.join(a.out, "library_summary.json"), "w"), indent=1)
    json.dump(pri, open(os.path.join(a.out, "priors_v1.json"), "w"), indent=1)
    with open(os.path.join(a.out, "library_v1.jsonl"), "w") as f:
        for r in lib:
            slim = {k: r[k] for k in ("pdb_id", "pep_chain", "rec_chains", "seq", "target_key", "receptor_uniprot", "primary_cyclisation", "ring_residues",
                                      "resolution_rcsb", "method", "doi", "pubmed", "title", "cit_year", "n_d", "n_nme", "n_cis_amide", "nonstd_resnames",
                                      "n_iface_res", "contacts_total", "hbond_rec_total", "salt_total", "hydrophobic_total", "metal_contacts",
                                      "buried_sasa_total", "buried_sasa_polar", "buried_sasa_apolar", "n_backbone_nh", "n_nh_intra_hbond",
                                      "n_nh_receptor_hbond", "n_nh_free", "hotspots", "affinity", "qc")}
            slim["beta_turns"] = [t["type"] + ":" + t["res"] for t in r["beta_turns"]]
            f.write(json.dumps(slim) + "\n")
    with open(os.path.join(a.out, "retrieval_snippets_v1.jsonl"), "w") as f:
        for s in snippets(pri):
            f.write(json.dumps(s) + "\n")
    json.dump(potentials(pri), open(os.path.join(a.out, "soft_potentials_v1.json"), "w"), indent=1)
    json.dump(sorted({r["target_key"] for r in lib}), open(os.path.join(a.out, "priors_targets.json"), "w"))
    print(json.dumps(summary(rows_all, lib)))


if __name__ == "__main__":
    main()
