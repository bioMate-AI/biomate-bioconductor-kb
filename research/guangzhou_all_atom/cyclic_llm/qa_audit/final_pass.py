#!/usr/bin/env python3
"""Mechanical part of the final claim-evidence pass (T-QA). Read-only. usage: python3 final_pass.py [--res5 DIR]
Checks: frozen-aggregate hash and every cited prefix, mean-inside-interval for every contrast, interval-level labels,
L5 spread vs bootstrap-of-mean from raw per-seed files (if --res5 given), provenance ancestry of IH-LM commits,
stale-string blacklist across the manuscript documents, citation-tag census, licence-tag check, 'result' sentences about
unfinished items (heuristic, for manual review). Prints PASS/FAIL/REVIEW lines; exit code 1 if any FAIL."""
import re, sys, json, glob, hashlib, subprocess, argparse, pathlib
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[4]
LR = ROOT / "research/guangzhou_all_atom/cyclic_llm/loop_retro/results"
DOCS = {"main": ROOT / "docs/20261029_MANUSCRIPT_LOOP_SMALL_LLM_DRAFT.md",
        "preprint": ROOT / "docs/20261027_PREPRINT_V1_PUBLIC/manuscript_loop.md",
        "patch": ROOT / "docs/20261030_RSI_MANUSCRIPT_PATCH_NOTE.md",
        "figplan": ROOT / "docs/20261029_MANUSCRIPT_FIGURE_AND_TABLE_PLAN.md",
        "brief": ROOT / "docs/20261030_REVIEW_BRIEF.md"}
FAILS = []


def out(tag, msg):
    print(f"{tag:7s} {msg}")
    if tag == "FAIL": FAILS.append(msg)


def sh(*a):
    return subprocess.run(a, cwd=ROOT, capture_output=True, text=True).stdout.strip()


def text(k):
    p = DOCS[k]
    return p.read_text() if p.exists() else None


def hashes():
    f = LR / "l7_aggregate.json"; s = LR / "l7_aggregate.sha256"
    h = hashlib.sha256(f.read_bytes()).hexdigest(); rec = s.read_text().split()[0]
    out("PASS" if h == rec else "FAIL", f"l7_aggregate.json sha256 {h[:12]} vs recorded {rec[:12]}")
    for k in DOCS:
        t = text(k)
        if t is None: continue
        for m in set(re.findall(r"(?:SHA-256|sha256|hash)[^`\n]{0,40}?([0-9a-f]{8})(?:…|\.\.\.)", t)):
            if m != h[:8]:
                out("REVIEW", f"{k}: cites hash prefix {m} (current {h[:8]}) - confirm it names an older or different file")


def intervals():
    d = json.load(open(LR / "l7_aggregate.json"))["small"]
    n = bad = nolevel = 0
    for reg, v in d.items():
        for scope in ("contrasts", "contrasts_cluster"):
            for k, c in v.get(scope, {}).items():
                if not isinstance(c, dict) or c.get("mean") is None: continue
                n += 1
                if scope == "contrasts":
                    if c.get("ci") and not (c["ci"][0] <= c["mean"] <= c["ci"][1]): bad += 1; out("FAIL", f"{reg} {k}: mean outside ci")
                    if "ci_level_pct" not in c: nolevel += 1
                else:
                    for key in ("ci_cluster", "ci_seed_only"):
                        if not (c[key][0] <= c["mean"] <= c[key][1]): bad += 1; out("FAIL", f"{reg} {k}: mean outside {key}")
    out("PASS" if not bad else "FAIL", f"{n} contrasts checked: mean inside every interval ({bad} violations)")
    out("PASS" if not nolevel else "FAIL", f"ci_level_pct present on all seed contrasts ({nolevel} missing)")


def l5(res5):
    a = json.load(open(LR / "l5_aggregate.json"))
    for k in ("fp_minus_random_A", "fp_minus_random_B", "fp_minus_random_C"):
        v = a[k]; ok = "ci95_mean" in v and v["ci95_mean"][0] <= v["mean"] <= v["ci95_mean"][1]
        out("PASS" if ok else "FAIL", f"l5 {k}: mean {v['mean']} spread {v['ci95']} boot-mean {v.get('ci95_mean')}")
    if not res5: return
    R = {}
    for f in glob.glob(f"{res5}/*.json"):
        r = json.load(open(f)); R[(r["arm"], r["regime"], r["seed"])] = r
    rng = np.random.default_rng(0)
    for reg in "ABC":
        s = sorted({k[2] for k in R if k[0] == "fp" and k[1] == reg} & {k[2] for k in R if k[0] == "random" and k[1] == reg})
        d = np.array([R[("fp", reg, x)]["greedy"] - R[("random", reg, x)]["greedy"] for x in s])
        bs = np.percentile([rng.choice(d, len(d)).mean() for _ in range(5000)], [2.5, 97.5])
        art = a[f"fp_minus_random_{reg}"]
        ok = abs(d.mean() - art["mean"]) < 0.06 and abs(bs[0] - art["ci95_mean"][0]) < 0.8
        out("PASS" if ok else "FAIL", f"raw res5 regime {reg}: mean {d.mean():.1f}, boot-mean {bs.round(1).tolist()} vs artifact {art['ci95_mean']}")


