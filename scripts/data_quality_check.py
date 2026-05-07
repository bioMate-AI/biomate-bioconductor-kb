#!/usr/bin/env python3
"""
Comprehensive data quality audit for BioMate regulatory LLM training materials.
Produces a structured report covering all training data files.
"""

import json
import re
import sys
import os
from collections import Counter, defaultdict
from pathlib import Path
import statistics

# ── Paths ────────────────────────────────────────────────────────────────────
BASE = Path("/home/yzhang/biomate/data")
REG  = BASE / "regulatory_training"
GLP  = BASE / "glp_study_data"

CORPUS   = REG / "combined_regulatory_training.jsonl"
TASK1    = REG / "tasks" / "task1_section_generation.jsonl"
TASK2    = REG / "tasks" / "task2_regulatory_qa.jsonl"
TASK3    = REG / "tasks" / "task3_region_adaptation.jsonl"
EPAR_TB  = GLP / "epar_study_tables.jsonl"
FDA_PHR  = GLP / "fda_pharmar_studies.jsonl"

# ── Helpers ──────────────────────────────────────────────────────────────────

def load_jsonl(path):
    records = []
    errors = 0
    with open(path, encoding="utf-8", errors="replace") as fh:
        for i, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as e:
                errors += 1
                if errors <= 3:
                    print(f"  [PARSE ERROR line {i}]: {e}")
    if errors:
        print(f"  ⚠️  {errors} JSON parse error(s) in {path.name}")
    return records


def word_count(text):
    if not text:
        return 0
    return len(text.split())


def percentile(data, p):
    if not data:
        return 0
    sorted_data = sorted(data)
    idx = (p / 100) * (len(sorted_data) - 1)
    lo = int(idx)
    hi = min(lo + 1, len(sorted_data) - 1)
    frac = idx - lo
    return sorted_data[lo] * (1 - frac) + sorted_data[hi] * frac


def wc_stats(counts):
    if not counts:
        return "n/a"
    return (
        f"min={min(counts):.0f}  p10={percentile(counts,10):.0f}"
        f"  p25={percentile(counts,25):.0f}  med={statistics.median(counts):.0f}"
        f"  p75={percentile(counts,75):.0f}  p90={percentile(counts,90):.0f}"
        f"  max={max(counts):.0f}"
    )


def has_non_ascii_issues(text):
    return "�" in text or any(ord(c) < 9 and c not in "\n\r\t" for c in text)


COMMON_ENGLISH = {"the", "of", "and", "to", "a", "in", "is", "that", "for", "it",
                  "was", "with", "are", "as", "at", "be", "this", "from", "or", "an"}


def is_likely_non_english(text):
    if not text or len(text.split()) < 10:
        return False
    words = {w.lower().strip(".,;:") for w in text.split()[:50]}
    overlap = words & COMMON_ENGLISH
    return len(overlap) < 2  # very low overlap with common English words


def hdr(title, level=1):
    if level == 1:
        bar = "=" * (len(title) + 4)
        print(f"\n{bar}")
        print(f"  {title}")
        print(bar)
    elif level == 2:
        print(f"\n{'─' * 60}")
        print(f"  {title}")
        print(f"{'─' * 60}")
    else:
        print(f"\n  ### {title}")


def table(rows, headers):
    """Print an aligned table."""
    col_w = [max(len(str(h)), max((len(str(r[i])) for r in rows), default=0))
             for i, h in enumerate(headers)]
    fmt = "  " + "  ".join(f"{{:<{w}}}" for w in col_w)
    sep = "  " + "  ".join("-" * w for w in col_w)
    print(fmt.format(*headers))
    print(sep)
    for row in rows:
        print(fmt.format(*row))


# ── Section 1: Raw Corpus ─────────────────────────────────────────────────────

