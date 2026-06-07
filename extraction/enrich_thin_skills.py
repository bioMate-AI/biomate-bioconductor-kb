#!/usr/bin/env python3
"""
Enrich thin auto-generated SKILL.md files via Gemini 3 Pro — BATCHED + PARALLEL.

For each SKILL.md under SIZE_THRESHOLD bytes:
  1. Bundle BATCH_SIZE packages into a single Gemini prompt with
     unambiguous delimiters around each package's context.
  2. Parse the multi-skill response, validate each per-skill output, and
     write back to the matching SKILL.md.

Batched calls cut wall time + per-call overhead; parallel workers cut
total time further.

Math (default settings, 100-package bundle): ~20 thin × 5 per batch × 8 workers
    → ~4 batches, ~30-60s per batch
    → wall time ≈ 2-5 min, cost ≈ $1-2.
"""
from __future__ import annotations

import json
import os
import re
import sqlite3
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, UTC
from pathlib import Path
from typing import Any

REPO = Path(__file__).parent.parent
SKILLS_ROOT = REPO / "skills"
AUDIT_PATH = REPO / "docs" / "enrich_audit.json"
PROD_DB = REPO / "galaxy_ai_tools.db"

SIZE_THRESHOLD = int(os.environ.get("ENRICH_SIZE_THRESHOLD", 1500))
BATCH_SIZE     = int(os.environ.get("ENRICH_BATCH_SIZE", 5))
MAX_WORKERS    = int(os.environ.get("ENRICH_WORKERS", 8))
MAX_CTX_PER_SKILL = 4000        # truncate scientific_context per skill in batch

# Complexity-aware routing:
#   - The enrichment task is "rewrite a structured SKILL.md given the
#     package's vignette/scientific_context/tool_knowledge as facts."
#     That's bounded structured generation — Flash handles it well.
#   - Pro is overkill for the bulk; reserved for retry on validation
#     failure (e.g., the model missed required sections).
#
# Override via env: ENRICH_MODEL=<exact-name>
GEMINI_MODEL_DEFAULT  = os.environ.get("ENRICH_MODEL", "gemini-3.5-flash")
GEMINI_MODEL_FALLBACK = os.environ.get("ENRICH_MODEL_RETRY", "gemini-3-pro-preview")
GEMINI_MODEL_CANDIDATES = [
    GEMINI_MODEL_DEFAULT,
    GEMINI_MODEL_FALLBACK,
    "gemini-3.1-pro-preview",
    "gemini-2.5-pro",
]

EXEC_BLOCKLIST = (
    "docker_image", "biocontainer_url", "nextflow_path",
    "galaxy_tool_id", "biomate_workflow_id", "aws_batch",
    "s3://", "biomate.ai/cloud", "biomate cloud",
)

BATCH_PROMPT_HEADER = """You are a Bioconductor expert curating a public skill library for AI coding agents (Claude Code, OpenAI Codex, Gemini, OpenClaw). I'll give you a BATCH of thin SKILL.md files. Rewrite each into a polished version.

For each package, output a complete SKILL.md following this template (do NOT skip any section):

---
<verbatim YAML frontmatter from input>
---

# <PackageName>

## When to Use
2-5 bullets with concrete analytical scenarios where this package is the right pick. Be specific (sample size, modality, organism, replicate structure, etc.).

## When NOT to Use
2-4 bullets each naming an explicit alternative. Format like: "For X, use Y instead because Z."

## Data Requirements
Bullet list of required input format, structure, minimum size, normalization state.

## Key Parameters
Up to 8 parameters as `- **param_name** (default): guidance`. Only include params a user typically needs to set.

## Best Practices
3-6 bullets of recommended workflow ordering and quality checks.

## Common Pitfalls
3-5 bullets each describing a real failure mode with cause + fix in one sentence.

## Alternatives
3-8 alternative R/Bioconductor packages for the same task, with a 1-clause why-they-differ.

## Citations
- Primary publication (author year, journal)
- 1-2 benchmark/review papers if known

## References
- Homepage: bioconductor.org/packages/<pkg>
- Vignette: bioconductor.org/packages/release/bioc/vignettes/<pkg>

# HARD RULES
- Do NOT mention: docker images, Nextflow pipeline paths, Galaxy tool IDs, AWS Batch, S3 URIs, BioMate Cloud or BioMate execution platform.
- Do NOT promote any platform. This is a public-domain knowledge artifact.
- Preserve the YAML frontmatter EXACTLY as given (same fields, same order, same values).
- Every section MUST have content. No empty sections.
- Target length: 1500-3500 characters per package.

# OUTPUT FORMAT — STRICT
For each package in the batch, emit:

<<<SKILL:{pkg_id}>>>
---
<verbatim frontmatter>
---

# <PackageName>

<sections>
<<<END>>>

The {pkg_id} marker must match the input's id exactly. Output nothing outside the <<<SKILL:...>>>...<<<END>>> blocks. No prose, no commentary, no code fences around the whole thing.

# INPUT BATCH BEGINS BELOW
"""


