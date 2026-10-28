"""GradedMemoryBridge: connects verifier outcomes to the IH-LM update path WITHOUT turning verifier rewards into laboratory measurements.
 - annotate/ingest: a graded result (cheap-tier gate pass/fail) is attached to a MEASURED row as its `verifier` flag (the field IHLM.update already consumes for its verifier head);
   the row's label and source are untouched. Rewards are never written as labels and never under a laboratory source (the pooled-laboratory confound this study measured).
 - pairs: graded-only candidates (no measurement) become preference pairs through reward.build_preference_pairs -> dpo_pairs.PairSet (inventory row 15); no training here.
Compounds the converter cannot map, or whose tokens the gate dialect cannot represent, are counted and skipped, never imputed."""
import numpy as np
from _paths import load_ihlm
import reward as _reward
from symbolic import iso


def grade_smiles(adapter, hook, smiles):
    """-> ({iso_smiles: grade}, stats). Uses the adapter's audited converter, then the gate-dialect map; None entries are skipped."""
    out, st = {}, dict(n=len(smiles), unmapped=0, unrepresentable=0, graded=0, duplicates=0, invalid_smiles=0)
    for s in smiles:
        t = adapter.segment(s)
        if t is None: st["unmapped"] += 1; continue
        g = hook.grade_tokens(t)
        if g is None: st["unrepresentable"] += 1; continue
        k = iso(s)
        if k is None: st["invalid_smiles"] += 1; continue
        if k in out: st["duplicates"] += 1; continue                       # identical canonical SMILES (CycPeptMPDB repeats structures): keep the first grade, count the rest
        out[k] = g; st["graded"] += 1
    assert st["graded"] == len(out) and sum(st[x] for x in ("graded", "duplicates", "unmapped", "unrepresentable", "invalid_smiles")) == st["n"]
    return out, st


class GradedMemoryBridge:
    @staticmethod
    def annotate(rows, graded_by_smiles):
        """new rows with `verifier` = 1.0 / 0.0 (cheap-tier hard gate) where graded; labels, sources and K untouched."""
        out, n = [], 0
        for r in rows:
            r2 = dict(r); g = graded_by_smiles.get(iso(r["smiles"]))
            if g is not None: r2["verifier"] = 1.0 if g["hard_gate_pass"] else 0.0; n += 1
            out.append(r2)
        return out, n

    def ingest(self, model, rows, graded_by_smiles, mode="finetune_ranking", seed=0, **kw):
        """-> (new model, n_annotated). The input model is not mutated (IHLM.update clones). Fast memory is written on every call; the slow update follows the model's own schedule."""
        ann, n = self.annotate(rows, graded_by_smiles)
        assert [r["label"] for r in ann] == [r["label"] for r in rows], "labels must not change"
        assert not any(str(r.get("source", "")).startswith("verifier") for r in ann), "verifier output must never be a laboratory source"
        return model.update(ann, mode=mode, seed=seed, **kw), n

    @staticmethod
    def pairs(graded_list, prompt="", max_pairs=None):
        """preference pairs (chosen gate-pass over gate-fail, then higher reward) from graded records; emitter only, no training."""
        recs = [g["record"] for g in graded_list if g is not None]
        return _reward.build_preference_pairs(recs, prompt=prompt, max_pairs=max_pairs)
