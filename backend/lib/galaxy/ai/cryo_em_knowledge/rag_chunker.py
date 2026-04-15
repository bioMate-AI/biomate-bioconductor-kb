"""
rag_chunker.py — Structural chunker for cryo-EM skill documents.

Design principles
=================
1.  Context-prepended: every chunk carries a header with document-level
    metadata (sample class, MW, pixel size, section path).  The chunk is
    self-contained — it can be injected into a prompt without surrounding
    context and still make sense.

2.  Structure-respecting: chunk boundaries follow markdown headings (##, ###).
    Tables, key-principle bullets, and failure-mode/solution pairs are NEVER
    split across chunk boundaries.

3.  Typed: each chunk gets a chunk_type that retrieval can use to bias
    results toward what the user actually needs
    (failure_mode for "something went wrong", parameter_table for
    "what value should I use", key_principle for general advice, etc.)

4.  Entity-tagged: key nouns (protein names, tool names, numeric params,
    technique names) are extracted into a metadata field, making them
    findable even when exact string is absent from chunk body.

Chunk structure
===============
    [Source: 01_MFSD2B_preprint.md | Sample: saposin_nanodisc | MW: ~45 kDa | Pixel: 0.649 Å/pix]
    [Section: Sample Preparation > Reconstitution > Troubleshooting]
    [Type: failure_mode | Entities: saposin, His-tag, Bio-Beads, SEC, aggregation]

    Problem: Nanodisc assembly produced aggregates at SEC void volume.
    Root cause: N-terminal His-tag blocked saposin A hydrophobic groove.
    Fix: Switch to C-terminal His-tag. Yield +3x.

full_text = context_header + "\n\n" + body  → embedded together
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Optional

# ---------------------------------------------------------------------------
# Chunk type taxonomy
# ---------------------------------------------------------------------------

CHUNK_TYPES = {
    "decision_tree",      # 00_GENERAL_FRAMEWORK branches
    "reconstitution",     # sample preparation / nanodisc / liposome protocols
    "collection_params",  # microscope / collection parameters
    "parameter_table",    # explicit parameter tables
    "qc_gate",            # quality control checkpoints
    "failure_mode",       # what went wrong + fix
    "processing",         # data processing pipeline steps
    "key_principle",      # top-level "always do this" rules
    "limitation",         # what the protocol can't handle
    "gap_analysis",       # BioMate capability gaps
    "study_design",       # hypothesis, why this experiment
    "model_building",     # Coot, PHENIX, restraints
    "general",            # fallback
}

# Section heading → chunk type heuristics
_HEADING_TYPE_MAP = [
    (re.compile(r"key.?principle|learnable.?rule|important.?rule", re.I), "key_principle"),
    (re.compile(r"limitation|caveat|not.?work|constraint", re.I),          "limitation"),
    (re.compile(r"troubleshoot|fail|went.?wrong|problem|error|debug", re.I), "failure_mode"),
    (re.compile(r"gap.?analys|biomate.?gap|missing|todo|need.?to.?add", re.I), "gap_analysis"),
    (re.compile(r"collection.?param|acquisition|microscopy.?param", re.I), "collection_params"),
    (re.compile(r"reconstitut|nanodis|liposom|detergent|sample.?prep", re.I), "reconstitution"),
    (re.compile(r"qc.?gate|quality.?control|validation|check", re.I),     "qc_gate"),
    (re.compile(r"processing|pipeline|workflow|software", re.I),           "processing"),
    (re.compile(r"model.?build|coot|phenix|refine|restraint", re.I),       "model_building"),
    (re.compile(r"design|hypothesis|overview|background|introduc", re.I),  "study_design"),
    (re.compile(r"parameter.?table|table.*param|param.*table", re.I),      "parameter_table"),
    (re.compile(r"decision.?tree|protocol.?generat|framework", re.I),      "decision_tree"),
]

# ---------------------------------------------------------------------------
# Entity extraction patterns
# ---------------------------------------------------------------------------
_ENTITY_PATTERNS = [
    # Protein / complex names
    re.compile(r"\b(MFSD2B|VMAT2|CaV1\.2|BAX|muOR|mu-OR|D1R|spliceosome|HBSV|HFTV1|"
               r"GPCR|Gi|Gs|Gq|G protein|saposin|MSP1D1|MSP\w+|scFv16|apyrase)\b"),
    # Tools
    re.compile(r"\b(CryoSPARC|RELION|TOPAZ|crYOLO|CTFFIND4|MotionCor2|DeepEMhancer|"
               r"Coot|PHENIX|ISOLDE|AlphaFold|DiffDock|Vina|GROMACS|AMBER|"
               r"IMOD|AreTomo|Dynamo|STOPGAP)\b"),
    # Techniques
    re.compile(r"\b(NS-EM|cryo-ET|SPA|3DVA|NUR|subtomogram|FIB|FSC|CTF|"
               r"ANTS|DPX|BRET|cAMP|radioactive.transport)\b", re.I),
    # Numeric parameters
    re.compile(r"\b(0\.\d+ Å|0\.\d+\s*A/pix|\d+\s*kDa|\d+\s*e-/Å²|"
               r"\d+\s*e.{0,3}/A|[+-]\d+\.\d+\s*μm)\b", re.I),
    # Lipids / reagents
    re.compile(r"\b(GDN|DDM|LMNG|POPC|POPE|cardiolipin|CL|Bio-Beads|"
               r"gamma-cyclodextrin|gamma.CD|SEC|Superdex)\b", re.I),
]

# ---------------------------------------------------------------------------
# Document-level metadata extraction
# ---------------------------------------------------------------------------

_MW_RE    = re.compile(r"(\d+[\–\-]\d+|\d+)\s*kDa", re.I)
_PIXEL_RE = re.compile(r"(0\.\d+)\s*[ÅA]/pix", re.I)
_YEAR_RE  = re.compile(r"\b(20\d{2})\b")
_LAB_RE   = re.compile(r"\b(Lee|Yan|Shi|Xu)\s+lab\b", re.I)


def _extract_doc_metadata(text: str, filename: str) -> dict:
    """Extract document-level facts from the first ~100 lines."""
    header_text = "\n".join(text.splitlines()[:100])

    mw_match = _MW_RE.search(header_text)
    px_match = _PIXEL_RE.search(header_text)
    yr_match = _YEAR_RE.search(header_text)
    lab_match = _LAB_RE.search(header_text)

    return {
        "mw_kda":     mw_match.group(0) if mw_match else None,
        "pixel_size": px_match.group(1) if px_match else None,
        "year":       yr_match.group(1) if yr_match else None,
        "lab":        lab_match.group(1) if lab_match else None,
    }


def _extract_entities(text: str) -> list[str]:
    seen = set()
    for pat in _ENTITY_PATTERNS:
        for m in pat.finditer(text):
            e = m.group(0).strip()
            if e and e not in seen:
                seen.add(e)
    return sorted(seen)[:12]  # cap at 12 entities per chunk


def _infer_type(section_path: list[str]) -> str:
    for heading in reversed(section_path):
        for pat, typ in _HEADING_TYPE_MAP:
            if pat.search(heading):
                return typ
    return "general"


# ---------------------------------------------------------------------------
# Table detection
# ---------------------------------------------------------------------------

def _is_table_line(line: str) -> bool:
    return bool(re.match(r"\s*\|", line))


def _table_block(lines: list[str], start: int) -> int:
    """Return end index (exclusive) of a markdown table starting at start."""
    i = start
    while i < len(lines) and (_is_table_line(lines[i]) or
          (lines[i].strip() == "" and i + 1 < len(lines) and _is_table_line(lines[i+1]))):
        i += 1
    return i


# ---------------------------------------------------------------------------
# Failure-mode block detection
# ---------------------------------------------------------------------------
# A failure-mode block starts with a "Problem:" / "Issue:" / "Root cause:"
# or a bullet that mentions failure, and ends at the next blank line after
# at least one "Fix:" / "Solution:" line.

_FAIL_START = re.compile(r"^(Problem|Issue|Root cause|Failure|Error|Warning):", re.I)
_FAIL_FIX   = re.compile(r"^(Fix|Solution|Resolved|How to fix|Work.?around):", re.I)


def _is_fail_block_start(line: str) -> bool:
    return bool(_FAIL_START.match(line.strip()))


# ---------------------------------------------------------------------------
# Key-principle detection
# ---------------------------------------------------------------------------

def _is_principle_start(line: str) -> bool:
    return bool(re.match(r"[-*•]\s*\*{0,2}(Always|Never|Must|Critical|Warning|Note|Key|Mandatory)", line.strip(), re.I))


# ---------------------------------------------------------------------------
# Core chunker
# ---------------------------------------------------------------------------

MAX_BODY_CHARS  = 1600   # ~400 tokens of body text
MIN_BODY_CHARS  = 80
OVERLAP_LINES   = 3


@dataclass
class Chunk:
    source_file:   str
    section_path:  list[str]
    sample_class:  str
    chunk_type:    str
    chunk_index:   int
    chunk_body:    str
    context_header: str = ""
    full_text:     str = ""
    entities:      list[str] = field(default_factory=list)
    char_count:    int = 0

    def finalise(self, doc_meta: dict) -> None:
        """Build context_header and full_text."""
        parts = [f"[Source: {self.source_file}]"]

        sc_part = f"Sample: {self.sample_class}"
        if doc_meta.get("mw_kda"):
            sc_part += f" | MW: {doc_meta['mw_kda']}"
        if doc_meta.get("pixel_size"):
            sc_part += f" | Pixel: {doc_meta['pixel_size']} Å/pix"
        if doc_meta.get("lab"):
            sc_part += f" | Lab: {doc_meta['lab']}"
        parts.append(f"[{sc_part}]")

        if self.section_path:
            parts.append(f"[Section: {' > '.join(self.section_path)}]")

        entity_str = ", ".join(self.entities[:8]) if self.entities else ""
        type_str   = f"Type: {self.chunk_type}"
        if entity_str:
            type_str += f" | Entities: {entity_str}"
        parts.append(f"[{type_str}]")

        self.context_header = "\n".join(parts)
        self.full_text      = self.context_header + "\n\n" + self.chunk_body
        self.char_count     = len(self.full_text)


def _emit(body_lines: list[str], section_path: list[str], source_file: str,
          sample_class: str, chunk_index: int, doc_meta: dict) -> Optional[Chunk]:
    body = "\n".join(body_lines).strip()
    if len(body) < MIN_BODY_CHARS:
        return None
    chunk_type = _infer_type(section_path)
    entities   = _extract_entities(body)
    c = Chunk(
        source_file=source_file,
        section_path=list(section_path),
        sample_class=sample_class,
        chunk_type=chunk_type,
        chunk_index=chunk_index,
        chunk_body=body,
        entities=entities,
    )
    c.finalise(doc_meta)
    return c


def chunk_document(
    text: str,
    source_file: str,
    sample_class: str,
) -> list[Chunk]:
    """
    Parse and chunk a markdown skill document into context-prepended chunks.

    Chunk boundary rules (in priority order):
      1. Never split a markdown table
      2. Never split a failure-mode / solution pair
      3. Never split a key-principle bullet block
      4. Split at ## headings (level-2 = topic boundary)
      5. Split at ### headings (level-3 = subtopic boundary)
      6. Size-based split when body > MAX_BODY_CHARS
         — split at the nearest blank line before the limit

    Context header is prepended to every chunk.
    """
    lines = text.splitlines()
    doc_meta = _extract_doc_metadata(text, source_file)

    chunks: list[Chunk] = []
    section_stack: list[str] = []   # [h2, h3, ...]
    current_lines: list[str] = []
    chunk_index = 0
    i = 0

    def flush(overlap: bool = False) -> list[str]:
        nonlocal chunk_index
        c = _emit(current_lines, section_stack, source_file,
                  sample_class, chunk_index, doc_meta)
        if c:
            chunks.append(c)
            chunk_index += 1
        tail = current_lines[-OVERLAP_LINES:] if overlap and current_lines else []
        return tail

    while i < len(lines):
        line = lines[i]

        # ── Heading detection ──────────────────────────────────────────────
        h2 = re.match(r"^##\s+(.+)", line)
        h3 = re.match(r"^###\s+(.+)", line)
        h4 = re.match(r"^####\s+(.+)", line)

        if h2:
            current_lines = flush(overlap=False)
            section_stack = [h2.group(1).strip()]
            current_lines.append(line)
            i += 1
            continue

        if h3:
            # Only flush if accumulated body is non-trivial
            if len("\n".join(current_lines)) > MIN_BODY_CHARS * 2:
                current_lines = flush(overlap=True)
            section_stack = section_stack[:1] + [h3.group(1).strip()]
            current_lines.append(line)
            i += 1
            continue

        if h4:
            # h4 folds into section_stack[2]
            if len("\n".join(current_lines)) > MIN_BODY_CHARS * 2:
                current_lines = flush(overlap=True)
            section_stack = section_stack[:2] + [h4.group(1).strip()]
            current_lines.append(line)
            i += 1
            continue

        # ── Table: consume whole table as a unit ──────────────────────────
        if _is_table_line(line):
            end = _table_block(lines, i)
            table_lines = lines[i:end]
            # If table fits in current chunk, append; else flush first
            if len("\n".join(current_lines + table_lines)) > MAX_BODY_CHARS:
                if current_lines:
                    current_lines = flush(overlap=False)
            current_lines.extend(table_lines)
            i = end
            continue

        # ── Key-principle bullet: keep full bullet paragraph together ──────
        if _is_principle_start(line):
            # Collect contiguous bullet lines (including wrapped continuations)
            bullet_lines = [line]
            j = i + 1
            while j < len(lines) and lines[j].strip() and not re.match(r"^#{1,4}\s", lines[j]):
                bullet_lines.append(lines[j])
                j += 1
            if len("\n".join(current_lines + bullet_lines)) > MAX_BODY_CHARS:
                current_lines = flush(overlap=False)
            current_lines.extend(bullet_lines)
            i = j
            continue

        # ── Failure-mode block: keep problem + fix together ───────────────
        if _is_fail_block_start(line):
            # Collect until blank line after a Fix: line
            fail_lines = [line]
            found_fix  = False
            j = i + 1
            while j < len(lines):
                fl = lines[j]
                if _FAIL_FIX.match(fl.strip()):
                    found_fix = True
                fail_lines.append(fl)
                if found_fix and fl.strip() == "":
                    break
                j += 1
            # If block is large, flush first
            if len("\n".join(current_lines + fail_lines)) > MAX_BODY_CHARS:
                current_lines = flush(overlap=False)
            current_lines.extend(fail_lines)
            i = j + 1
            continue

        # ── Size-based split ───────────────────────────────────────────────
        current_lines.append(line)
        if len("\n".join(current_lines)) > MAX_BODY_CHARS:
            # Split at nearest preceding blank line
            split_at = len(current_lines) - 1
            for k in range(len(current_lines) - 1, max(OVERLAP_LINES, 0), -1):
                if current_lines[k].strip() == "":
                    split_at = k
                    break
            tail_lines = current_lines[split_at:]
            current_lines = current_lines[:split_at]
            flush_tail = flush(overlap=False)
            current_lines = flush_tail + tail_lines

        i += 1

    # Final flush
    flush(overlap=False)

    return chunks


# ---------------------------------------------------------------------------
# 00_GENERAL_FRAMEWORK special treatment
# ---------------------------------------------------------------------------

def chunk_general_framework(text: str, source_file: str) -> list[Chunk]:
    """
    The general framework doc needs tighter chunking:
    - Each decision-tree branch → one chunk (type=decision_tree)
    - Each parameter table → one chunk (type=parameter_table)
    - Each QC gate section → one chunk (type=qc_gate)
    """
    doc_meta = _extract_doc_metadata(text, source_file)
    # Runs through the same structural chunker but overrides sample_class
    # to "general" and forces decision_tree type for framework sections.
    chunks = chunk_document(text, source_file, sample_class="general")
    # Re-type chunks that belong to decision-tree sections
    for c in chunks:
        joined = " ".join(c.section_path).lower()
        if any(kw in joined for kw in ["decision", "framework", "protocol gen", "branch", "when to use"]):
            c.chunk_type = "decision_tree"
            c.finalise(doc_meta)
    return chunks


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def chunk_file(filepath: str, sample_class: str) -> list[Chunk]:
    """Chunk a single markdown file."""
    from pathlib import Path
    text = Path(filepath).read_text(encoding="utf-8")
    source_file = Path(filepath).name

    if "00_GENERAL_FRAMEWORK" in source_file:
        return chunk_general_framework(text, source_file)
    return chunk_document(text, source_file, sample_class)


def chunk_all_docs(docs_dir: str, file_sample_class_map: dict[str, str]) -> list[Chunk]:
    """Chunk all markdown files in docs_dir."""
    from pathlib import Path
    all_chunks = []
    for md_file in sorted(Path(docs_dir).glob("*.md")):
        if md_file.stem == "00_INDEX":
            continue
        stem_key = next((k for k in file_sample_class_map if k in md_file.stem), None)
        sc = file_sample_class_map.get(stem_key, "general") if stem_key else "general"
        chunks = chunk_file(str(md_file), sc)
        all_chunks.extend(chunks)
    return all_chunks


# ---------------------------------------------------------------------------
# Quick test
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import sys, json
    from pathlib import Path

    DOCS = "/home/yzhang/biomate/docs/cryo_em_skills"
    FILE_TO_SC = {
        "00_GENERAL_FRAMEWORK": "general",
        "01_MFSD2B_preprint":   "saposin_nanodisc",
        "02_VMAT2_nature2023":  "saposin_nanodisc",
        "03_CaV1_2_cell2023":   "detergent_ion_channel",
        "04_BAX_pore_science2025": "liposome_pore_forming",
        "05_muOR_cell2022":     "msp_nanodisc_gpcr",
        "06_D1_PAM_preprint2025": "msp_nanodisc_gpcr",
        "07_spliceosome_multistate": "rna_protein_endogenous",
        "08_symmetric_assembly_capsid": "symmetric_assembly",
    }

    chunks = chunk_all_docs(DOCS, FILE_TO_SC)

    # Stats
    by_file: dict[str, int] = {}
    by_type: dict[str, int] = {}
    for c in chunks:
        by_file[c.source_file] = by_file.get(c.source_file, 0) + 1
        by_type[c.chunk_type]  = by_type.get(c.chunk_type, 0) + 1

    print(f"Total chunks: {len(chunks)}")
    print("\nBy file:")
    for f, n in sorted(by_file.items()):
        print(f"  {f:45s}  {n:3d}")
    print("\nBy type:")
    for t, n in sorted(by_type.items(), key=lambda x: -x[1]):
        print(f"  {t:25s}  {n:3d}")

    # Show a sample chunk from each type
    shown = set()
    print("\n--- Sample chunks ---")
    for c in chunks:
        if c.chunk_type not in shown:
            shown.add(c.chunk_type)
            print(f"\n[{c.chunk_type.upper()}]")
            print(c.full_text[:500])
            print("---")
