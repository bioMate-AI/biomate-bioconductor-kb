#!/usr/bin/env python3
"""NEED-SATISFACTION grader for the reverse-decomposition benchmark.

The scientist's query states a biomedical NEED, never a tool. The gold is NOT a single
tool-set; it is a list of capability UNITS, each carrying an ACCEPT-SET of capability-
equivalent catalog realizations (DESeq2 OR edgeR OR limma all satisfy "find DE genes").

A plan is graded on *did it meet the need*, crediting ANY valid realization:

  need_recall     = fraction of gold capability units satisfied by >=1 predicted node
  need_precision  = fraction of predicted nodes that map to some gold unit (penalizes junk)
  need_f1         = 0.65*need_recall + 0.35*need_precision  (recall-leaning blend, NOT a plain
                    harmonic mean: gold is a minimal core, so recall is weighted up — see code)
  structure       = parallel/sequential/mixed/single shape match (reuse _structure_of)
  aggregation     = if the need implies a rank/select/compare/integrate step, did the plan
                    include one (keyword OR fan-in node with >=2 deps)?  else 1.0

  reward = 0.55*need_f1 + need_recall*(0.25*structure + 0.20*aggregation)   (bounded [0,1];
                    structure/aggregation credit is GATED by need_recall, so a wrong-tool plan
                    with the right shape cannot score high)

This is NOT exact tool-ID node-F1 — that metric floored decomposition_real at 0.016 because
it punished valid alternatives. A node SATISFIES a unit when it names any accept-set member
(key-token recall >=0.5) OR the capability itself (label-token recall >=0.6).

Validate (no model, no network):
    python need_grader.py --selftest --dataset reverse_decomp_train.jsonl
      oracle_A (one member/unit)      -> ~1.0
      oracle_B (a DIFFERENT member)   -> ~1.0   (two different tool-sets BOTH correct)
      wrong   (unrelated tools)       -> low
      partial (half the units)        -> mid
"""
from __future__ import annotations
import json, os, re, argparse
from collections import defaultdict

_WORD = re.compile(r"[a-z0-9]+")

# tokens that carry no capability identity (path noise + generic verbs/nouns)
_STOP = {
    "toolshed", "g2", "bx", "psu", "edu", "repos", "galaxy", "galaxyp", "bioc", "bioconductor",
    "nf", "core", "the", "for", "with", "and", "of", "to", "a", "an", "from", "using", "use",
    "run", "perform", "do", "data", "dataset", "workflow", "pipeline", "tool", "tools", "step",
    "steps", "analysis", "analyze", "analyse", "result", "results", "output", "report", "my",
    "our", "this", "that", "on", "in", "by", "via", "then", "get", "compute", "calculate",
    "generate", "produce", "make", "build", "v1", "v2", "v3", "0", "1", "2", "3",
}


def toks(s):
    return {t for t in _WORD.findall(str(s).lower()) if t}


def canon(s):
    return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()


_VERSION = re.compile(r"^[0-9][0-9.+a-z_\-]*$")  # a version-looking trailing segment


def _member_key_tokens(member_id):
    """Distinctive tokens of a catalog member id (drop path/owner/version/stop noise).

    'toolshed.g2.bx.psu.edu/repos/galaxyp/peptide_to_gff/peptide_to_gff/1.0' -> {peptide, gff}
    'BIOC_DESEQ2' -> {deseq2} ; 'nf-core/differentialabundance' -> {differentialabundance}
    'bioconductor/comet' -> {comet} ; 'Haplotypecaller Simple' -> {haplotypecaller, simple}
    """
    s = str(member_id)
    if "toolshed" in s.lower():
        # informative segment of a toolshed id is the wrapper name (2nd-to-last, last is version)
        parts = [p for p in s.split("/") if p]
        seg = parts[-2] if len(parts) >= 2 else parts[-1]
        return toks(seg) - _STOP
    # non-toolshed: union all path segments, drop a trailing version segment, then strip stop/path
    segs = [p for p in s.split("/") if p]
    if len(segs) >= 2 and _VERSION.match(segs[-1]):
        segs = segs[:-1]
    bag = set()
    for seg in segs:
        bag |= toks(seg)
    return bag - _STOP


