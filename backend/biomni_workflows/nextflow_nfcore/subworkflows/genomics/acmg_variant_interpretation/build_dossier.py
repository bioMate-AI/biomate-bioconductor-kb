#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_dossier.py -- consume annotated variants (VEP TSV or a JSON variant list)
and emit a structured, auditable ACMG evidence dossier per variant + a
human-readable Markdown report.

HONEST-FAIL: if NO variant carries any usable evidence axis, the script exits
non-zero and writes nothing but an error record. It never fabricates evidence
or a classification. No RNG anywhere.

Python 3.9-safe.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from typing import Any, Dict, List, Optional

# Import criteria engine (same directory).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import acmg_criteria as ac  # noqa: E402


# Map VEP CSQ / common annotation column names -> our canonical evidence keys.
# Only real, standard VEP / annotation fields are mapped -- nothing invented.
_COLUMN_ALIASES = {
    # allele frequency
    "gnomADg_AF": "gnomad_af", "gnomADe_AF": "gnomad_af", "gnomAD_AF": "gnomad_af",
    "AF": "gnomad_af", "MAX_AF": "max_af", "gnomAD_grpmax_AF": "gnomad_af_grpmax",
    "gnomADg_AF_grpmax": "gnomad_af_grpmax", "gnomAD_popmax_AF": "gnomad_af_popmax",
    # in-silico
    "REVEL": "revel", "revel": "revel",
    "am_pathogenicity": "alphamissense", "AlphaMissense": "alphamissense",
    "am_class": "am_class", "CADD_PHRED": "cadd_phred", "CADD_phred": "cadd_phred",
    # constraint
    "pLI": "pli", "LOEUF": "loeuf", "oe_lof_upper": "loeuf",
    # consequence
    "Consequence": "consequence", "consequence": "consequence",
    # clinvar
    "CLIN_SIG": "clinvar_sig", "CLNSIG": "clinvar_sig", "ClinVar_CLNSIG": "clinvar_sig",
    "CLNREVSTAT": "clinvar_review", "ClinVar_CLNREVSTAT": "clinvar_review",
    # identity
    "SYMBOL": "gene", "Gene": "gene_id", "HGVSc": "hgvsc", "HGVSp": "hgvsp",
    "CHROM": "chrom", "POS": "pos", "REF": "ref", "ALT": "alt", "ID": "variant_id",
}


def _normalize_row(row):
    # type: (Dict[str, Any]) -> Dict[str, Any]
    ev = {}  # type: Dict[str, Any]
    for k, v in row.items():
        if k is None:
            continue
        canon = _COLUMN_ALIASES.get(k, k)
        # do not overwrite a populated canonical key with an empty later alias
        if canon in ev and (v is None or str(v).strip() in ("", ".")):
            continue
        ev[canon] = v
    # If any gnomAD-ish AF column is present in the source at all, mark queried.
    if any(a in row for a in ("gnomADg_AF", "gnomADe_AF", "gnomAD_AF", "AF",
                              "gnomAD_grpmax_AF", "gnomAD_popmax_AF")):
        ev.setdefault("gnomad_queried", True)
    return ev


def _variant_label(ev):
    # type: (Dict[str, Any]) -> str
    gene = ev.get("gene") or ev.get("gene_id") or ""
    hgvsp = ev.get("hgvsp") or ""
    hgvsc = ev.get("hgvsc") or ""
    chrom = ev.get("chrom"); pos = ev.get("pos")
    ref = ev.get("ref"); alt = ev.get("alt")
    if gene and hgvsp:
        return "%s %s" % (gene, hgvsp)
    if gene and hgvsc:
        return "%s %s" % (gene, hgvsc)
    if chrom and pos:
        return "%s:%s%s>%s" % (chrom, pos, ref or "", alt or "")
    return ev.get("variant_id") or "variant"


def load_variants(path):
    # type: (str) -> List[Dict[str, Any]]
    """Load variants from a VEP/annotation TSV or a JSON list. No fabrication."""
    lower = path.lower()
    if lower.endswith(".json"):
        with open(path) as fh:
            data = json.load(fh)
        if isinstance(data, dict) and "variants" in data:
            data = data["variants"]
        if not isinstance(data, list):
            raise ValueError("JSON input must be a list of variant objects.")
        return [_normalize_row(r) for r in data]
    # default: TSV / CSV
    delim = "," if lower.endswith(".csv") else "\t"
    rows = []  # type: List[Dict[str, Any]]
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh, delimiter=delim)
        for r in reader:
            rows.append(_normalize_row(r))
    return rows


