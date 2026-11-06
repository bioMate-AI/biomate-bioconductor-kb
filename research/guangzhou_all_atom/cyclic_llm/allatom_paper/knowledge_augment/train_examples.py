"""Training-example generator: (prompt, control codes, target molecule) triples for fine-tuning the knowledge-conditioned generator.

Data: ONLY group-A peptides (Source in {2020_Townsend, 2021_Kelly}; source_groups_v2.json). The store the neighbours come from is built from the same rows, so nothing from groups
S/B can reach a prompt or a target (asserted). Exclusions ("CycPeptMPDB exclusions as before"): any peptide whose non-isomeric canonical SMILES is in `cpm_exclude_flat`
(the pilot-3 held-out CycPeptMPDB partition that the novelty and Y metrics are computed against; supplied at run time from generation_pilot/gen_pilot.py on EC2) is dropped
both as a target and as a neighbour; the number dropped is reported. The target molecule's own flat key (all stereo siblings) is excluded from its neighbours, enforced by BlindRule.
The prompt is produced by the SAME builder as generation (prompts.build_pack). Control codes: level code + ring-size bin from the target's largest ring (atoms/3 residues).
No target-specific information exists for group-A permeability peptides (no target), so arm-G exclusion by accession is a no-op for this generator; `exclude_tokens` is still passed to the
prompt builder and recorded.
EC2 / Spark only (RDKit, pandas)."""
import hashlib
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AP = os.path.normpath(os.path.join(HERE, ".."))
for p in (AP, os.path.join(AP, "track_e")):
    if p not in sys.path:
        sys.path.insert(0, p)
from knowledge_augment.levels import P, build_level  # noqa: E402
from knowledge_augment.prompts import build_pack, control_codes  # noqa: E402
from retrieval import Retriever, RetrievalStore, BlindRule, canon  # noqa: E402


def group_a_sources():
    g = json.load(open(P["groups"]))["membership"]
    return sorted(s for s, v in g.items() if v["group"] == "A")


def group_a_rows(ann_path=None):
    import verifiers_e as VE
    d = VE.load_labelled(ann_path) if ann_path else VE.load_labelled()
    A = set(group_a_sources())
    d = d[d["Source"].isin(A)]
    assert set(d["Source"].unique()) <= A
    return [(r.smiles, r.Source, float(r.z)) for r in d.itertuples()]


def largest_ring_residues(smiles):
    from rdkit import Chem
    m = Chem.MolFromSmiles(smiles)
    rr = [len(r) for r in m.GetRingInfo().AtomRings()]
    return max(4, min(30, round(max(rr) / 3.0))) if rr else None


def make_examples(level_name, n, seed=0, k_nb=4, cpm_exclude_flat=frozenset(), exclude_tokens=(), ann_path=None, rows=None):
    lv = build_level(level_name, exclude_tokens)
    rows = rows if rows is not None else group_a_rows(ann_path)
    A = set(group_a_sources())
    assert all(src in A for _, src, _ in rows), "non-group-A row"
    cpm = frozenset(cpm_exclude_flat)
    store = RetrievalStore()
    kept, dropped = [], 0
    for smi, src, z in rows:
        c = canon(smi)
        if c is None:
            continue
        if c[1] in cpm:
            dropped += 1
            continue
        if store.add(smi, {"z": z}, doc=src, source="groupA"):
            kept.append((smi, src, z, c[1]))
    rt = Retriever(store)
    rng = random.Random(seed)
    idx = list(range(len(kept)))
    rng.shuffle(idx)
    out = []
    for i in idx[:n]:
        smi, src, z, flat = kept[i]
        rule = BlindRule.for_answer_docs([], [flat])
        hits = rt.query(smi, k=k_nb, exclude_flat=rule.exclude_flat)
        rule.assert_clean(hits)
        res, kmeta = build_pack(lv, hits, None, exclude_tokens)
        rr = largest_ring_residues(smi)
        out.append(dict(level=lv.name, config_hash=lv.config_hash, prompt=res.text, control=control_codes(lv.name, None, rr), target=smi, source=src,
                        neighbours=[h.smiles for h in hits], knowledge_ids=[x["id"] for x in kmeta["lines"]], n_tokens_est=res.n_tokens_est))
    info = dict(level=lv.name, config_hash=lv.config_hash, n_group_a_rows=len(rows), n_dropped_cpm_exclusion=dropped, n_store=len(kept), n_examples=len(out), sources=sorted(A),
                seed=seed, exclude_tokens=list(exclude_tokens),
                examples_sha256=hashlib.sha256(json.dumps([(e["target"], e["prompt"]) for e in out]).encode()).hexdigest()[:16])
    return out, info
