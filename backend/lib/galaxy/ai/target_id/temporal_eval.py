#!/usr/bin/env python3
"""Score any target-id channel on the temporal (post-cut-off) gold built by ``temporal_gold``.

A channel is anything that yields ``{target_symbol: score}`` for a disease id:
  * a callable ``fn(disease_id, disease_name) -> {target: score}``
  * an object with ``.run({"disease_id": id, ...}) -> ChannelResult`` (OpenTargetsGeneticsChannel, LLM channel,
    TableChannel / client tables)
  * precomputed scores ``{disease_id: {target: score}}`` (e.g. a saved LLM run: no model call is made here)

Per (channel, subset in {novel, new_indication, all_post}, negative policy):
  per-disease AUROC and hit@k (mid-rank), macro-mean AUROC, micro hit@k, a pooled percentile AUROC, and a
  label-permutation null (positives re-drawn at random inside each disease's candidate set) giving a
  p-value and the 95th-percentile null bar.  A simple popularity baseline is scored identically and
  compared paired by disease.

Candidates per disease = positives (the subset's gold targets) + negatives.  Negatives = the disease universe
(union of every channel's targets + baseline) minus ALL post-cut-off gold targets of that disease, minus
targets with a pre-cut-off approved drug for that disease.  Policy ``unapproved`` also removes every target
that had any pre-cut-off approved drug in any indication (the harder, memorisation-resistant negatives).
Targets a channel does not score rank last (they count as misses, so coverage gaps are not hidden).

LEAKAGE WARNING: current Open Targets overall/known_drug/literature scores were computed after the approvals.
Use ``ot_leakage_safe_scores`` (genetic_association, somatic_mutation, affected_pathway, rna_expression,
animal_model only) for an Open Targets channel.  The literature baseline is a *current* popularity measure and
is reported as such.

Offline:  python -m galaxy.ai.target_id.temporal_eval --gold GOLD.json --scores NAME=scores.json [...]
Live OT :  python -m galaxy.ai.target_id.temporal_eval --gold GOLD.json --live-ot [--max-diseases 40]
LLM run :  produce scores.json = {disease_id: {SYMBOL: score}} with the LLM channel (separate, paid step),
           then pass --scores llm=scores.json
3.9-safe, stdlib only.
"""
import argparse
import json
import os
import random
import sys
import urllib.request
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Set, Tuple

LEAKY_DATATYPES = ("known_drug", "literature")
SAFE_DATATYPES = ("genetic_association", "somatic_mutation", "affected_pathway", "rna_expression", "animal_model")
OT_GQL = "https://api.platform.opentargets.org/api/v4/graphql"
SUBSETS = ("novel", "new_indication", "all_post")
POLICIES = ("all", "unapproved")
KS = (10, 20, 50, 100)


# ---------------------------------------------------------------------------------------------
# Metric primitives (pure)
# ---------------------------------------------------------------------------------------------
def midranks_ascending(values: Sequence[float]) -> List[float]:
    """1-based average ranks, ascending (ties share the mean rank)."""
    order = sorted(range(len(values)), key=lambda i: values[i])
    ranks = [0.0] * len(values)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
            j += 1
        r = (i + j) / 2.0 + 1.0
        for t in range(i, j + 1):
            ranks[order[t]] = r
        i = j + 1
    return ranks


def auroc_from_labels(scores: Sequence[float], labels: Sequence[int]) -> Optional[float]:
    npos = sum(labels)
    nneg = len(labels) - npos
    if npos == 0 or nneg == 0:
        return None
    rk = midranks_ascending(scores)
    s = sum(r for r, y in zip(rk, labels) if y)
    return (s - npos * (npos + 1) / 2.0) / (npos * nneg)


class DiseaseSet:
    """One disease's candidate set with precomputed ranks (fast permutation null)."""

    def __init__(self, disease_id: str, items: List[str], scores: List[float], pos: Set[str]):
        self.disease_id = disease_id
        self.items = items
        self.scores = scores
        self.labels = [1 if t in pos else 0 for t in items]
        self.npos = sum(self.labels)
        self.nneg = len(items) - self.npos
        self.asc = midranks_ascending(scores)                     # for AUROC
        n = len(scores)
        self.desc = [n + 1 - r for r in self.asc]                 # mid-rank from the top (1 = best)

    def usable(self) -> bool:
        return self.npos > 0 and self.nneg > 0

    def auroc(self, idx: Optional[Sequence[int]] = None) -> float:
        if idx is None:
            idx = [i for i, y in enumerate(self.labels) if y]
        return (sum(self.asc[i] for i in idx) - self.npos * (self.npos + 1) / 2.0) / (self.npos * self.nneg)

    def hits(self, k: int, idx: Optional[Sequence[int]] = None) -> int:
        if idx is None:
            idx = [i for i, y in enumerate(self.labels) if y]
        return sum(1 for i in idx if self.desc[i] <= k)


