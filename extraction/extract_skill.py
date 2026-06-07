#!/usr/bin/env python3
"""
Bioconductor SKILL.md extractor — public, knowledge-only.

Produces a single SKILL.md file per package in Anthropic Claude Code Skills
format. Stripped of all execution-level fields (no Docker images, no
Nextflow paths, no Galaxy tool IDs, no AWS/S3 hints, no BioMate-internal
identifiers).

Sources (read-only):
  - tools.scientific_context  : structured per-tool knowledge JSON
  - tool_knowledge.{use_cases, limitations, alternatives,
                    recommended_parameters, primary_citation}
  - tools.{description, edam_operations, edam_topics, parameters, citations}
  - Optionally: bioconductor_tools.db.tools.skill_content (the 23 hand-
    curated SKILL.md bodies) — use verbatim when present.

Output: SKILL.md per package, structured as:

    ---
    name: bioconductor-<pkg-kebab>
    description: <single-line routing description>
    when_to_use: Use when: <positive cases>. Not for: <negative cases>.
    user-invocable: false
    ---

    ## Best Practices
    ## Key Parameters
    ## Result Interpretation
    ## Common Pitfalls
    ## Data Requirements
    ## Alternatives

Usage:
    extract_skill.py --db galaxy_ai_tools.db --skill-db bioconductor_tools.db \\
                     --pkg DESeq2 --out skills/rnaseq-de/deseq2/SKILL.md
"""
from __future__ import annotations
import argparse, json, re, sqlite3, sys
from pathlib import Path

# Fields we NEVER emit publicly — execution-level / BioMate-internal.
EXEC_FIELDS_BLOCKLIST = {
    "docker_image", "biocontainer_url", "biocontainer", "container",
    "nextflow_path", "nextflow_module", "galaxy_tool_id", "galaxy_inputs",
    "galaxy_outputs", "biomate_workflow_id", "biomate_status",
    "aws_batch_queue", "s3_uri", "execution_info", "compute_profile",
    "cpu_hours", "memory_gb", "gpu_required", "executor", "queue",
}

YAML_FRONT_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)


def _short(v) -> str:
    if v is None: return ""
    if isinstance(v, str): return v.strip()
    if isinstance(v, list):
        items = [str(x).strip() for x in v if x]
        return "\n".join(f"- {x}" for x in items) if items else ""
    if isinstance(v, dict):
        # Strip any execution-keyed nested fields
        return json.dumps({k: v[k] for k in v if k not in EXEC_FIELDS_BLOCKLIST},
                          indent=2, ensure_ascii=False)
    return str(v).strip()


def _scrub_skill_body(body: str) -> str:
    """For hand-curated skill_content: strip any inadvertent execution
    hints + the BioMate footer signature."""
    lines = []
    for line in body.splitlines():
        ll = line.lower()
        if any(k in ll for k in (
            "biomate skill generator", "biomate cloud", "biomate.ai",
            "aws batch", "docker image:", "biocontainer:",
            "nextflow_path", "galaxy_tool_id",
        )):
            continue
        lines.append(line)
    return "\n".join(lines).rstrip() + "\n"


def _select_domain(edam_topics: str, name: str) -> str:
    """Coarse-grained domain for folder placement."""
    et = (edam_topics or "").lower()
    n  = (name or "").lower()
    if any(k in n or k in et for k in ("deseq", "edger", "limma", "tximport", "fishpond")):
        return "rnaseq-de"
    if any(k in n or k in et for k in ("seurat", "scran", "scater", "singlecell", "droplet", "batchelor", "fastmnn", "scrna")):
        return "single-cell"
    if any(k in n or k in et for k in ("chip", "diffbind", "atac")):
        return "chip-seq"
    if any(k in n or k in et for k in ("variant", "vcf", "mutationalpatt", "vep")):
        return "variant-calling"
    if any(k in n or k in et for k in ("xcms", "metabolom", "msnbase", "spectra")):
        return "metabolomics"
    if any(k in n or k in et for k in ("msstats", "proteomic", "qfeatures", "depmap", "openms")):
        return "proteomics"
    if any(k in n or k in et for k in ("cluster", "enrich", "gsea", "reactome", "fgsea", "gprofiler")):
        return "enrichment"
    if any(k in n or k in et for k in ("phyloseq", "metagenom", "dada", "ancombc", "aldex")):
        return "metagenomics"
    if any(k in n or k in et for k in ("methylkit", "minfi", "bsseq", "champ", "methylation")):
        return "methylation"
    if any(k in n or k in et for k in ("genomicrange", "rsamtools", "rtracklayer", "iranges", "biostrings", "genomeinfo")):
        return "infrastructure"
    if any(k in n or k in et for k in ("annot", "biomart", "annotationhub", "kegg")):
        return "annotation"
    return "general"


def _kebab(name: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "-", name).strip("-").lower()
    return s