def _load_pkg_context(pkg_name: str) -> tuple[dict, str]:
    """Pull tool_knowledge + scientific_context from production DB."""
    conn = sqlite3.connect(str(PROD_DB))
    conn.row_factory = sqlite3.Row
    tk = conn.execute(
        "SELECT tool_name, use_cases, limitations, alternatives, "
        "       recommended_parameters, primary_citation, benchmark_papers "
        "FROM tool_knowledge WHERE lower(tool_name)=? LIMIT 1",
        (pkg_name.lower(),),
    ).fetchone()
    tr = conn.execute(
        "SELECT scientific_context FROM tools WHERE lower(name)=? LIMIT 1",
        (pkg_name.lower(),),
    ).fetchone()
    conn.close()
    tk_dict = dict(tk) if tk else {}
    sci_ctx = (tr["scientific_context"] if tr else "") or ""
    if len(sci_ctx) > MAX_CTX_PER_SKILL:
        sci_ctx = sci_ctx[:MAX_CTX_PER_SKILL] + "\n... [truncated]"
    return tk_dict, sci_ctx


def _extract_pkg_name(content: str) -> str | None:
    m = re.search(r"^name:\s*bioconductor-([a-z0-9_.-]+)", content, re.I | re.M)
    if m: return m.group(1)
    m = re.search(r"^# (\S+)\s*$", content, re.M)
    return m.group(1) if m else None


def _call_gemini(prompt: str, model_name: str) -> str:
    import google.generativeai as genai
    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key: raise RuntimeError("GEMINI_API_KEY not set")
    genai.configure(api_key=api_key)
    model = genai.GenerativeModel(model_name)
    resp = model.generate_content(
        prompt,
        generation_config={"max_output_tokens": 16384, "temperature": 0.3},
    )
    return resp.text if hasattr(resp, "text") else ""


def _choose_model() -> str:
    for m in GEMINI_MODEL_CANDIDATES:
        try:
            r = _call_gemini("Reply with only: OK", m)
            if r and "ok" in r.strip().lower():
                return m
        except Exception:
            continue
    raise RuntimeError("No Gemini model worked")


def _validate(out: str) -> tuple[bool, str]:
    if not out or len(out.strip()) < 800:
        return False, f"too short ({len(out.strip())})"
    if not out.lstrip().startswith("---"):
        return False, "no YAML frontmatter"
    lc = out.lower()
    for term in EXEC_BLOCKLIST:
        if term.lower() in lc:
            return False, f"exec-leak: {term!r}"
    sections = ["When to Use", "When NOT to Use", "Data Requirements",
                "Key Parameters", "Best Practices", "Common Pitfalls",
                "Alternatives", "Citations", "References"]
    hits = sum(1 for s in sections if f"## {s}" in out)
    if hits < 5:
        return False, f"only {hits}/9 sections"
    return True, "ok"


def _build_batch_prompt(items: list[dict]) -> str:
    parts = [BATCH_PROMPT_HEADER]
    for it in items:
        parts.append(f"\n<<<INPUT_SKILL:{it['pkg_id']}>>>\n")
        parts.append(it["current"])
        parts.append(f"\n<<<TK_ROW>>>\n{json.dumps(it['tk'], default=str)}\n")
        parts.append(f"<<<SCI_CTX>>>\n{it['sci_ctx']}\n")
        parts.append(f"<<<END_INPUT_SKILL:{it['pkg_id']}>>>\n")
    parts.append("\n# Now produce the rewritten SKILL.md for each package in the batch using the strict output format.\n")
    return "".join(parts)


def _split_batch_output(text: str) -> dict[str, str]:
    """Parse <<<SKILL:id>>> ... <<<END>>> blocks. Return {pkg_id: skill_md}."""
    out: dict[str, str] = {}
    pattern = re.compile(r"<<<SKILL:([a-zA-Z0-9_.-]+)>>>(.*?)<<<END>>>", re.DOTALL)
    for m in pattern.finditer(text):
        pid = m.group(1).strip()
        body = m.group(2).strip()
        if body.startswith("```"):
            body = re.sub(r"^```(?:markdown|md)?\s*", "", body)
            body = re.sub(r"\s*```$", "", body)
        body = body.strip() + "\n"
        out[pid] = body
    return out