def audit_corpus():
    hdr("1. RAW CORPUS — combined_regulatory_training.jsonl", 1)
    records = load_jsonl(CORPUS)
    print(f"\n  Total records: {len(records):,}")

    # Determine source field (may vary)
    by_source = defaultdict(list)
    for r in records:
        src = r.get("source", "UNKNOWN")
        by_source[src].append(r)

    hdr("1a. Examples per source", 2)
    src_rows = []
    for src, recs in sorted(by_source.items()):
        src_rows.append([src, len(recs)])
    table(src_rows, ["Source", "Count"])

    hdr("1b. Word count distribution per source", 2)
    for src, recs in sorted(by_source.items()):
        wcs = [word_count(r.get("response", r.get("text", ""))) for r in recs]
        print(f"\n  [{src}] n={len(recs)}")
        print(f"    {wc_stats(wcs)}")

    hdr("1c. Empty / near-empty responses (< 30 words)", 2)
    short_records = []
    for r in records:
        resp = r.get("response", r.get("text", ""))
        wc = word_count(resp)
        if wc < 30:
            short_records.append((r.get("source", "?"), wc, resp[:100].replace("\n", " ")))
    print(f"\n  Count: {len(short_records)}")
    if short_records:
        print(f"  ⚠️  ISSUE: {len(short_records)} near-empty responses found")
        for src, wc, preview in short_records[:10]:
            print(f"    [{src}] ({wc} words) {preview!r}")

    hdr("1d. Duplicate detection", 2)
    # Exact duplicates
    resp_texts = [r.get("response", r.get("text", "")) for r in records]
    exact_counts = Counter(resp_texts)
    exact_dups = {k: v for k, v in exact_counts.items() if v > 1}
    print(f"\n  Exact duplicates: {len(exact_dups)} unique texts duplicated "
          f"(covering {sum(v for v in exact_dups.values()) - len(exact_dups)} extra copies)")
    if exact_dups:
        print(f"  ⚠️  ISSUE: exact duplicates present")
        for text, cnt in sorted(exact_dups.items(), key=lambda x: -x[1])[:5]:
            print(f"    count={cnt}  preview={text[:80]!r}")

    # Near-duplicates (first 100 chars)
    prefix_counts = Counter(t[:100] for t in resp_texts)
    near_dup_prefixes = {k: v for k, v in prefix_counts.items() if v > 1}
    total_near_extra = sum(v for v in near_dup_prefixes.values()) - len(near_dup_prefixes)
    print(f"\n  Near-duplicates (same first 100 chars): "
          f"{len(near_dup_prefixes)} groups, {total_near_extra} extra copies")
    if near_dup_prefixes:
        print(f"  ⚠️  ISSUE: near-duplicates present")
        for prefix, cnt in sorted(near_dup_prefixes.items(), key=lambda x: -x[1])[:5]:
            print(f"    count={cnt}  prefix={prefix[:80]!r}")

    hdr("1e. Boilerplate contamination (admin/cover-page keywords)", 2)
    boilerplate_kw = [
        "Table of Contents",
        "Assessment report",
        "CHMP",
        "European Medicines Agency",
        "Committee for Medicinal Products",
        "Procedure No",
    ]
    bp_by_source = defaultdict(lambda: defaultdict(int))
    bp_total = defaultdict(int)
    for r in records:
        resp = r.get("response", r.get("text", ""))
        src = r.get("source", "?")
        for kw in boilerplate_kw:
            if kw.lower() in resp.lower():
                bp_by_source[src][kw] += 1
                bp_total[kw] += 1

    rows = []
    for kw in boilerplate_kw:
        total = bp_total.get(kw, 0)
        per_src = ", ".join(f"{s}:{n}" for s, n in bp_by_source[src].items()
                            ) if False else ""
        rows.append([kw, total])
    table(rows, ["Keyword", "Total Hits"])

    total_bp = sum(bp_total.values())
    if total_bp > 0:
        print(f"\n  ⚠️  ISSUE: {total_bp} boilerplate keyword hits across corpus")
        print(f"  Breakdown by source + keyword:")
        for src, kw_counts in sorted(bp_by_source.items()):
            for kw, cnt in sorted(kw_counts.items(), key=lambda x: -x[1]):
                print(f"    [{src}] '{kw}': {cnt}")

    hdr("1f. FDA label header contamination", 2)
    label_pat = re.compile(
        r"^(13\s+NONCLINICAL|12\s+CLINICAL|\d+\.\d+\s+[A-Z]{4,})",
        re.MULTILINE
    )
    label_hits = []
    for r in records:
        resp = r.get("response", r.get("text", ""))
        if label_pat.search(resp):
            label_hits.append((r.get("source", "?"), resp[:100].replace("\n", " ")))
    print(f"\n  Count: {len(label_hits)}")
    if label_hits:
        print(f"  ⚠️  ISSUE: {len(label_hits)} FDA label headers found in responses")
        for src, preview in label_hits[:5]:
            print(f"    [{src}] {preview!r}")

    hdr("1g. Non-ASCII / encoding issues", 2)
    enc_issues = []
    for i, r in enumerate(records):
        resp = r.get("response", r.get("text", ""))
        if has_non_ascii_issues(resp):
            enc_issues.append((i + 1, r.get("source", "?"), resp[:80].replace("\n", " ")))
    print(f"\n  Count: {len(enc_issues)}")
    if enc_issues:
        print(f"  ⚠️  ISSUE: {len(enc_issues)} records with encoding problems")
        for lineno, src, preview in enc_issues[:5]:
            print(f"    [line {lineno}, {src}] {preview!r}")

    hdr("1h. Language check (possible non-English)", 2)
    non_eng = []
    for i, r in enumerate(records):
        resp = r.get("response", r.get("text", ""))
        if is_likely_non_english(resp):
            non_eng.append((i + 1, r.get("source", "?"), resp[:80].replace("\n", " ")))
    print(f"\n  Count: {len(non_eng)}")
    if non_eng:
        print(f"  ⚠️  ISSUE: {len(non_eng)} possible non-English responses")
        for lineno, src, preview in non_eng[:5]:
            print(f"    [line {lineno}, {src}] {preview!r}")
    else:
        print("  All records appear to be English.")

    return len(records)


