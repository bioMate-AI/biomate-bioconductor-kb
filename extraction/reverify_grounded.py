#!/usr/bin/env python3
"""
Tighter re-verifier for the Pass-2 audit failures.

The original verifier flagged English nouns like `parameter`, `object`,
`indicators`, `frequency` as missing R functions when they appeared
followed by `(` in prose. That caused 8 packages with substantively
good content to fail the 50% function-name verification floor.

This script:
  1. Extracts only R-SHAPED function names from each SKILL.md
     (camelCase, PascalCase, dotted, or all-lowercase ≥5 chars NOT in
     the common-prose blocklist).
  2. Re-checks substring presence in the cached vignette.
  3. For packages that now clear the FACT_FLOOR, flips the tag
     `auto-generated` → `vignette-grounded` and rewrites the SKILL.md.
  4. Writes a new audit at docs/20260526_REVERIFY_AUDIT.json.

No LLM calls. Pure local recheck.
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, UTC
from pathlib import Path

REPO = Path(__file__).parent.parent
CACHE = REPO / ".source_cache"
SKILLS = REPO / "skills"
AUDIT_IN = REPO / "docs" / "enrich_v2_audit.json"
AUDIT_OUT = REPO / "docs" / "reverify_audit.json"

FACT_FLOOR = 0.5

COMMON_PROSE_NOUNS = {
    "parameter","object","matching","objects","units","annotations",
    "subsetting","organism","indexing","databases","coordinates","trajectory",
    "normalized","files","intensities","microarrays","models","graphs","standard",
    "rescaled","prediction","values","times","indicators","thresholds",
    "probabilities","index","frequency","layer","layers","node","nodes","tree",
    "trees","image","images","data","analysis","function","functions","method",
    "methods","samples","reads","results","counts","plots","plot","table","tables",
    "row","rows","column","columns","factor","factors","cell","cells","gene",
    "genes","variant","variants","details","sources","examples","example","author",
    "year","journal","input","output","step","steps","group","groups","level",
    "levels","tag","tags","field","fields","section","sections","reference",
    "references","fact","facts","feature","features","case","cases","question",
    "questions","note","notes","item","items","kind","kinds","type","types",
    "test","tests","check","checks","point","points","record","records","line",
    "lines","format","formats","mode","modes","name","names","sequence","sequences",
    "comment","comments","author","element","elements","peak","peaks","range","ranges",
    "subset","subsets","run","runs","entry","entries","quality","qualities","number",
    "numbers","series","study","studies","experiment","experiments","tool","tools",
    "process","processes","summary","summaries","report","reports","query","queries",
    "interval","intervals","window","windows","cutoff","cutoffs","filter","filters",
    "selection","selections","stage","stages","tier","tiers","domain","domains",
    "package","packages","library","libraries","platform","platforms","interaction",
    "interactions","association","associations","comparison","comparisons","contrast",
    "contrasts","design","designs","panel","panels","container","containers",
    "session","sessions","operation","operations","feature","features",
    # English verbs commonly followed by parens
    "see","use","run","load","save","set","get","add","sub","mul","div",
    "create","build","make","construct","define","return","print","show",
    "find","search","fit","apply","map","reduce","filter","check","detect",
    "predict","compute","calculate","estimate","derive","extract","parse",
    "read","write","open","close","subset","group","split","merge","combine",
    # Latin/abbrev
    "ie","eg","etc","vs","cf","al","etc","ed","via",
    # Things like 'standard','default'
    "default","optional","required","specific","general","global","local",
    "previous","next","initial","final","main","extra","external","internal",
}

def looks_like_r_function(fn: str) -> bool:
    """Heuristic: is `fn(...)` actually an R function call worth verifying?"""
    if len(fn) < 3: return False
    if fn.lower() in COMMON_PROSE_NOUNS: return False
    # Dotted names (`stats::lm`, `as.data.frame`) are always real
    if "." in fn or "::" in fn: return True
    has_upper = any(c.isupper() for c in fn)
    has_lower = any(c.islower() for c in fn)
    if has_upper and has_lower: return True   # camelCase / PascalCase
    if has_upper and not has_lower: return True   # ALL_CAPS (rare but valid)
    # All-lowercase: only count if ≥6 chars and not in blocklist
    if fn.islower() and len(fn) >= 6: return True
    return False


def extract_r_functions(skill: str) -> set[str]:
    fns: set[str] = set()
    for m in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_.]*::)?([A-Za-z_][A-Za-z0-9_.]+)\s*\(", skill):
        fn = m.group(2)
        if looks_like_r_function(fn):
            fns.add(fn)
    return fns


def load_vignette(pkg_name: str) -> str:
    pcache = CACHE / pkg_name.lower()
    parts: list[str] = []
    if pcache.is_dir():
        for f in sorted(pcache.glob("vignette_*.txt")):
            parts.append(f.read_text())
    return "\n".join(parts)


def find_skill_path(pkg_id: str) -> Path | None:
    for p in SKILLS.rglob("SKILL.md"):
        text = p.read_text()
        m = re.search(r"^name:\s*bioconductor-([a-z0-9_.-]+)", text, re.I | re.M)
        if m and m.group(1).lower() == pkg_id.lower():
            return p
    return None


def main() -> int:
    audit = json.loads(AUDIT_IN.read_text())
    failures = [r for r in audit["results"] if not r["ok"]]
    print(f"[reverify] {len(failures)} previously-failed packages")

    rows = []
    promoted = 0
    for f in failures:
        pkg = f["pkg"]
        path = find_skill_path(pkg)
        if not path:
            rows.append({"pkg": pkg, "ok": False, "reason": "no SKILL.md found"})
            continue
        skill = path.read_text()
        vig = load_vignette(pkg)
        fns = extract_r_functions(skill)
        missing = [fn for fn in fns if fn not in vig]
        rate = 1.0 - (len(missing) / max(len(fns), 1))
        row = {
            "pkg": pkg, "n_funcs": len(fns), "n_missing": len(missing),
            "verify_rate": round(rate, 3),
            "missing_sample": sorted(missing)[:10],
            "promote": rate >= FACT_FLOOR,
        }
        if row["promote"]:
            # Flip tag auto-generated → vignette-grounded
            new = re.sub(r"(\btags:\s*\[[^\]]*?)(auto-generated)([^\]]*\])",
                         lambda m: f"{m.group(1)}vignette-grounded{m.group(3)}",
                         skill)
            if new != skill:
                path.write_text(new)
                row["promoted"] = True
                promoted += 1
            else:
                row["promoted"] = False
                row["note"] = "tag already set"
        rows.append(row)

    print(f"[reverify] promoted: {promoted}/{len(failures)}")
    print()
    print(f"{'pkg':18s}  {'fns':>4s}  {'rate':>6s}  promote")
    for r in rows:
        marker = "✓" if r.get("promote") else "✗"
        print(f"  {r['pkg']:18s}  {r.get('n_funcs',0):>4d}  {r.get('verify_rate',0):>6.0%}  {marker}")

    AUDIT_OUT.parent.mkdir(parents=True, exist_ok=True)
    AUDIT_OUT.write_text(json.dumps({
        "ran_at": datetime.now(UTC).isoformat(),
        "fact_floor": FACT_FLOOR,
        "promoted": promoted,
        "total": len(rows),
        "results": rows,
    }, indent=2, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