def build(variants, max_credible_af=None):
    # type: (List[Dict[str, Any]], Optional[float]) -> Dict[str, Any]
    dossiers = []
    n_with_evidence = 0
    for ev in variants:
        ok, missing = ac.has_minimum_evidence(ev)
        label = _variant_label(ev)
        if not ok:
            dossiers.append({
                "variant": label,
                "status": "insufficient_evidence",
                "missing_evidence": missing,
                "note": ("No usable evidence axis for this variant -- no dossier "
                         "computed (honest skip, no fabrication)."),
                "raw_evidence": ev,
            })
            continue
        n_with_evidence += 1
        result = ac.classify(ev, max_credible_af=max_credible_af)
        result["variant"] = label
        result["status"] = "evaluated"
        result["raw_evidence"] = ev
        dossiers.append(result)

    return {
        "schema": "biomate.acmg_dossier.v1",
        "engine": "acmg_variant_interpretation",
        "honesty_boundary": (
            "This engine applies ONLY mechanically-computable ACMG/AMP-2015 "
            "criteria (BA1/BS1/PM2_Supporting/PP3/BP4 + PVS1 precondition flag). "
            "It does NOT emit a final clinical classification. Every provisional "
            "tier is a transparent additive summary of the auto-applied criteria "
            "and REQUIRES expert review. Missing evidence -> criterion unknown -> "
            "defaults toward VUS. No evidence or classification is fabricated."),
        "n_variants": len(variants),
        "n_evaluated": n_with_evidence,
        "n_insufficient_evidence": len(variants) - n_with_evidence,
        "variants": dossiers,
    }


def render_markdown(dossier):
    # type: (Dict[str, Any]) -> str
    L = []
    L.append("# ACMG Variant Interpretation -- Evidence Dossier")
    L.append("")
    L.append("> %s" % dossier["honesty_boundary"])
    L.append("")
    L.append("- Variants supplied: **%d**" % dossier["n_variants"])
    L.append("- Evaluated (had usable evidence): **%d**" % dossier["n_evaluated"])
    L.append("- Skipped (insufficient evidence): **%d**"
             % dossier["n_insufficient_evidence"])
    L.append("")
    for d in dossier["variants"]:
        L.append("---")
        L.append("## %s" % d["variant"])
        if d.get("status") == "insufficient_evidence":
            L.append("")
            L.append("**Status: INSUFFICIENT EVIDENCE -- no dossier computed.**")
            L.append("")
            L.append("Missing: %s" % ", ".join(d["missing_evidence"]))
            L.append("")
            continue
        prov = d["provisional"]
        L.append("")
        L.append("**Provisional tier: %s**  (points=%d, from %d automatable criteria)"
                 % (prov["tier"], prov["points"],
                    prov["n_automatable_criteria_applied"]))
        L.append("")
        L.append("> %s" % prov["label"])
        L.append("")
        cv = d.get("clinvar_reference")
        if cv:
            stars = cv.get("review_stars")
            L.append("_ClinVar (reference only, not used in tier):_ **%s** "
                     "(review: %s%s)"
                     % (cv.get("clinical_significance"),
                        cv.get("review_status"),
                        ", %d star" % stars if stars is not None else ""))
            L.append("")

        def _section(title, items):
            if not items:
                return
            L.append("**%s**" % title)
            for it in items:
                code = it["code"]
                L.append("- `%s` (%s, %s): %s"
                         % (code, it.get("strength"), it.get("direction"),
                            it["rationale"]))
            L.append("")

        _section("Auto-applied criteria (with evidence citations)",
                 d["applied_criteria"])
        _section("Flagged -- preconditions met, EXPERT CONFIRMATION REQUIRED",
                 d["flagged_criteria"])
        _section("Evaluated but not met", d["not_applicable_criteria"])
        _section("Could not assess (evidence missing -> unknown)",
                 d["unknown_criteria"])
        L.append("**Requires expert / functional / clinical review "
                 "(never auto-applied):** %s"
                 % ", ".join(c["code"] for c in d["requires_expert_review"]))
        L.append("")
    return "\n".join(L) + "\n"


def main(argv=None):
    # type: (Optional[List[str]]) -> int
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", required=True,
                   help="Annotated variants: VEP TSV/CSV or JSON list.")
    p.add_argument("--out-json", default="acmg_dossier.json")
    p.add_argument("--out-md", default="acmg_dossier_report.md")
    p.add_argument("--max-credible-af", type=float, default=None,
                   help="Gene/disease-specific max credible AF for BS1 "
                        "(Whiffin 2017). If omitted, a generic default is used.")
    args = p.parse_args(argv)

    if not os.path.exists(args.input):
        sys.stderr.write("HONEST-FAIL: input file not found: %s\n" % args.input)
        return 2

    try:
        variants = load_variants(args.input)
    except Exception as e:  # noqa: BLE001
        sys.stderr.write("HONEST-FAIL: could not parse input (%s): %s\n"
                         % (args.input, e))
        return 2

    if not variants:
        sys.stderr.write("HONEST-FAIL: no variants found in input -- refusing "
                         "to emit a dossier from nothing.\n")
        return 3

    dossier = build(variants, max_credible_af=args.max_credible_af)

    if dossier["n_evaluated"] == 0:
        # Every variant lacked usable evidence. Emit the error record but fail.
        with open(args.out_json, "w") as fh:
            json.dump(dossier, fh, indent=2)
        sys.stderr.write(
            "HONEST-FAIL: none of the %d variants had usable evidence "
            "(gnomAD AF / in-silico predictor / consequence). No classification "
            "emitted. Required annotation sources appear to be missing -- run "
            "the vep_annotation subworkflow with gnomAD + a predictor plugin.\n"
            % dossier["n_variants"])
        return 4

    with open(args.out_json, "w") as fh:
        json.dump(dossier, fh, indent=2)
    with open(args.out_md, "w") as fh:
        fh.write(render_markdown(dossier))

    sys.stderr.write("Wrote %s and %s (%d/%d variants evaluated).\n"
                     % (args.out_json, args.out_md,
                        dossier["n_evaluated"], dossier["n_variants"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