# ── Section 2: Task 1 — Section Generation ───────────────────────────────────

def audit_task1():
    hdr("2. TRAINING PAIRS — task1_section_generation.jsonl", 1)
    records = load_jsonl(TASK1)
    print(f"\n  Total records: {len(records):,}")

    CITATION_PATTERNS = [
        "ICH S2", "ICH S7", "ICH M3", "EMA/CHMP/EWP/37498",
        "21 CFR", "ICH S1", "ICH S5",
    ]
    GENO_WORDS = ["ames", "genotox", "mutagenicit", "chromosomal", "S2(R1)"]
    BOILERPLATE_STARTS = ["DEPARTMENT OF HEALTH", "Committee for Medicinal Products"]

    by_section = defaultdict(list)
    for r in records:
        meta = r.get("meta", {})
        sec = meta.get("section_type", "unknown")
        by_section[sec].append(r)

    hdr("2a. Count and word-count distribution per section_type", 2)
    for sec, recs in sorted(by_section.items()):
        asst_wcs = []
        for r in recs:
            msgs = r.get("messages", [])
            asst = next((m["content"] for m in msgs if m["role"] == "assistant"), "")
            asst_wcs.append(word_count(asst))
        print(f"\n  [{sec}] n={len(recs)}")
        print(f"    {wc_stats(asst_wcs)}")

    hdr("2b. Citation injection rate per section_type", 2)
    cit_rows = []
    for sec, recs in sorted(by_section.items()):
        with_cit = 0
        for r in recs:
            msgs = r.get("messages", [])
            asst = next((m["content"] for m in msgs if m["role"] == "assistant"), "")
            if any(pat.lower() in asst.lower() for pat in CITATION_PATTERNS):
                with_cit += 1
        pct = 100 * with_cit / len(recs) if recs else 0
        cit_rows.append([sec, len(recs), with_cit, f"{pct:.1f}%"])
    table(cit_rows, ["section_type", "Total", "With Citation", "Rate"])

    hdr("2c. Prompt-target alignment: tox_genotox misclassification", 2)
    geno_recs = by_section.get("tox_genotox", [])
    misclassified = []
    for r in geno_recs:
        msgs = r.get("messages", [])
        asst = next((m["content"] for m in msgs if m["role"] == "assistant"), "").lower()
        if not any(kw in asst for kw in GENO_WORDS):
            meta = r.get("meta", {})
            drug = meta.get("drug", "?")
            misclassified.append((drug, asst[:100]))
    print(f"\n  tox_genotox records: {len(geno_recs)}")
    print(f"  Missing genotoxicity keywords: {len(misclassified)}")
    if misclassified:
        print(f"  ⚠️  ISSUE: {len(misclassified)} tox_genotox records may be misclassified")
        for drug, preview in misclassified[:5]:
            print(f"    [{drug}] {preview!r}")

    hdr("2d. Boilerplate leak in assistant targets", 2)
    bp_leak = []
    for r in records:
        msgs = r.get("messages", [])
        asst = next((m["content"] for m in msgs if m["role"] == "assistant"), "")
        for bp in BOILERPLATE_STARTS:
            if asst.strip().startswith(bp):
                bp_leak.append((r.get("meta", {}).get("drug", "?"), asst[:100]))
    print(f"\n  Count: {len(bp_leak)}")
    if bp_leak:
        print(f"  ⚠️  ISSUE: {len(bp_leak)} targets start with boilerplate")
        for drug, preview in bp_leak[:5]:
            print(f"    [{drug}] {preview!r}")
    else:
        print("  No boilerplate leak detected.")

    hdr("2e. Duplicate assistant targets", 2)
    target_texts = []
    for r in records:
        msgs = r.get("messages", [])
        asst = next((m["content"] for m in msgs if m["role"] == "assistant"), "")
        target_texts.append(asst)
    dup_counts = Counter(target_texts)
    dups = {k: v for k, v in dup_counts.items() if v > 1}
    total_dup_extra = sum(v - 1 for v in dups.values())
    print(f"\n  Exact duplicate targets: {len(dups)} unique texts, {total_dup_extra} extra copies")
    if dups:
        print(f"  ⚠️  ISSUE: duplicate assistant targets present")
        for text, cnt in sorted(dups.items(), key=lambda x: -x[1])[:5]:
            print(f"    count={cnt}  preview={text[:80]!r}")

    return len(records)


