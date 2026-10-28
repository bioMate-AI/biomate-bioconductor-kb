"""Corpus/split builder tests. Run: python3 test_build_corpus.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_corpus as B

def test_split_is_deterministic_whole_sources_and_about_25_percent():
    counts = {f"src{i}": c for i, c in enumerate([3000, 1500, 800, 600, 400, 300, 250, 200, 150, 100, 80, 60, 40, 30, 20, 10])}
    a = B.split_sources(counts); b = B.split_sources(dict(reversed(list(counts.items()))))
    assert a == b                                                                   # order of input does not matter
    held = sum(counts[s] for s in a); frac = held / sum(counts.values())
    assert 0.25 <= frac < 0.25 + max(counts.values()) / sum(counts.values()) + 1e-9, frac
    assert a <= set(counts)                                                          # whole sources only

def test_near_duplicate_filter_removes_close_analogues_but_keeps_distant_molecules():
    held = ["CC(=O)NC1CCCCC1C(=O)NCC(=O)NC(C)C(=O)O"]
    cand = {"same": "CC(=O)NC1CCCCC1C(=O)NCC(=O)NC(C)C(=O)O", "far": "c1ccccc1CCN", "close": "CC(=O)NC1CCCCC1C(=O)NCC(=O)NC(C)C(=O)OC"}
    keep = B.filter_near_duplicates(cand, held, thr=0.9, min_heavy=5)
    assert "same" not in keep and "far" in keep, keep

def test_canonical_and_size_filter():
    assert B.canon("OC(=O)C") == B.canon("CC(=O)O") and B.canon("not a smiles") is None
    assert B.canon("C" * 400, max_heavy=120) is None

if __name__ == "__main__":
    k = 0
    for n, f in sorted(globals().items()):
        if n.startswith("test_"): f(); k += 1; print("PASS", n)
    print(k, "tests passed")