def evaluate_sets(sets: List[DiseaseSet], n_perm: int = 500, seed: int = 0, ks: Sequence[int] = KS) -> Dict[str, Any]:
    use = [d for d in sets if d.usable()]
    if not use:
        return {"n_diseases": 0, "n_pairs": 0, "note": "no disease with >=1 positive and >=1 negative"}
    per = []
    for d in use:
        per.append({"disease_id": d.disease_id, "n_pos": d.npos, "n_neg": d.nneg, "auroc": round(d.auroc(), 4),
                    "hit_at_k": {str(k): d.hits(k) for k in ks}})
    npos_total = sum(d.npos for d in use)
    macro = sum(p["auroc"] for p in per) / len(per)
    micro_hits = {str(k): sum(d.hits(k) for d in use) for k in ks}
    # pooled percentile AUROC: score -> within-disease percentile, then one AUROC over all candidates
    pooled_s, pooled_y = [], []
    for d in use:
        n = len(d.items)
        for i in range(n):
            pooled_s.append(d.asc[i] / n)
            pooled_y.append(d.labels[i])
    pooled = auroc_from_labels(pooled_s, pooled_y)
    rng = random.Random(seed)
    null_macro, null_hits = [], {str(k): [] for k in ks}
    for _ in range(n_perm):
        m = 0.0
        h = {str(k): 0 for k in ks}
        for d in use:
            idx = rng.sample(range(len(d.items)), d.npos)
            m += d.auroc(idx)
            for k in ks:
                h[str(k)] += d.hits(k, idx)
        null_macro.append(m / len(use))
        for k in ks:
            null_hits[str(k)].append(h[str(k)])
    null_macro.sort()
    p_macro = (1 + sum(1 for v in null_macro if v >= macro - 1e-12)) / (n_perm + 1)
    hit_stats = {}
    for k in ks:
        arr = sorted(null_hits[str(k)])
        obs = micro_hits[str(k)]
        hit_stats[str(k)] = {"hits": obs, "of": npos_total, "rate": round(obs / npos_total, 4),
                             "null_mean_rate": round(sum(arr) / len(arr) / npos_total, 4),
                             "null_p95_rate": round(arr[int(0.95 * (len(arr) - 1))] / npos_total, 4),
                             "perm_p": round((1 + sum(1 for v in arr if v >= obs)) / (n_perm + 1), 4)}
    return {"n_diseases": len(use), "n_pairs": npos_total,
            "macro_auroc": round(macro, 4), "pooled_percentile_auroc": round(pooled, 4) if pooled is not None else None,
            "null_macro_auroc_p95": round(null_macro[int(0.95 * (len(null_macro) - 1))], 4),
            "null_macro_auroc_mean": round(sum(null_macro) / len(null_macro), 4),
            "perm_p_macro_auroc": round(p_macro, 4), "n_perm": n_perm,
            "hit_at_k": hit_stats, "per_disease": per}


# ---------------------------------------------------------------------------------------------
# Gold + channels
# ---------------------------------------------------------------------------------------------
def load_gold(path: str) -> Dict[str, Any]:
    with open(path) as fh:
        return json.load(fh)


def _scores_for(channel: Any, disease_id: str, disease_name: Optional[str]) -> Dict[str, float]:
    if isinstance(channel, dict):
        raw = channel.get(disease_id) or {}
    elif hasattr(channel, "run"):
        cr = channel.run({"disease_id": disease_id, "disease": disease_name})
        raw = getattr(cr, "scores", None) or {}
    else:
        raw = channel(disease_id, disease_name) or {}
    return {str(k).upper(): float(v) for k, v in raw.items()}


def gold_subsets(gold: Dict[str, Any]) -> Dict[str, Dict[str, Set[str]]]:
    """{subset: {disease_id: {targets}}} with the all_post union."""
    out = {s: {} for s in SUBSETS}
    for p in gold["pairs"]:
        out[p["subset"]].setdefault(p["disease_id"], set()).add(p["target_symbol"].upper())
        out["all_post"].setdefault(p["disease_id"], set()).add(p["target_symbol"].upper())
    return out