def _process_batch(items: list[dict], model: str, attempt: int = 1) -> list[dict[str, Any]]:
    """Run one batch through Gemini and return per-item result rows.

    Complexity routing: on validation failure (missing sections, exec-leak,
    truncated output), retry the failed items with the bigger Pro model
    one at a time. This means the 80%+ trivial cases pay Flash prices,
    only the hard ones get Pro.
    """
    prompt = _build_batch_prompt(items)
    try:
        raw = _call_gemini(prompt, model)
    except Exception as exc:
        if attempt == 1 and ("429" in str(exc) or "rate" in str(exc).lower() or "timeout" in str(exc).lower()):
            time.sleep(8)
            return _process_batch(items, model, attempt=2)
        return [{"pkg": it["pkg_id"], "ok": False, "reason": f"LLM error ({model}): {exc}",
                 "orig_size": it["orig_size"], "new_size": 0, "model_used": model}
                for it in items]

    by_id = _split_batch_output(raw)
    rows: list[dict[str, Any]] = []
    retry_items: list[dict] = []
    for it in items:
        body = by_id.get(it["pkg_id"], "")
        if not body:
            retry_items.append(it)
            continue
        ok, reason = _validate(body)
        if not ok:
            retry_items.append(it)
            continue
        it["path"].write_text(body)
        rows.append({"pkg": it["pkg_id"], "ok": True, "reason": "enriched",
                     "orig_size": it["orig_size"], "new_size": len(body),
                     "model_used": model})

    # Complexity escalation: retry remaining items one-by-one with the Pro model
    if retry_items and model != GEMINI_MODEL_FALLBACK and attempt == 1:
        for it in retry_items:
            single_rows = _process_batch([it], GEMINI_MODEL_FALLBACK, attempt=2)
            rows.extend(single_rows)
    else:
        for it in retry_items:
            body = by_id.get(it["pkg_id"], "")
            ok, reason = _validate(body) if body else (False, "missing in batch response")
            rows.append({"pkg": it["pkg_id"], "ok": False, "reason": reason,
                         "orig_size": it["orig_size"], "new_size": len(body),
                         "model_used": model,
                         "preview": (body or "")[:200]})
    return rows


def main() -> int:
    print(f"[enrich] threshold={SIZE_THRESHOLD}c batch={BATCH_SIZE} workers={MAX_WORKERS}")
    # Collect thin files + their context
    items_all: list[dict] = []
    for p in sorted(SKILLS_ROOT.rglob("SKILL.md")):
        if p.stat().st_size < SIZE_THRESHOLD:
            text = p.read_text()
            pkg_name = _extract_pkg_name(text)
            if not pkg_name:
                continue
            tk, sci_ctx = _load_pkg_context(pkg_name)
            items_all.append({
                "path": p,
                "pkg_id": pkg_name,
                "current": text,
                "tk": tk,
                "sci_ctx": sci_ctx,
                "orig_size": len(text),
            })
    print(f"[enrich] {len(items_all)} thin SKILL.md to process")
    if not items_all: return 0

    model = _choose_model()
    print(f"[enrich] model: {model}")

    # Chunk into batches
    batches = [items_all[i:i+BATCH_SIZE] for i in range(0, len(items_all), BATCH_SIZE)]
    print(f"[enrich] {len(batches)} batches × {BATCH_SIZE} pkgs each")

    all_results: list[dict] = []
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        future_to_idx = {ex.submit(_process_batch, b, model): i for i, b in enumerate(batches)}
        done = 0
        for fut in as_completed(future_to_idx):
            rows = fut.result()
            all_results.extend(rows)
            done += 1
            ok_in_batch = sum(1 for r in rows if r["ok"])
            print(f"  [batch {done:3d}/{len(batches)}] {ok_in_batch}/{len(rows)} ok",
                  flush=True)

    elapsed = time.time() - t0
    ok = sum(1 for r in all_results if r["ok"])
    print(f"\n[enrich] done in {elapsed/60:.1f} min — ok={ok} failed={len(all_results)-ok}")
    AUDIT_PATH.parent.mkdir(parents=True, exist_ok=True)
    AUDIT_PATH.write_text(json.dumps({
        "ran_at": datetime.now(UTC).isoformat(),
        "model": model,
        "size_threshold": SIZE_THRESHOLD,
        "batch_size": BATCH_SIZE,
        "max_workers": MAX_WORKERS,
        "total": len(items_all),
        "batches": len(batches),
        "ok": ok,
        "failed": len(items_all) - ok,
        "elapsed_minutes": round(elapsed/60, 2),
        "results": all_results,
    }, indent=2, default=str))
    print(f"[enrich] audit → {AUDIT_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