# ── Section 3: Task 2 — QA Pairs ─────────────────────────────────────────────

def audit_task2():
    hdr("3. QA PAIRS — task2_regulatory_qa.jsonl", 1)
    records = load_jsonl(TASK2)
    print(f"\n  Total records: {len(records):,}")

    hdr("3a. Full listing: question + answer previews", 2)
    issues = []
    for i, r in enumerate(records, 1):
        msgs = r.get("messages", [])
        q = next((m["content"] for m in msgs if m["role"] == "user"), "")
        a = next((m["content"] for m in msgs if m["role"] == "assistant"), "")
        wc_a = word_count(a)
        q_short = q[:80].replace("\n", " ")
        a_short = a[:80].replace("\n", " ")
        print(f"\n  [{i:02d}] Q: {q_short!r}")
        print(f"       A: {a_short!r}")
        print(f"       Answer words: {wc_a}")
        if wc_a < 50:
            issues.append(i)
            print(f"       ⚠️  ISSUE: answer too short ({wc_a} words)")
        # Circular check: does the answer contain the exact question?
        if q.strip()[:50].lower() in a.lower():
            issues.append(i)
            print(f"       ⚠️  ISSUE: answer appears to repeat the question")

    if issues:
        print(f"\n  ⚠️  ISSUE: {len(set(issues))} QA pairs have problems")
    else:
        print(f"\n  All {len(records)} QA pairs look healthy.")

    return len(records)


# ── Section 4: Task 3 — Region Adaptation ────────────────────────────────────

def audit_task3():
    hdr("4. REGION ADAPTATION PAIRS — task3_region_adaptation.jsonl", 1)
    records = load_jsonl(TASK3)
    print(f"\n  Total records: {len(records):,}")

    hdr("4a. Count per target region", 2)
    # Actual field names: meta.source_region and meta.target_region
    by_target = Counter()
    by_section = Counter()
    for r in records:
        meta = r.get("meta", {})
        tgt = meta.get("target_region", meta.get("region", "unknown"))
        sec = meta.get("section_type", "unknown")
        by_target[tgt] += 1
        by_section[sec] += 1

    tgt_rows = [[region, cnt] for region, cnt in sorted(by_target.items())]
    table(tgt_rows, ["Target Region", "Count"])
    print()
    sec_rows = [[sec, cnt] for sec, cnt in sorted(by_section.items())]
    table(sec_rows, ["Section Type", "Count"])

    hdr("4b. Do region-adaptation targets actually differ from FDA input?", 2)
    # Check if assistant output == input FDA text (copied verbatim — no adaptation)
    input_eq_output = 0
    no_fda_block = 0
    examples_copied = []
    for r in records:
        msgs = r.get("messages", [])
        user_msg = next((m["content"] for m in msgs if m["role"] == "user"), "")
        asst = next((m["content"] for m in msgs if m["role"] == "assistant"), "")
        m = re.search(r"FDA text:\s*\n(.+)", user_msg, re.DOTALL)
        if m:
            fda_text_in_prompt = m.group(1).strip()
            if asst.strip()[:200] == fda_text_in_prompt[:200]:
                input_eq_output += 1
                meta = r.get("meta", {})
                if len(examples_copied) < 3:
                    examples_copied.append((
                        meta.get("target_region", "?"),
                        meta.get("section_type", "?"),
                        asst[:100].replace("\n", " ")
                    ))
        else:
            no_fda_block += 1

    total = len(records)
    pct = 100 * input_eq_output / total if total else 0
    print(f"\n  Records checked: {total}")
    print(f"  Records without 'FDA text:' block in prompt: {no_fda_block}")
    print(f"  Output == input FDA text (first 200 chars): {input_eq_output} ({pct:.1f}%)")
    if input_eq_output > 0:
        print(f"  ⚠️  ISSUE: {input_eq_output}/{total} ({pct:.1f}%) region-adaptation targets are "
              f"verbatim copies of the input — no adaptation occurred")
        for tgt, sec, preview in examples_copied:
            print(f"    [target={tgt}, section={sec}] {preview!r}")
    else:
        print("  All targets show changes relative to the FDA input.")

    return len(records)


