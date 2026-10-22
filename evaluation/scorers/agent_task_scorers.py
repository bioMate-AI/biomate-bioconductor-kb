"""
agent_task_scorers.py
---------------------
Pure, stdlib verifiable scorers for the DB-generated + error-mined training pool, so one GRPO
reward fn can cover the WHOLE corpus (routing + param-selection + autofix) alongside the decision
scorers. No heavy deps (safe to import in the GPU trainer).

Each scorer takes the model's completion TEXT and the row's gold, returns a float in [0,1].
"""
from __future__ import annotations

import json
import re
from typing import Any, Dict


def _norm_wf(s: str) -> str:
    """Canonicalize a workflow id for comparison: lower, nf-core↔nfcore, drop /main.nf + paths tails."""
    x = str(s or "").strip().lower().replace("nf-core", "nfcore")
    x = re.sub(r"/main\.nf$", "", x)
    return x.strip("/ ")


def _as_gold(gold: Any) -> Dict[str, Any]:
    return json.loads(gold) if isinstance(gold, str) and gold.strip().startswith("{") else gold


def score_routing(completion: str, gold: Any) -> float:
    """gold = a filename string OR {correct_workflow, acceptable_alts}. Correct iff a gold workflow
    (canonicalized) appears in the completion (tolerant to bare-name or prose answers)."""
    g = _as_gold(gold)
    if isinstance(g, dict):
        alts = [g.get("correct_workflow")] + list(g.get("acceptable_alts") or [])
    else:
        alts = [g]
    comp = _norm_wf(completion)
    for a in alts:
        if not a:
            continue
        ca = _norm_wf(a)
        if ca and (ca == comp or ca in comp):
            return 1.0
    return 0.0


def _names_in(text: str, names) -> set:
    """Match each param NAME as a whole identifier (word-bounded), not a raw substring — so a
    forbidden `input` does NOT falsely match inside a required `input_files`."""
    low = (text or "").lower()
    out = set()
    for n in names:
        if not n:
            continue
        pat = r"(?<![\w.-])" + re.escape(str(n).lower()) + r"(?![\w.-])"
        if re.search(pat, low):
            out.add(n)
    return out


def score_param_select(completion: str, gold: Any) -> float:
    """gold = {required_params, must_not_fill} (db_generated `param_select`) OR {expected_params,
    must_not_fill} (error-mined `param_prefill`, where the required NAMES are the expected_params
    keys). Reward = recall of required param NAMES, penalised for naming any must_not_fill param
    (selection + restraint). 0.7*recall + 0.3*(1 - fraction of forbidden named)."""
    g = _as_gold(gold) or {}
    required = [str(x) for x in (g.get("required_params") or [])]
    if not required and isinstance(g.get("expected_params"), dict):
        required = [str(k) for k in g["expected_params"].keys()]
    forbidden = [str(x) for x in (g.get("must_not_fill") or [])]
    if not required and not forbidden:
        return 0.0
    req_set, forb_set = set(required), set(forbidden)
    hit = _names_in(completion, req_set)
    viol = _names_in(completion, forb_set)
    recall = len(hit) / len(req_set) if req_set else 1.0  # distinct names (gold may duplicate)
    restraint = 1.0 - (len(viol) / len(forb_set) if forb_set else 0.0)
    return round(0.7 * recall + 0.3 * restraint, 4)


def score_autofix(completion: str, gold: Any) -> float:
    """gold = the correct fix-category string. Correct iff it appears (normalized) in the completion."""
    g = str(_as_gold(gold) or "").strip().lower()
    return 1.0 if g and g in (completion or "").lower() else 0.0


def _selftest() -> int:
    R = []
    ck = lambda n, c: (R.append(bool(c)), print(("PASS" if c else "FAIL"), "-", n))
    # routing: nf-core/nfcore + /main.nf tolerance
    ck("routing exact (canon)", score_routing("nfcore/chipseq/main.nf", "nf-core/chipseq") == 1.0)
    ck("routing in prose", score_routing("I'd run nfcore/chipseq for this.", "nfcore/chipseq/main.nf") == 1.0)
    ck("routing alts dict", score_routing("nf-core/rnaseq", json.dumps({"correct_workflow": "x", "acceptable_alts": ["nfcore/rnaseq/main.nf"]})) == 1.0)
    ck("routing wrong", score_routing("nfcore/sarek", "nfcore/chipseq") == 0.0)
    # param_select: recall + restraint
    g = json.dumps({"required_params": ["genome", "reads"], "must_not_fill": ["accession"]})
    ck("param full recall no violation → 1.0", score_param_select('{"genome":"GRCh38","reads":"x"}', g) == 1.0)
    ck("param violation penalised", score_param_select('{"genome":"x","reads":"y","accession":"z"}', g) < 1.0)
    ck("param half recall", abs(score_param_select('{"genome":"x"}', g) - (0.7 * 0.5 + 0.3)) < 1e-6)
    # autofix
    ck("autofix hit", score_autofix("This is a genome_mismatch error.", "genome_mismatch") == 1.0)
    ck("autofix miss", score_autofix("oom_error", "genome_mismatch") == 0.0)
    p = sum(R)
    print(f"\n{p}/{len(R)} passed")
    return 0 if p == len(R) else 1


if __name__ == "__main__":
    import sys
    sys.exit(_selftest())