def _flatten_to_line(text: str, max_chars: int) -> str:
    """Collapse bullet lists / newlines to a single line, truncate."""
    text = re.sub(r"\s*\n\s*-\s*", "; ", text)   # "- item\n- item" → "; item; item"
    text = re.sub(r"^-\s*", "", text)              # leading bullet
    text = re.sub(r"\s+", " ", text).strip()
    return text[:max_chars]


def _build_when_to_use(sci_ctx: dict, tk: dict) -> str:
    """Build the when_to_use frontmatter value from structured context.

    Returns a single-line string of the form:
      "Use when: <positive cases>. Not for: <negative cases>."
    Combined with description it must stay under 1,536 chars total.
    """
    sci_ctx = sci_ctx or {}
    tk = tk or {}
    parts = []

    # Positive cases — best_for preferred, use_cases fallback
    best = (sci_ctx.get("tool_selection", {}) or {}).get("best_for")
    if not best and tk.get("use_cases"):
        try: best = json.loads(tk["use_cases"])
        except Exception: best = tk["use_cases"]
    if best:
        best_str = _flatten_to_line(_short(best), 400)
        if best_str:
            parts.append(f"Use when: {best_str}")

    # Negative cases — not_recommended_for preferred, limitations fallback
    nrf = (sci_ctx.get("tool_selection", {}) or {}).get("not_recommended_for")
    if not nrf and tk.get("limitations"):
        try: nrf = json.loads(tk["limitations"])
        except Exception: nrf = tk["limitations"]
    if nrf:
        nrf_str = _flatten_to_line(_short(nrf), 250)
        if nrf_str:
            parts.append(f"Not for: {nrf_str}")

    return ". ".join(parts)


# ---------------------------------------------------------------------------
# Renderers
# ---------------------------------------------------------------------------

def _render_frontmatter(name: str, description: str, when_to_use_text: str = "") -> str:
    """Emit Claude Code-compliant SKILL.md frontmatter.

    Valid fields: name, description, when_to_use, user-invocable.
    No tags, no version — those fields are not recognised by Claude Code.
    Combined description + when_to_use must stay under 1,536 chars.
    """
    desc = (description or "").replace("\n", " ").strip()[:500]
    wtu = (when_to_use_text or "").replace("\n", " ").strip()
    # Enforce combined cap
    remaining = max(0, 1536 - len(desc) - 2)   # -2 for separator chars
    wtu = wtu[:remaining]

    out = "---\n"
    out += f"name: bioconductor-{_kebab(name)}\n"
    out += f"description: {desc}\n"
    if wtu:
        out += f"when_to_use: {wtu}\n"
    out += "user-invocable: false\n"
    out += "---\n\n"
    return out


def _emit_section(title: str, body: str) -> str:
    body = (body or "").strip()
    if not body: return ""
    return f"## {title}\n\n{body}\n\n"


def _render_from_curated(name: str, description: str, skill_body: str) -> str:
    """When we have a hand-curated SKILL.md — rewrap frontmatter to valid
    Claude Code format and scrub any internal hints.

    Extracts the 'When to Use' and 'When NOT to Use' sections from the body
    and condenses them into the when_to_use frontmatter field.
    """
    body = skill_body
    # Strip existing frontmatter (we re-emit fresh)
    m = YAML_FRONT_RE.match(body)
    if m: body = body[m.end():]
    body = _scrub_skill_body(body)

    # Extract "When to Use" and "When NOT to Use" sections for frontmatter
    wtu_parts = []
    wtu_match = re.search(r"##\s+When to Use\s*\n(.*?)(?=\n##|\Z)", body, re.DOTALL)
    if wtu_match:
        text = _flatten_to_line(wtu_match.group(1), 400)
        if text:
            wtu_parts.append(f"Use when: {text}")

    wtn_match = re.search(r"##\s+When NOT to Use\s*\n(.*?)(?=\n##|\Z)", body, re.DOTALL)
    if wtn_match:
        text = _flatten_to_line(wtn_match.group(1), 250)
        if text:
            wtu_parts.append(f"Not for: {text}")

    when_to_use = ". ".join(wtu_parts)
    return _render_frontmatter(name, description, when_to_use) + body