# ── Section 5: EPAR Study Tables ─────────────────────────────────────────────

def audit_epar_tables():
    hdr("5. EPAR STUDY TABLES — epar_study_tables.jsonl", 1)
    records = load_jsonl(EPAR_TB)
    print(f"\n  Total records: {len(records):,}")

    hdr("5a. Records with empty headers", 2)
    empty_hdr = [r for r in records if not any(h.strip() for h in r.get("headers", []))]
    print(f"\n  Count: {len(empty_hdr)}")
    if empty_hdr:
        print(f"  ⚠️  ISSUE: {len(empty_hdr)} records have completely empty header lists")

    hdr("5b. Records with NOAEL/dose-related headers", 2)
    noael_kw = re.compile(r"\b(noael|noel|dose|mg/kg|dosing|loael|ld50)\b", re.IGNORECASE)
    noael_recs = [r for r in records if any(noael_kw.search(h) for h in r.get("headers", []))]
    print(f"\n  Count: {len(noael_recs)} ({100*len(noael_recs)/len(records):.1f}% of total)")

    hdr("5c. Average rows per table", 2)
    row_counts = [len(r.get("rows", [])) for r in records]
    print(f"\n  {wc_stats(row_counts)}")
    print(f"  Mean: {statistics.mean(row_counts):.1f}")

    hdr("5d. Top 10 drugs by table count", 2)
    drug_counts = Counter(r.get("drug", "unknown") for r in records)
    top10 = drug_counts.most_common(10)
    table([[d, c] for d, c in top10], ["Drug", "Tables"])

    hdr("5e. Empty or single-char headers", 2)
    total_headers = sum(len(r.get("headers", [])) for r in records)
    bad_hdrs = sum(
        1 for r in records
        for h in r.get("headers", [])
        if len(h.strip()) <= 1
    )
    pct = 100 * bad_hdrs / total_headers if total_headers else 0
    print(f"\n  Total header cells: {total_headers:,}")
    print(f"  Empty / single-char headers: {bad_hdrs:,} ({pct:.1f}%)")
    if pct > 20:
        print(f"  ⚠️  ISSUE: High fraction of empty/single-char headers — "
              f"suggests PDF table extraction artifacts")

    hdr("5f. Merged/garbled headers (newlines or > 80 chars)", 2)
    garbled = 0
    garbled_examples = []
    for r in records:
        for h in r.get("headers", []):
            if "\n" in h or len(h) > 80:
                garbled += 1
                if len(garbled_examples) < 3:
                    garbled_examples.append((r.get("drug", "?"), h[:100].replace("\n", "\\n")))
    print(f"\n  Count: {garbled}")
    if garbled:
        print(f"  ⚠️  ISSUE: {garbled} garbled headers (newlines or >80 chars)")
        for drug, h in garbled_examples:
            print(f"    [{drug}] {h!r}")

    return len(records)


# ── Section 6: FDA PharmR Records ────────────────────────────────────────────