def build_sets(gold: Dict[str, Any], channel_scores: Dict[str, Dict[str, float]], universe_extra: Iterable[str],
               disease_id: str, subset: str, policy: str, subsets: Dict[str, Dict[str, Set[str]]]) -> Optional[DiseaseSet]:
    pos = subsets[subset].get(disease_id)
    if not pos:
        return None
    post_all = subsets["all_post"].get(disease_id, set())
    pre_dis = {t.upper() for t in (gold.get("pre_cutoff_approved_targets_by_disease") or {}).get(disease_id, [])}
    pre_glob = {t.upper() for t in gold.get("pre_cutoff_approved_targets_global", [])} if policy == "unapproved" else set()
    universe = set(channel_scores) | set(universe_extra)
    negs = {t for t in universe if t not in post_all and t not in pre_dis and t not in pre_glob}
    items = sorted(pos | negs)
    floor = (min(channel_scores.values()) - 1.0) if channel_scores else 0.0
    sc = [channel_scores.get(t, floor) for t in items]
    return DiseaseSet(disease_id, items, sc, pos)


def run_eval(gold: Dict[str, Any], channels: Dict[str, Any], baseline: Optional[Any] = None, baseline_name: str = "popularity",
             n_perm: int = 500, seed: int = 0, min_pairs_per_disease: int = 1, max_diseases: Optional[int] = None) -> Dict[str, Any]:
    """channels / baseline: see module docstring. Returns a JSON-able report."""
    subsets = gold_subsets(gold)
    names = {p["disease_id"]: p.get("disease_name") for p in gold["pairs"]}
    diseases = sorted(subsets["all_post"], key=lambda d: (-len(subsets["all_post"][d]), d))
    diseases = [d for d in diseases if len(subsets["all_post"][d]) >= min_pairs_per_disease]
    if max_diseases:
        diseases = diseases[:max_diseases]
    allch = dict(channels)
    if baseline is not None:
        allch[baseline_name] = baseline
    scores: Dict[str, Dict[str, Dict[str, float]]] = {c: {} for c in allch}
    coverage: Dict[str, Dict[str, int]] = {c: {"diseases_scored": 0} for c in allch}
    for d in diseases:
        for c, ch in allch.items():
            try:
                s = _scores_for(ch, d, names.get(d))
            except Exception as e:  # a failing channel on one disease is a miss, not a crash
                s = {}
                coverage[c].setdefault("errors", 0)
                coverage[c]["errors"] += 1
            scores[c][d] = s
            if s:
                coverage[c]["diseases_scored"] += 1
    report: Dict[str, Any] = {
        "gold_cutoff": gold["meta"]["cutoff"], "gold_query_date": gold["meta"]["query_date"],
        "n_diseases_considered": len(diseases), "n_perm": n_perm, "coverage": coverage,
        "baseline": baseline_name if baseline is not None else None, "results": {}, "vs_baseline": {}}
    for subset in SUBSETS:
        for policy in POLICIES:
            key = "%s|%s" % (subset, policy)
            report["results"][key] = {}
            for c in allch:
                sets = []
                for d in diseases:
                    union_extra = set()
                    for c2 in allch:
                        union_extra |= set(scores[c2][d])
                    ds = build_sets(gold, scores[c][d], union_extra, d, subset, policy, subsets)
                    if ds is not None:
                        sets.append(ds)
                res = evaluate_sets(sets, n_perm=n_perm, seed=seed)
                covered = 0
                total = 0
                for ds in sets:
                    for t, y in zip(ds.items, ds.labels):
                        if y:
                            total += 1
                            covered += 1 if t in scores[c][ds.disease_id] else 0
                res["gold_scored_by_channel"] = "%d/%d" % (covered, total)
                report["results"][key][c] = res
            if baseline is not None:
                b = {p["disease_id"]: p["auroc"] for p in report["results"][key][baseline_name].get("per_disease", [])}
                for c in channels:
                    diff, wins, n = 0.0, 0, 0
                    for p in report["results"][key][c].get("per_disease", []):
                        if p["disease_id"] in b:
                            n += 1
                            diff += p["auroc"] - b[p["disease_id"]]
                            wins += 1 if p["auroc"] > b[p["disease_id"]] else 0
                    report["vs_baseline"].setdefault(key, {})[c] = {
                        "paired_diseases": n, "mean_auroc_diff": round(diff / n, 4) if n else None, "diseases_channel_wins": wins}
    return report