def _render_auto(name: str, description: str, domain: str,
                 sci_ctx: dict, tk: dict) -> str:
    """Build SKILL.md body as Claude instructions (not API reference docs)."""
    sci_ctx = sci_ctx or {}
    tk = tk or {}

    # Build frontmatter
    when_to_use = _build_when_to_use(sci_ctx, tk)
    out = _render_frontmatter(name, description, when_to_use)

    # Body: instructions Claude follows when this skill is invoked.
    # Sections are ordered from most-actionable to most-contextual.

    # Best practices — what Claude should do / tell the user
    bp = sci_ctx.get("best_practices")
    out += _emit_section("Best Practices", _short(bp))

    # Key parameters — what to configure
    kp = (sci_ctx.get("scientific_guidance", {}) or {}).get("key_parameters")
    if not kp and tk.get("recommended_parameters"):
        try: kp = json.loads(tk["recommended_parameters"])
        except Exception: kp = tk["recommended_parameters"]
    out += _emit_section("Key Parameters", _short(kp))

    # Result interpretation — how to read outputs
    ri = (sci_ctx.get("result_interpretation")
          or (sci_ctx.get("scientific_guidance", {}) or {}).get("result_interpretation"))
    out += _emit_section("Result Interpretation", _short(ri))

    # Common pitfalls — what to warn about
    cp = (sci_ctx.get("scientific_guidance", {}) or {}).get("common_pitfalls")
    if not cp: cp = sci_ctx.get("common_pitfalls")
    out += _emit_section("Common Pitfalls", _short(cp))

    # Data requirements — what input format is needed
    dr = sci_ctx.get("data_requirements")
    out += _emit_section("Data Requirements", _short(dr))

    # Alternatives — when to suggest a different tool
    alts = (sci_ctx.get("tool_selection", {}) or {}).get("alternatives")
    if not alts and tk.get("alternatives"):
        try: alts = json.loads(tk["alternatives"])
        except Exception: alts = tk["alternatives"]
    out += _emit_section("Alternatives", _short(alts))

    return out.rstrip() + "\n"


# ---------------------------------------------------------------------------
# Main extractor
# ---------------------------------------------------------------------------

def extract_skill(name: str, prod_db: Path, skill_db: Path | None = None) -> tuple[str, str] | None:
    """Return (domain, skill_md_text) or None if no usable content."""
    conn = sqlite3.connect(str(prod_db))
    conn.row_factory = sqlite3.Row
    # Production tools row
    tool_row = conn.execute(
        "SELECT name, description, scientific_context, edam_operations, edam_topics "
        "FROM tools WHERE lower(name)=? LIMIT 1", (name.lower(),)
    ).fetchone()
    tk_row = conn.execute(
        "SELECT use_cases, limitations, alternatives, recommended_parameters, "
        "       primary_citation, benchmark_papers, review_papers "
        "FROM tool_knowledge WHERE lower(tool_name)=? LIMIT 1", (name.lower(),)
    ).fetchone()
    wf_row = conn.execute(
        "SELECT domain FROM workflows WHERE lower(name)=? AND source='bioconductor' LIMIT 1",
        (name.lower(),),
    ).fetchone()
    conn.close()

    description = (tool_row["description"] if tool_row else "") or ""
    edam_topics = (tool_row["edam_topics"] if tool_row else "") or ""

    # Prefer the production workflows.domain mapping (curated); fall back to
    # the keyword heuristic when the DB has it as "general".
    _WF_TO_FOLDER = {
        "transcriptomics": "transcriptomics",
        "genomics": "genomics",
        "epigenomics": "epigenomics",
        "proteomics": "proteomics",
        "variant_calling": "variant-calling",
        "imaging": "imaging",
        "metagenomics": "metagenomics",
        "single_cell": "single-cell",
        "metabolomics": "metabolomics",
    }
    wf_domain = (wf_row["domain"] if wf_row else "") or ""
    domain = _WF_TO_FOLDER.get(wf_domain) or _select_domain(edam_topics, name)

    # Curated SKILL.md from the skill DB if present
    if skill_db and skill_db.exists():
        s = sqlite3.connect(str(skill_db))
        crow = s.execute("SELECT skill_content FROM tools WHERE lower(name)=? LIMIT 1",
                         (name.lower(),)).fetchone()
        s.close()
        if crow and crow[0] and len(crow[0]) > 500:
            return domain, _render_from_curated(name, description, crow[0])

    # Otherwise auto-generate from structured context
    sci = {}
    if tool_row and tool_row["scientific_context"]:
        try: sci = json.loads(tool_row["scientific_context"])
        except Exception: sci = {}
    tk = dict(tk_row) if tk_row else {}

    # Reject if we'd have basically nothing
    if (not sci) and (not any(tk.get(k) for k in ("use_cases","limitations","alternatives","recommended_parameters"))):
        # Still emit a thin stub so the package is discoverable
        if not description:
            return None
        body = _render_frontmatter(name, description) + f"# {name}\n\n{description}\n"
        return domain, body

    return domain, _render_auto(name, description, domain, sci, tk)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True, type=Path)
    ap.add_argument("--skill-db", type=Path, default=None)
    ap.add_argument("--pkg", required=True)
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()

    r = extract_skill(args.pkg, args.db, args.skill_db)
    if not r:
        print(f"No usable content for {args.pkg}", file=sys.stderr); return 1
    domain, body = r
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(body)
        print(f"[{domain}] {args.pkg} → {args.out} ({len(body)} chars)")
    else:
        print(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