def _unit_match_tokens(unit):
    """Per-unit: list of distinctive token-sets (one per accept member) + the capability label set."""
    member_sets = []
    for m in unit.get("accept_set", []):
        d = _member_key_tokens(m)
        if d:
            member_sets.append(d)
    label = toks(str(unit.get("capability", "")).replace("_", " ")) - _STOP
    return member_sets, label


def _node_satisfies_unit(pred_toks, member_sets, label, mem_thresh=0.5, lab_thresh=0.6):
    """pred node satisfies the unit if it names any accept member (key-token recall) OR
    the capability itself (label-token recall)."""
    for d in member_sets:
        if d and len(d & pred_toks) / len(d) >= mem_thresh:
            return True
    if label and len(label & pred_toks) / len(label) >= lab_thresh:
        return True
    return False


def _structure_of(plan):
    deps = [len(s.get("depends_on", []) or []) for s in plan if isinstance(s, dict)]
    if not deps:
        return "empty"
    if len(deps) == 1:
        return "single"
    if all(d == 0 for d in deps):
        return "parallel"
    if all(d > 0 for d in deps[1:]):
        return "sequential"
    return "mixed"


def _gold_structure(gold_units):
    return _structure_of([{"depends_on": u.get("depends_on", [])} for u in gold_units])


_AGG_KW = {"rank", "ranked", "ranking", "select", "selection", "best", "top", "prioritize",
           "prioritise", "compare", "comparison", "consensus", "integrate", "integration",
           "combine", "merge", "aggregate", "summarize", "summarise", "shortlist", "choose",
           "overlap", "intersect"}


def _has_aggregation(plan):
    for s in plan:
        if not isinstance(s, dict):
            continue
        if len(s.get("depends_on", []) or []) >= 2:   # fan-in
            return True
        if toks(s.get("sub_task", "")) & _AGG_KW:
            return True
    return False


def grade(pred, gold_units, aggregation="none", weights=None, detail=False):
    """Score one plan against the need (gold_units + aggregation intent)."""
    w = {"need": 0.55, "struct": 0.25, "agg": 0.20}
    if weights:
        w.update(weights)
    if isinstance(pred, str):
        pred = _parse_plan(pred)
    if not isinstance(pred, list):
        pred = []

    pred_tok_list = [toks(p.get("sub_task", "")) for p in pred if isinstance(p, dict)]
    unit_tokmaps = [_unit_match_tokens(u) for u in gold_units]

    # recall: each gold unit satisfied by >=1 pred node
    satisfied = 0
    for (msets, label) in unit_tokmaps:
        if any(_node_satisfies_unit(pt, msets, label) for pt in pred_tok_list):
            satisfied += 1
    need_recall = satisfied / len(gold_units) if gold_units else 0.0

    # precision: each pred node maps to some gold unit
    mapped = 0
    for pt in pred_tok_list:
        if any(_node_satisfies_unit(pt, msets, label) for (msets, label) in unit_tokmaps):
            mapped += 1
    need_prec = mapped / len(pred_tok_list) if pred_tok_list else 0.0
    # gold is a MINIMAL CORE: a natural need query may legitimately imply a superset of steps,
    # so we lean on recall (did the plan cover the core need?) while precision still punishes
    # pure junk (nodes that map to no gold unit at all). Recall-leaning blend, not plain F1.
    need_f1 = 0.65 * need_recall + 0.35 * need_prec

    struct = 1.0 if _structure_of(pred) == _gold_structure(gold_units) else 0.0
    if aggregation and aggregation != "none":
        agg = 1.0 if _has_aggregation(pred) else 0.0
    else:
        agg = 1.0

    # need-satisfaction is the gate: structure/aggregation credit is only meaningful once the
    # right capabilities are present, so scale them by need_recall. A wrong-tool plan with the
    # right shape must NOT score high (that was the decomposition_real failure in reverse).
    reward = w["need"] * need_f1 + need_recall * (w["struct"] * struct + w["agg"] * agg)
    reward = max(0.0, min(1.0, reward))
    if detail:
        return {"reward": round(reward, 4), "need_f1": round(need_f1, 4),
                "need_recall": round(need_recall, 4), "need_precision": round(need_prec, 4),
                "structure": struct, "aggregation": agg,
                "pred_structure": _structure_of(pred), "gold_structure": _gold_structure(gold_units),
                "units_satisfied": satisfied, "units_total": len(gold_units)}
    return round(reward, 4)