def provenance():
    base = "87f4f6718"
    anc = subprocess.run(["git", "merge-base", "--is-ancestor", base, "HEAD"], cwd=ROOT).returncode == 0
    out("PASS" if anc else "FAIL", f"HEAD contains {base} (IH-LM provenance floor)")
    for k in DOCS:
        t = text(k)
        if t is None: continue
        for line in t.splitlines():
            if re.search(r"IH-?LM|ihlm", line) and re.search(r"\b(AUROC|Spearman|yield|rho|ρ)\b", line) and re.search(r"\d\.\d", line) \
               and not re.search(r"not run|no result|pending|planned|design|no number|untested|has not", line, re.I):
                out("REVIEW", f"{k}: IH-LM line with numbers and no 'not run/pending' marker: {line[:140]}")
                for c in re.findall(r"\b([0-9a-f]{9})\b", line):
                    if subprocess.run(["git", "cat-file", "-e", c], cwd=ROOT, capture_output=True).returncode == 0:
                        ok = subprocess.run(["git", "merge-base", "--is-ancestor", base, c], cwd=ROOT).returncode == 0
                        out("PASS" if ok else "FAIL", f"{k}: commit {c} descends from {base}")


STALE = [r"plain[- ]GBM (regime )?B has (only )?(2|two) seeds", r"one in four", r"\b7 of 7\b", r"\b6 of 6\b", r"three of six|3 of 6 configurations",
         r"small LLM", r"learn\s*0\.299", r"0\.299 / 0\.118(?!.*(withdrawn|logged|not citable))", r"\+32\.6(?!.*superseded)",
         r"all 15 99 ?% intervals include zero(?!.*spread)", r"396\.7", r"98\.5 ?%", r"54 of 57"]


def stale():
    for k in DOCS:
        t = text(k)
        if t is None: continue
        for i, line in enumerate(t.splitlines(), 1):
            for pat in STALE:
                if re.search(pat, line, re.I) and not re.search(r"supersed|withdrawn|stale|retired|earlier (version|draft|statements)|S1|replaced", line, re.I):
                    out("REVIEW", f"{k}:{i}: stale pattern /{pat}/: {line[:120]}")


def citations():
    risky = ["Graber", "Jablonka", r"CycPeptMP(?!DB)", "Feller and Wilke", "Geylan et al", "Liu et al", "Liu, Li, Verma"]
    for k in ("main", "preprint", "patch", "brief"):
        t = text(k)
        if t is None: continue
        tags = re.findall(r"\[(LIT-[A-Z]+)", t)
        out("INFO", f"{k}: citation tags {dict((x, tags.count(x)) for x in sorted(set(tags)))}")
        for line in t.splitlines():
            for r in risky:
                if re.search(r, line) and "LIT-VERIFIED" in line and "UNVERIFIED" not in line:
                    out("FAIL", f"{k}: {r} tagged LIT-VERIFIED (not re-openable in the audit): {line[:120]}")
        for line in t.splitlines():
            if re.search(r"NC-SA|NC-ND|CC BY-NC", line) and not re.search(r"UNVERIFIED|LIT-VERIFIED|unresolved|conflict", line):
                out("REVIEW", f"{k}: licence statement without a verification tag: {line[:120]}")


def results_vs_unfinished():
    for k in ("main", "preprint", "brief"):
        t = text(k)
        if t is None: continue
        for i, line in enumerate(t.splitlines(), 1):
            if re.search(r"\b(IH-LM|larger pretrained|external base|P1 pretrain|S2 physics|confirmatory)", line, re.I) and \
               re.search(r"\b(improv|outperform|beats?|non-inferior|superior|gain of|achiev)", line, re.I) and \
               not re.search(r"not run|no result|pending|planned|to be|would|hypothes|if |not claimed|not tested|untested|design", line, re.I):
                out("REVIEW", f"{k}:{i}: possible result claim about an unfinished item: {line[:140]}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--res5"); a = ap.parse_args()
    for f in (hashes, intervals, provenance, stale, citations, results_vs_unfinished): f()
    l5(a.res5)
    print(f"\nFAILS: {len(FAILS)}")
    sys.exit(1 if FAILS else 0)
