#!/usr/bin/env python3
"""Leakage + baseline audit of the display-binding selector (docs 20261006_BINDING_SELECTOR_WITHIN_TARGET_WIN).
The LM selector's split is a random shuffle of unique sequences ('sequence-disjoint'). Display pools contain point-mutant families,
so a random split can leak family members across train/test. This audit (no LM involved):
  1. replicates the selector split (shuffle seed 0, 20 % test) and measures how many test binders have a train binder at Hamming distance <=1 / <=2;
  2. trains a trivial k-mer logistic regression on the same split -> AUC (the bar the LM must clear);
  3. re-splits by Hamming-1 connected component (family-disjoint) -> AUC of the same trivial baseline.
usage: selector_leakage_audit.py TARGET [out.json]"""
import sys, json, random, collections, itertools
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.feature_extraction.text import CountVectorizer
from cyclic_llm_selector import load_target

CSV = "../data/display/display_ngs_multitarget.csv.gz"


def ham(a, b): return sum(x != y for x, y in zip(a, b))


def min_dist_to_set(seq, bucket):                       # bucket: same-length train binders (list)
    return min((ham(seq, t) for t in bucket), default=99)


def components(seqs):                                   # Hamming-1 connected components via masked-position hashing
    parent = {s: s for s in seqs}
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    buckets = collections.defaultdict(list)
    for s in seqs:
        for i in range(len(s)): buckets[(i, s[:i] + "_" + s[i + 1:])].append(s)
    for v in buckets.values():
        for o in v[1:]: parent[find(o)] = find(v[0])
    return {s: find(s) for s in seqs}


def kmer_auc(train, test):
    cv = CountVectorizer(analyzer="char", ngram_range=(1, 2), lowercase=False)
    Xtr = cv.fit_transform([r["seq"] for r in train]); Xte = cv.transform([r["seq"] for r in test])
    ytr = np.array([r["is_binder"] for r in train], int); yte = np.array([r["is_binder"] for r in test], int)
    if yte.sum() == 0 or ytr.sum() == 0 or yte.sum() == len(yte): return None
    m = LogisticRegression(max_iter=1000, C=1.0).fit(Xtr, ytr)
    s = m.decision_function(Xte); top = np.argsort(-s)[: max(1, len(s) // 20)]
    return dict(auc=round(float(roc_auc_score(yte, s)), 3), lift_top5=round(float(yte[top].mean() / yte.mean()), 1), n_test=len(yte), n_test_binders=int(yte.sum()))


def main(target, out=None):
    recs = load_target(CSV, target)
    random.Random(0).shuffle(recs)
    n_test = max(200, int(len(recs) * 0.2)); test, train = recs[:n_test], recs[n_test:]
    res = dict(target=target, n_unique=len(recs), n_train=len(train), n_test=len(test))
    byl = collections.defaultdict(list)
    for r in train:
        if r["is_binder"]: byl[len(r["seq"])].append(r["seq"])
    tb = [r for r in test if r["is_binder"]]
    d = [min_dist_to_set(r["seq"], byl.get(len(r["seq"]), [])) for r in tb[:1500]]
    res["test_binders_with_train_binder_within_hamming1"] = round(float(np.mean([x <= 1 for x in d])), 3) if d else None
    res["test_binders_with_train_binder_within_hamming2"] = round(float(np.mean([x <= 2 for x in d])), 3) if d else None
    res["random_split_kmer_baseline"] = kmer_auc(train, test)
    comp = components([r["seq"] for r in recs]); cs = sorted(set(comp.values())); random.Random(1).shuffle(cs)
    te_c = set(cs[: int(len(cs) * 0.2)]); fam_test = [r for r in recs if comp[r["seq"]] in te_c]; fam_train = [r for r in recs if comp[r["seq"]] not in te_c]
    res["n_families"] = len(cs); res["family_disjoint_kmer_baseline"] = kmer_auc(fam_train, fam_test)
    print(json.dumps(res, indent=1))
    if out: json.dump(res, open(out, "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