def format_report(rep: Dict[str, Any]) -> str:
    lines = ["cutoff %s  (gold queried %s)  diseases=%d  perm=%d" % (
        rep["gold_cutoff"], rep["gold_query_date"], rep["n_diseases_considered"], rep["n_perm"])]
    for key, per in rep["results"].items():
        lines.append("\n[%s]" % key)
        for c, r in per.items():
            if not r.get("n_diseases"):
                lines.append("  %-18s no usable disease" % c)
                continue
            h = r["hit_at_k"]
            lines.append("  %-18s n=%d/%d  macroAUROC=%.3f (null p95 %.3f, p=%.3f)  pooled=%.3f  hit@20=%d/%d (null %.2f)  hit@100=%.2f  scored=%s" % (
                c, r["n_pairs"], r["n_diseases"], r["macro_auroc"], r["null_macro_auroc_p95"], r["perm_p_macro_auroc"],
                r["pooled_percentile_auroc"] or float("nan"), h["20"]["hits"], h["20"]["of"], h["20"]["null_mean_rate"],
                h["100"]["rate"], r["gold_scored_by_channel"]))
    return "\n".join(lines)


# ---------------------------------------------------------------------------------------------
# Live Open Targets helpers (free API; leakage-safe scoring and a popularity baseline)
# ---------------------------------------------------------------------------------------------
_Q = ("query($id:String!,$i:Int!){disease(efoId:$id){associatedTargets(page:{index:$i,size:500}){count "
      "rows{target{approvedSymbol} score datatypeScores{id score}}}}}")


def _ot_rows(efo: str, max_pages: int = 4, cache_dir: str = "/tmp/targetid_temporal_cache") -> List[Dict[str, Any]]:
    os.makedirs(cache_dir, exist_ok=True)
    p = os.path.join(cache_dir, "ot_assoc_%s.json" % efo)
    if os.path.exists(p):
        with open(p) as fh:
            return json.load(fh)
    rows: List[Dict[str, Any]] = []
    for i in range(max_pages):
        body = json.dumps({"query": _Q, "variables": {"id": efo, "i": i}}).encode()
        req = urllib.request.Request(OT_GQL, data=body, headers={"Content-Type": "application/json"})
        d = json.loads(urllib.request.urlopen(req, timeout=60).read())
        a = ((d.get("data") or {}).get("disease") or {}).get("associatedTargets")
        if not a or not a["rows"]:
            break
        rows.extend(a["rows"])
        if len(rows) >= a["count"]:
            break
    with open(p, "w") as fh:
        json.dump(rows, fh)
    return rows


def harmonic_sum(vals: Iterable[float]) -> float:
    v = sorted((x for x in vals if x and x > 0), reverse=True)
    return sum(x / ((i + 1) ** 2) for i, x in enumerate(v))


def ot_leakage_safe_scores(efo: str) -> Dict[str, float]:
    out = {}
    for r in _ot_rows(efo):
        dt = {x["id"]: x["score"] for x in r["datatypeScores"]}
        s = harmonic_sum(dt.get(k, 0.0) for k in SAFE_DATATYPES)
        if s > 0:
            out[r["target"]["approvedSymbol"].upper()] = s
    return out


def ot_literature_popularity(efo: str) -> Dict[str, float]:
    """Current literature datatype score: a popularity baseline (note: includes post-approval papers)."""
    out = {}
    for r in _ot_rows(efo):
        dt = {x["id"]: x["score"] for x in r["datatypeScores"]}
        if dt.get("literature", 0) > 0:
            out[r["target"]["approvedSymbol"].upper()] = dt["literature"]
    return out


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gold", required=True)
    ap.add_argument("--scores", nargs="*", default=[], help="NAME=path.json  ({disease_id: {SYMBOL: score}})")
    ap.add_argument("--baseline-scores", default=None, help="path.json popularity scores (default with --live-ot: OT literature)")
    ap.add_argument("--live-ot", action="store_true", help="add leakage-safe Open Targets channel + literature baseline (free API)")
    ap.add_argument("--n-perm", type=int, default=500)
    ap.add_argument("--max-diseases", type=int, default=None)
    ap.add_argument("--out", default=None)
    a = ap.parse_args(argv)
    gold = load_gold(a.gold)
    channels: Dict[str, Any] = {}
    for spec in a.scores:
        name, path = spec.split("=", 1)
        with open(path) as fh:
            channels[name] = json.load(fh)
    baseline = None
    if a.baseline_scores:
        with open(a.baseline_scores) as fh:
            baseline = json.load(fh)
    if a.live_ot:
        channels["ot_genetics_safe"] = lambda d, n: ot_leakage_safe_scores(d)
        if baseline is None:
            baseline = lambda d, n: ot_literature_popularity(d)
    if not channels:
        ap.error("no channel: pass --scores NAME=path or --live-ot")
    rep = run_eval(gold, channels, baseline=baseline, baseline_name="popularity", n_perm=a.n_perm, max_diseases=a.max_diseases)
    print(format_report(rep))
    if a.out:
        with open(a.out, "w") as fh:
            json.dump(rep, fh, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
