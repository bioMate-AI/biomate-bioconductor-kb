#!/usr/bin/env python3
"""Score the clarification (interpret-or-clarify) benchmark.

Prediction per item: {"action":"interpret"|"clarify","value":<interpreted value|null>,"clarify_about":"<text>"}

Dimensions:
  - decision_acc    : correct interpret-vs-clarify choice
  - over_clarify    : of INTERPRET-gold items, fraction wrongly clarified (over-asking — annoying)
  - under_clarify   : of CLARIFY-gold items, fraction wrongly interpreted (silent wrong guess — dangerous)
  - target_acc      : right value (interpret) / right thing asked about (clarify), among decision-correct items
  - outcome (PRIMARY): slot fully correct = right decision AND right target/value
"""
import json, os, re, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))

# what a correct clarification should ask about, per fork / param / input target
CLARIFY_KEYS = {
    "variant_type": ["germline", "somatic"], "assembly_type": ["de novo", "reference"],
    "rnaseq_type": ["bulk", "single-cell", "single cell", "scrna"], "peak_calling_type": ["chip", "atac"],
    "chip_target": ["transcription factor", "histone", "narrow", "broad"],
    "proteomics_type": ["dda", "dia", "data-dependent", "data-independent"],
    "cryoem_type": ["single-particle", "spa", "tomograph", "cryo-et"],
    "metagenomics_type": ["16s", "amplicon", "shotgun"], "docking_type": ["blind", "site-directed", "pocket"],
    "rnaseq_focus": ["mrna", "mirna", "small rna", "differential"],
    "genome": ["genome", "organism", "species", "reference", "assembly"],
    "strandedness": ["strand", "stranded", "library"],
    "smiles": ["smiles", "structure", "molecule", "sdf", "compound"],
    "receptor_pdb": ["receptor", "protein", "pdb", "structure", "target"],
    "matrix": ["matrix", "counts", "fastq", "input", "data", "expression"],
    # --- hard-tier targets (v2) ---
    "contrast": ["contrast", "reference level", "baseline", "which.*control", "direction", "which condition", "treated vs"],
    "genome_conflict": ["grch37", "grch38", "hg19", "hg38", "mismatch", "conflict", "header", "dictionary", "realign", "build", "disagree"],
    "tool_data_conflict": ["bulk", "single-cell", "single cell", "long-read", "long read", "short-read", "short read",
                           "not.*design", "intended for", "instead", "smart-seq", "cellranger", "sniffles", "seurat",
                           "manta", "delly", "deseq", "raw count", "mismatch"],
    "genome_build": ["mm10", "mm39", "grcm38", "grcm39", "build", "version", "which.*mouse", "assembly"],
    "receptor_chain": ["chain", "chain a", "chain b", "subunit", "monomer", "which.*chain"],
    "matched_normal": ["matched normal", "normal", "tumor-only", "tumor only", "panel of normals", "germline control"],
    "matrix_type": ["raw count", "raw", "tpm", "normalized", "not.*count", "integer", "count matrix", "fpkm"],
    "matrix_select": ["which matrix", "which file", "raw", "normalized", "two", "counts vs", "ambiguous"],
    "read_layout": ["paired", "single-end", "single end", "layout", "r1", "r2"],
}
GENOME_ALIAS = {"grch38": {"grch38", "hg38"}, "grch37": {"grch37", "hg19"},
                "r64-1-1": {"r64-1-1", "r64", "saccharomyces", "saccer3"}, "paired": {"paired", "paired-end"}}


def norm(s): return re.sub(r"\s+", " ", str(s or "").strip().lower())


def value_ok(target, gold_value, pred_value):
    pv = norm(pred_value)
    gv = norm(gold_value)
    if target == "genome":
        al = GENOME_ALIAS.get(gv, {gv})
        return any(a in pv for a in al)
    if target == "strandedness":
        return gv in pv or ("reverse" in pv if "reverse" in gv else gv in pv)
    return gv in pv if gv else bool(pv)


def clarify_ok(target, text):
    t = norm(text)
    return any(k in t for k in CLARIFY_KEYS.get(target, [target]))


def load(path):
    return [json.loads(l) for l in open(path) if l.strip()]


def score(items, preds):
    by = {p["id"]: p for p in preds}
    n = dec = tgt = out = 0
    over_d = over_n = under_d = under_n = 0
    for it in items:
        p = by.get(it["id"])
        if not p: continue
        n += 1
        act = norm(p.get("action"))
        gold = it["gold_action"]
        if it.get("accept_either"):
            # a competent agent may clarify OR correctly interpret/default; both correct, excluded from rates
            if act == "clarify":
                ok = clarify_ok(it["gold_target"], p.get("clarify_about") or p.get("value") or "")
            elif act == "interpret":
                ok = value_ok(it["gold_target"], it.get("gold_value"), p.get("value")) if it.get("gold_value") else bool(norm(p.get("value")))
            else:
                ok = False
            dec += 1 if ok else 0
            tgt += 1 if ok else 0
            out += 1 if ok else 0
            continue
        dec_ok = (act == gold)
        dec += dec_ok
        if gold == "interpret":
            over_d += 1; over_n += 1 if act == "clarify" else 0
            t_ok = value_ok(it["gold_target"], it.get("gold_value"), p.get("value")) if it.get("gold_value") else dec_ok
        else:
            under_d += 1; under_n += 1 if act == "interpret" else 0
            t_ok = clarify_ok(it["gold_target"], p.get("clarify_about") or p.get("value") or "")
        tgt += 1 if (dec_ok and t_ok) else 0
        out += 1 if (dec_ok and t_ok) else 0
    return {
        "n": n,
        "decision_acc": round(dec / n, 3) if n else None,
        "over_clarify": round(over_n / over_d, 3) if over_d else None,
        "under_clarify": round(under_n / under_d, 3) if under_d else None,
        "outcome": round(out / n, 3) if n else None,
    }


if __name__ == "__main__":
    import sys
    items = load(os.path.join(HERE, "data.jsonl"))
    preds = load(sys.argv[1])
    print(json.dumps(score(items, preds), indent=2))