def _parse_plan(txt):
    m = re.search(r"\[.*\]", txt or "", re.S)
    if not m:
        return []
    try:
        p = json.loads(m.group())
        return p if isinstance(p, list) else []
    except Exception:
        return []


# ----------------------------------------------------------------------------------------
# selftest: oracle (any valid realization) ~1.0 ; wrong tool-set low ; TWO different sets both pass
# ----------------------------------------------------------------------------------------
def _plan_from_members(gold_units, pick):
    """Build a plan naming the pick()-th accept member of each unit, preserving structure."""
    plan = []
    for u in gold_units:
        acc = u.get("accept_set", [])
        name = acc[pick(len(acc))] if acc else u.get("capability", "step")
        plan.append({"sub_task": name, "order": u["order"],
                     "depends_on": list(u.get("depends_on", []) or [])})
    return plan


_WRONG_POOL = ["samtools sort", "bedtools intersect", "fastqc report", "gzip compress",
               "md5sum checksum", "awk column cut", "tar archive", "scp transfer"]


def selftest(dataset_path):
    rows = [json.loads(l) for l in open(dataset_path) if l.strip()]
    rows = [r for r in rows if r.get("gold_units")]
    if not rows:
        print("no rows with gold_units"); return False
    agg = defaultdict(list)
    for r in rows:
        gu, ai = r["gold_units"], r.get("aggregation", "none")
        # oracle A: first member of each unit
        a = grade(_plan_from_members(gu, lambda n: 0), gu, ai)
        # oracle B: a DIFFERENT member (last) — alternative but capability-equivalent realization
        b = grade(_plan_from_members(gu, lambda n: n - 1), gu, ai)
        # wrong: unrelated tools, same structure
        wrong = [{"sub_task": _WRONG_POOL[i % len(_WRONG_POOL)], "order": u["order"],
                  "depends_on": list(u.get("depends_on", []) or [])} for i, u in enumerate(gu)]
        w = grade(wrong, gu, ai)
        # partial: satisfy only the first half of the units
        half = max(1, len(gu) // 2)
        part = _plan_from_members(gu[:half], lambda n: 0)
        p = grade(part, gu, ai)
        agg["oracle_A"].append(a); agg["oracle_B"].append(b)
        agg["wrong"].append(w); agg["partial"].append(p)
    print(f"rows: {len(rows)}\n")
    for k in ["oracle_A", "oracle_B", "wrong", "partial"]:
        v = agg[k]
        print(f"  {k:10s} mean={sum(v)/len(v):.4f}  [min {min(v):.3f}, max {max(v):.3f}]")
    mA = sum(agg["oracle_A"]) / len(agg["oracle_A"])
    mB = sum(agg["oracle_B"]) / len(agg["oracle_B"])
    mW = sum(agg["wrong"]) / len(agg["wrong"])
    ok = mA > 0.85 and mB > 0.85 and (mA - mW) > 0.3
    print(f"\nSELFTEST {'PASS' if ok else 'FAIL'}  "
          f"(oracle_A>0.85, oracle_B>0.85 [alt realization], oracle_A-wrong>0.3)")
    return ok


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--dataset", default=os.path.join(os.path.dirname(__file__),
                                                       "reverse_decomp_train.jsonl"))
    a = ap.parse_args()
    if a.selftest:
        raise SystemExit(0 if selftest(a.dataset) else 1)
    ap.print_help()