def audit_fda_pharmar():
    hdr("6. FDA PharmR RECORDS — fda_pharmar_studies.jsonl", 1)
    records = load_jsonl(FDA_PHR)
    print(f"\n  Total records: {len(records):,}")

    hdr("6a. Records by source type (prose vs table)", 2)
    src_counts = Counter(r.get("source", "unknown") for r in records)
    table([[s, c] for s, c in sorted(src_counts.items())], ["Source Type", "Count"])

    hdr("6b. NOAEL value distribution", 2)
    noael_values = []
    has_noael = 0
    suspicious = []
    for r in records:
        nv = r.get("noael_value")
        if nv is not None:
            try:
                fv = float(nv)
                noael_values.append(fv)
                has_noael += 1
                if fv < 0.001 or fv > 10000:
                    suspicious.append((r.get("source_app", "?"), r.get("species", "?"), fv))
            except (ValueError, TypeError):
                pass  # non-numeric NOAEL
    print(f"\n  Records with numeric NOAEL: {has_noael} / {len(records)}")
    if noael_values:
        print(f"  Range: {min(noael_values):.4g} – {max(noael_values):.4g} mg/kg")
        print(f"  {wc_stats(noael_values)}")
    if suspicious:
        print(f"\n  ⚠️  ISSUE: {len(suspicious)} records with suspicious NOAEL values "
              f"(< 0.001 or > 10000 mg/kg):")
        for app, species, val in suspicious[:5]:
            print(f"    [{app}, {species}] NOAEL={val}")

    hdr("6c. Study type distribution", 2)
    study_counts = Counter(r.get("study_type", "unknown") for r in records)
    study_rows = sorted(study_counts.items(), key=lambda x: -x[1])
    table([[s, c] for s, c in study_rows[:20]], ["Study Type", "Count"])
    if len(study_rows) > 20:
        print(f"  ... and {len(study_rows) - 20} more study types")

    hdr("6d. Species distribution", 2)
    species_counts = Counter(r.get("species", "unknown") for r in records)
    species_rows = sorted(species_counts.items(), key=lambda x: -x[1])
    table([[s, c] for s, c in species_rows[:15]], ["Species", "Count"])

    hdr("6e. Records with missing key_findings / noael_context text", 2)
    # Prose records store findings in 'noael_context'; table records store in 'rows'
    missing_findings = []
    for r in records:
        src_type = r.get("source", "")
        if src_type == "table":
            rows = r.get("rows", [])
            if not rows:
                missing_findings.append((r.get("source_app", "?"), "table: no rows"))
        elif src_type == "prose":
            ctx = r.get("noael_context", "")
            if not ctx or len(ctx.strip()) < 20:
                missing_findings.append((r.get("source_app", "?"), "prose: empty noael_context"))
        else:
            # Unrecognised source type
            missing_findings.append((r.get("source_app", "?"), f"unknown source type: {src_type!r}"))
    print(f"\n  Records with missing/empty findings: {len(missing_findings)}")
    if missing_findings:
        print(f"  ⚠️  ISSUE: {len(missing_findings)} records have no usable findings text")
        for app, reason in missing_findings[:5]:
            print(f"    [{app}] {reason}")
    else:
        print("  All records have usable findings text.")

    return len(records)


# ── Summary ───────────────────────────────────────────────────────────────────

def print_summary(counts):
    hdr("SUMMARY", 1)
    rows = [
        ["combined_regulatory_training.jsonl", counts.get("corpus", 0)],
        ["task1_section_generation.jsonl", counts.get("task1", 0)],
        ["task2_regulatory_qa.jsonl", counts.get("task2", 0)],
        ["task3_region_adaptation.jsonl", counts.get("task3", 0)],
        ["epar_study_tables.jsonl", counts.get("epar", 0)],
        ["fda_pharmar_studies.jsonl", counts.get("fda_pharmar", 0)],
    ]
    table(rows, ["File", "Records"])
    total = sum(c for _, c in rows)
    print(f"\n  Total records audited: {total:,}")
    print(f"\n  Search for '⚠️  ISSUE' in this report to find all flagged problems.")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("\n" + "=" * 70)
    print("  BIOMATE REGULATORY LLM TRAINING DATA QUALITY AUDIT")
    print(f"  Generated: 2026-05-06")
    print("=" * 70)

    counts = {}
    counts["corpus"]     = audit_corpus()
    counts["task1"]      = audit_task1()
    counts["task2"]      = audit_task2()
    counts["task3"]      = audit_task3()
    counts["epar"]       = audit_epar_tables()
    counts["fda_pharmar"] = audit_fda_pharmar()
    print_summary(counts)
    print()


if __name__ == "__main__":
    main()
