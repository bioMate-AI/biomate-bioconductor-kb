"""
Folder profile — what a project FOLDER holds as a whole, not file by file.

A folder upload is more than a container: ``pairs/`` with ``S1_R1.fastq.gz``,
``S1_R2.fastq.gz`` and ``S2_R1.fastq.gz`` is one paired sample plus an orphan R1, and
``tenx/`` with ``matrix.mtx`` + ``barcodes.tsv`` + ``features.tsv`` is ONE 10x matrix whose
two TSVs are header-less by specification. A per-file profiler cannot see either fact, so
this module profiles the folder from its file names (plus the Matrix Market size line of a
10x matrix, read through a caller-supplied callback):

* **FASTQ pairing reuses Galaxy's own list:paired builder** —
  ``galaxy.model.dataset_collections.auto_pairing.auto_pair`` (the code behind Galaxy's
  "Build list of dataset pairs"). Importing it pulls the whole ``galaxy.model`` package
  (SQLAlchemy, boltons, …), which the Galaxy backend has and a bare laptop does not, so it
  is imported lazily; :func:`_auto_pair_fallback` is a line-for-line port of the same
  algorithm, checked against Galaxy's ``auto_pairing_spec.yml`` cases AND against the
  Galaxy source itself in ``tests/test_folder_profile.py``. ``engine`` in the output says
  which one ran.
* **10x Genomics matrices** follow the Cell Ranger output spec: ``matrix.mtx(.gz)`` +
  ``barcodes.tsv(.gz)`` + ``features.tsv(.gz)`` (v3) or ``genes.tsv(.gz)`` (v2), optionally
  with a common sample prefix (GEO: ``GSM123_matrix.mtx.gz``), one set per directory
  (``filtered_feature_bc_matrix/``, ``raw_feature_bc_matrix/``). Cells × genes come from the
  matrix's size line (rows = features, columns = barcodes).
* Everything else is rolled up by format ("12 files: 8 FASTQ (4 pairs), 2 CSV, 2
  unrecognised").

Findings carry a code + params (rendered by the UI through i18n ``perception.msg.<code>``),
exactly like the per-file profiler. Pure: no I/O except the ``read_head`` callback, no
network, no third-party imports — loadable on its own by file path (unit tests).
"""
from __future__ import annotations

import csv
import io
import logging
import posixpath
import re
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Pairing — Galaxy's auto_pair (lazy) with a faithful pure fallback
# ---------------------------------------------------------------------------
# Same table as galaxy.model.dataset_collections.auto_pairing.COMMON_FILTERS (and the client's
# pairing.ts): filter type → (forward marker, reverse marker).
COMMON_FILTERS: Dict[str, Tuple[str, str]] = {
    "illumina": ("_1", "_2"),
    "Rs": ("_R1", "_R2"),
    "dot12s": (".1.fastq", ".2.fastq"),
}


@dataclass
class _Element:
    """What auto_pair expects (a ``.name``) + the project path it stands for."""

    name: str
    path: str


def _filename_to_element_identifier(filename: str) -> str:
    """Port of galaxy.model.dataset_collections.auto_identifiers.filename_to_element_identifier."""
    basename = posixpath.basename(filename.split("?", 1)[0])
    for zip_extension in [".zip", ".tar.gz", ".tar", ".tgz", ".gz", "bz2", ".bz"]:
        if basename.endswith(zip_extension):
            basename = basename[: -len(zip_extension)]
    if "." in basename:
        basename = basename.split(".")[0]
    return basename


def _guess_initial_filter_type_fallback(elements: Sequence[Any]) -> Optional[str]:
    """Port of auto_pairing.guess_initial_filter_type."""
    illumina = dot12s = rs = 0
    for element in elements:
        if ".1.fastq" in element.name or ".2.fastq" in element.name:
            dot12s += 1
        elif "_R1" in element.name or "_R2" in element.name:
            rs += 1
        elif "_1" in element.name or "_2" in element.name:
            illumina += 1
    if illumina == 0 and dot12s == 0 and rs == 0:
        return None
    if illumina > dot12s and illumina > rs:
        return "illumina"
    if dot12s > illumina and dot12s > rs:
        return "dot12s"
    if rs > illumina and rs > dot12s:
        return "Rs"
    return "illumina"


def _auto_pair_fallback(elements: Sequence[Any]) -> Tuple[List[Tuple[str, Any, Any]], List[Any], Optional[str]]:
    """Port of auto_pairing.auto_pair → (pairs [(name, forward, reverse)], unpaired, filter type)."""
    filter_type = _guess_initial_filter_type_fallback(elements)
    if not filter_type:
        return [], list(elements), None
    fwd_marker, rev_marker = COMMON_FILTERS[filter_type]
    fwd_re, rev_re = re.compile(fwd_marker), re.compile(rev_marker)
    forward = [e for e in elements if e.name and fwd_re.search(e.name)]
    reverse = [e for e in elements if e.name and rev_re.search(e.name)]
    partial: Dict[str, List[Any]] = {}
    for e in forward:
        base = _filename_to_element_identifier(re.sub(fwd_marker, "", e.name))
        partial.setdefault(base, [e, None])
    for e in reverse:
        base = _filename_to_element_identifier(re.sub(rev_marker, "", e.name))
        if base not in partial:
            partial[base] = [None, e]
        else:
            partial[base][1] = e
    unpaired = list(elements)
    for e in forward + reverse:
        if e in unpaired:
            unpaired.remove(e)
    pairs: List[Tuple[str, Any, Any]] = []
    for base, (f, r) in partial.items():
        if f is None:
            unpaired.append(r)
        elif r is None:
            unpaired.append(f)
        else:
            pairs.append((base, f, r))
    return pairs, unpaired, filter_type


_GALAXY_PAIRING: List[Any] = []


def _galaxy_pairing() -> Any:
    """Galaxy's auto_pairing module, or None when galaxy.model cannot import (laptop, tests)."""
    if not _GALAXY_PAIRING:
        try:
            from galaxy.model.dataset_collections import auto_pairing  # heavy: galaxy.model

            _GALAXY_PAIRING.append(auto_pairing)
        except Exception as exc:  # noqa: BLE001 — the fallback is the same algorithm
            log.info("[folder_profile] Galaxy auto_pairing unavailable (%s); using the pure port", exc)
            _GALAXY_PAIRING.append(None)
    return _GALAXY_PAIRING[0]


def auto_pair(elements: Sequence[Any], engine: str = "auto") -> Tuple[List[Tuple[str, Any, Any]], List[Any], Optional[str], str]:
    """Pair ``elements`` (objects with ``.name``) the way Galaxy's list:paired builder does.

    Returns (pairs, unpaired, filter_type, engine) where engine is "galaxy" or "fallback".
    ``engine="fallback"`` forces the pure port (tests).
    """
    mod = _galaxy_pairing() if engine != "fallback" else None
    if mod is not None:
        try:
            filter_type = mod.guess_initial_filter_type(list(elements))
            res = mod.auto_pair(list(elements))
            return ([(p.name, p.forward, p.reverse) for p in res.paired], list(res.unpaired), filter_type, "galaxy")
        except Exception as exc:  # noqa: BLE001 — e.g. a name matching BOTH markers (list.remove twice)
            log.info("[folder_profile] Galaxy auto_pair failed (%s); using the pure port", exc)
    pairs, unpaired, filter_type = _auto_pair_fallback(elements)
    return pairs, unpaired, filter_type, "fallback"


# ---------------------------------------------------------------------------
# Name-level format classification
# ---------------------------------------------------------------------------
_COMPRESSION = (".gz", ".bgz", ".bz2", ".zst")
_FASTQ_EXTS = (".fastq", ".fq", ".fastqsanger")


def _strip_compression(name: str) -> str:
    low = name.lower()
    for suf in _COMPRESSION:
        if low.endswith(suf):
            return name[: -len(suf)]
    return name


def is_fastq_name(name: str) -> bool:
    return _strip_compression(posixpath.basename(name)).lower().endswith(_FASTQ_EXTS)


# Default (Galaxy-free) name → (format key, label). The API layer passes a classifier backed by
# Galaxy's datatype labels (galaxy_formats.filename_exts / label_for) instead.
_DEFAULT_FORMATS: Dict[str, str] = {
    "fastq": "FASTQ", "fq": "FASTQ", "fasta": "FASTA", "fa": "FASTA", "fna": "FASTA", "faa": "FASTA",
    "vcf": "VCF", "bcf": "BCF", "bam": "BAM", "cram": "CRAM", "sam": "SAM", "bai": "BAI", "crai": "CRAI",
    "bed": "BED", "narrowpeak": "narrowPeak", "broadpeak": "broadPeak", "bedgraph": "bedGraph",
    "gtf": "GTF", "gff": "GFF", "gff3": "GFF3", "csv": "CSV", "tsv": "TSV", "tabular": "Tabular",
    "txt": "Text", "json": "JSON", "jsonl": "JSON Lines", "yaml": "YAML", "yml": "YAML", "mtx": "Matrix Market",
    "h5ad": "AnnData (h5ad)", "loom": "Loom", "h5": "HDF5", "rds": "RDS", "xlsx": "Excel (xlsx)",
    "pdb": "PDB", "cif": "mmCIF", "sdf": "SDF", "smi": "SMILES", "mrc": "MRC", "tif": "TIFF", "tiff": "TIFF",
    "png": "PNG", "jpg": "JPEG", "jpeg": "JPEG", "pdf": "PDF", "html": "HTML", "pod5": "POD5",
    "bigwig": "bigWig", "bw": "bigWig", "md5": "Checksum",
}
_FORMAT_ALIASES = {"fq": "fastq", "fastqsanger": "fastq", "fa": "fasta", "fna": "fasta", "faa": "fasta",
                   "yml": "yaml", "tif": "tiff", "bw": "bigwig", "jpeg": "jpg"}


def default_classify(name: str) -> Tuple[str, str]:
    """(format key, label) from the file name; ("unrecognised", "") when the name claims none."""
    base = _strip_compression(posixpath.basename(name)).lower()
    if "." not in base:
        return "unrecognised", ""
    ext = base.rsplit(".", 1)[1]
    if ext not in _DEFAULT_FORMATS:
        return "unrecognised", ""
    return _FORMAT_ALIASES.get(ext, ext), _DEFAULT_FORMATS[ext]


# ---------------------------------------------------------------------------
# 10x Genomics matrix sets (Cell Ranger output spec)
# ---------------------------------------------------------------------------
# <prefix>matrix.mtx(.gz) | <prefix>barcodes.tsv(.gz) | <prefix>features.tsv(.gz) | <prefix>genes.tsv(.gz)
_TENX_PART = re.compile(r"^(?P<prefix>.*?)(?P<part>matrix\.mtx|barcodes\.tsv|features\.tsv|genes\.tsv)(?:\.gz)?$", re.I)
_TENX_ROLE = {"matrix.mtx": "matrix", "barcodes.tsv": "barcodes", "features.tsv": "features", "genes.tsv": "features"}


def _tenx_key(path: str) -> Optional[Tuple[str, str, str, str]]:
    """(directory, prefix, role, part) when the name is a 10x matrix part, else None.
    A prefix must end at a separator ("GSM1_", "S1-", "S1.") so "mygenes.tsv" is not a part."""
    d, base = posixpath.split(path)
    m = _TENX_PART.match(base)
    if not m:
        return None
    prefix = m.group("prefix")
    if prefix and prefix[-1] not in "_-.":
        return None
    part = m.group("part").lower()
    return d, prefix, _TENX_ROLE[part], part


def tenx_sets(paths: Sequence[str]) -> List[Dict[str, Any]]:
    """Group 10x parts by (directory, prefix). A group is a 10x set when it has a matrix plus at
    least one of barcodes / features (a lone ``matrix.mtx`` is just a Matrix Market file)."""
    groups: Dict[Tuple[str, str], Dict[str, Any]] = {}
    for p in paths:
        k = _tenx_key(p)
        if not k:
            continue
        d, prefix, role, part = k
        g = groups.setdefault((d, prefix), {"dir": d, "prefix": prefix})
        if role in g:  # e.g. both features.tsv and genes.tsv — keep the first, it is still a set
            continue
        g[role] = p
        if role == "features":
            g["version"] = "v2" if part == "genes.tsv" else "v3"
    out = []
    for (_d, _p), g in sorted(groups.items()):
        if "matrix" in g and ("barcodes" in g or "features" in g):
            g["complete"] = "barcodes" in g and "features" in g
            g["missing"] = [r for r in ("barcodes", "features") if r not in g]
            out.append(g)
    return out


def parse_mtx_header(text: Optional[str]) -> Optional[Dict[str, Any]]:
    """{rows, cols, nnz, field} from a Matrix Market head (banner + size line), else None."""
    if not text:
        return None
    lines = text.splitlines()
    if not lines or not lines[0].lower().startswith("%%matrixmarket"):
        return None
    banner = lines[0].split()
    for line in lines[1:]:
        s = line.strip()
        if not s or s.startswith("%"):
            continue
        try:
            dims = [int(x) for x in s.split()]
        except ValueError:
            return None
        if len(dims) < 2:
            return None
        return {"rows": dims[0], "cols": dims[1], "nnz": dims[2] if len(dims) > 2 else None,
                "field": banner[3].lower() if len(banner) > 3 else ""}
    return None


# ---------------------------------------------------------------------------
# Folder profile
# ---------------------------------------------------------------------------
def _finding(out: Dict[str, Any], code: str, level: str = "info", **params: Any) -> None:
    out["findings"].append({"code": code, "level": level, "params": params})


def _rel(path: str, folder: str) -> str:
    return path[len(folder) + 1:] if folder and path.startswith(folder + "/") else path


def _fastq_section(fastq_paths: Sequence[str], engine: str = "auto") -> Dict[str, Any]:
    """Pair FASTQs per directory (two runs' S1_R1 never pair across directories)."""
    by_dir: Dict[str, List[_Element]] = {}
    for p in fastq_paths:
        by_dir.setdefault(posixpath.dirname(p), []).append(_Element(name=posixpath.basename(p), path=p))
    samples: List[Dict[str, Any]] = []
    patterns: List[str] = []
    used_engine = None
    for d in sorted(by_dir):
        elements = by_dir[d]
        pairs, unpaired, filter_type, used_engine = auto_pair(elements, engine)
        if filter_type and filter_type not in patterns:
            patterns.append(filter_type)
        markers = COMMON_FILTERS.get(filter_type or "", None)
        for name, f, r in pairs:
            samples.append({"sample": name, "forward": f.path, "reverse": r.path, "status": "paired", "dir": d})
        for e in unpaired:
            role = None
            sample = _filename_to_element_identifier(e.name)
            if markers:
                if re.search(markers[0], e.name):
                    role = "forward"
                    sample = _filename_to_element_identifier(re.sub(markers[0], "", e.name))
                elif re.search(markers[1], e.name):
                    role = "reverse"
                    sample = _filename_to_element_identifier(re.sub(markers[1], "", e.name))
            samples.append({
                "sample": sample, "forward": e.path if role != "reverse" else None,
                "reverse": e.path if role == "reverse" else None,
                "status": "orphan" if role else "single", "role": role, "dir": d,
            })
    samples.sort(key=lambda s: (s["sample"], s["dir"], s["forward"] or s["reverse"] or ""))
    n_pairs = sum(1 for s in samples if s["status"] == "paired")
    orphans = [s for s in samples if s["status"] == "orphan"]
    singles = [s for s in samples if s["status"] == "single"]
    if n_pairs and not orphans and not singles:
        verdict = "paired"
    elif n_pairs:
        verdict = "mixed"
    else:
        verdict = "single_end"
    return {
        "verdict": verdict,
        "pattern": patterns[0] if len(patterns) == 1 else (patterns or [None])[0],
        "engine": used_engine or ("fallback" if engine == "fallback" else "galaxy"),
        "pairs": n_pairs,
        "samples": samples,
        "orphans": [s["forward"] or s["reverse"] for s in orphans],
        "singles": [s["forward"] for s in singles],
    }


def samplesheet(samples: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    """nf-core style samplesheet (sample,fastq_1,fastq_2): one row per sample/run; single-end and
    orphan rows leave fastq_2 empty (a lone R2 becomes that row's fastq_1). Paths are the project
    file paths. Spaces in sample names become "_" (nf-core rejects them)."""
    rows = []
    for s in samples:
        fq1 = s.get("forward") or s.get("reverse") or ""
        fq2 = s.get("reverse") if s.get("forward") else ""
        rows.append([re.sub(r"\s+", "_", str(s["sample"])), fq1, fq2 or ""])
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(["sample", "fastq_1", "fastq_2"])
    w.writerows(rows)
    return {"columns": ["sample", "fastq_1", "fastq_2"], "rows": rows, "csv": buf.getvalue(),
            "filename": "samplesheet.csv"}


_PATTERN_LABEL = {"Rs": "_R1/_R2", "illumina": "_1/_2", "dot12s": ".1.fastq/.2.fastq"}


def profile_folder(
    folder: str,
    names: Sequence[str],
    *,
    read_head: Optional[Callable[[str], Optional[str]]] = None,
    classify: Callable[[str], Tuple[str, str]] = default_classify,
    engine: str = "auto",
) -> Dict[str, Any]:
    """Profile the folder ``folder`` ("" = the project's input root) holding ``names`` (project
    file paths, every file below the folder, any depth).

    ``read_head(path)`` returns the first few KB of a file as text (decompressed) or None; it is
    only called for the matrix of each 10x set. Returns the JSON shape the UI consumes.
    """
    folder = folder.strip("/")
    paths = sorted({n for n in names if n})
    out: Dict[str, Any] = {"path": folder, "fileCount": len(paths), "kind": "empty", "rollup": [], "findings": []}
    if not paths:
        _finding(out, "folder_empty")
        return out

    fastqs = [p for p in paths if is_fastq_name(p)]
    sets = tenx_sets(paths)
    in_set = {s[r] for s in sets for r in ("matrix", "barcodes", "features") if r in s}

    # Format roll-up (FASTQ carries its pair count).
    counts: Dict[str, Dict[str, Any]] = {}
    for p in paths:
        key, label = ("fastq", "FASTQ") if p in fastqs else classify(p)
        c = counts.setdefault(key, {"format": key, "label": label, "count": 0})
        c["count"] += 1

    if fastqs:
        fq = _fastq_section(fastqs, engine)
        out["fastq"] = fq
        out["samplesheet"] = samplesheet(fq["samples"])
        counts["fastq"]["pairs"] = fq["pairs"]
        pattern = _PATTERN_LABEL.get(fq["pattern"] or "", "")
        if fq["pairs"]:
            _finding(out, "folder_fastq_pairs", pairs=fq["pairs"], pattern=pattern)
        for s in fq["samples"]:
            if s["status"] == "orphan":
                name = posixpath.basename(s["forward"] or s["reverse"])
                missing = "R2" if s["role"] == "forward" else "R1"
                if fq["pattern"] == "illumina":
                    missing = "_2" if s["role"] == "forward" else "_1"
                elif fq["pattern"] == "dot12s":
                    missing = ".2.fastq" if s["role"] == "forward" else ".1.fastq"
                _finding(out, "folder_fastq_orphan", "watch", name=name, sample=s["sample"], missing=missing)
        if fq["singles"] and not fq["pairs"] and not fq["orphans"]:
            _finding(out, "folder_fastq_single_end", n=len(fq["singles"]))
        if fq["verdict"] == "mixed":
            _finding(out, "folder_fastq_mixed_layout", "watch", pairs=fq["pairs"],
                     unpaired=len(fq["orphans"]) + len(fq["singles"]))
        runs: Dict[str, int] = {}
        for s in fq["samples"]:
            runs[s["sample"]] = runs.get(s["sample"], 0) + 1
        for sample, n in sorted(runs.items()):
            if n > 1:
                _finding(out, "folder_fastq_sample_runs", sample=sample, n=n)
        _finding(out, "folder_samplesheet", rows=len(out["samplesheet"]["rows"]))

    if sets:
        tenx = []
        for s in sets:
            rec = {k: s.get(k) for k in ("dir", "prefix", "matrix", "barcodes", "features", "version", "complete", "missing")}
            rec["dir"] = _rel(rec["dir"], folder) if rec["dir"] != folder else ""
            head = None
            if read_head is not None:
                try:
                    head = read_head(s["matrix"])
                except Exception as exc:  # noqa: BLE001 — an unreadable head is a finding, not a crash
                    log.info("[folder_profile] mtx head read failed for %s: %s", s["matrix"], exc)
            dims = parse_mtx_header(head)
            if dims:
                rec.update(genes=dims["rows"], cells=dims["cols"], nnz=dims["nnz"])
                _finding(out, "folder_tenx_recognised", cells=dims["cols"], genes=dims["rows"],
                         nnz=dims["nnz"] if dims["nnz"] is not None else "—", version=rec.get("version") or "",
                         dir=rec["dir"] or ".")
            else:
                _finding(out, "folder_tenx_recognised_nodims", version=rec.get("version") or "", dir=rec["dir"] or ".")
                if read_head is not None:
                    _finding(out, "folder_tenx_mtx_unreadable", "watch", name=posixpath.basename(s["matrix"]))
            if not s["complete"]:
                _finding(out, "folder_tenx_incomplete", "watch", dir=rec["dir"] or ".",
                         missing=", ".join(s["missing"]))
            tenx.append(rec)
        out["tenx"] = {"sets": tenx}
        _finding(out, "folder_tenx_headerless")

    if sets and not fastqs:
        out["kind"] = "tenx_matrix"
    elif fastqs and len(fastqs) == len(paths):
        out["kind"] = "fastq_set"
    else:
        out["kind"] = "mixed"
    out["rollup"] = sorted(counts.values(), key=lambda c: (c["format"] == "unrecognised", -c["count"], c["label"]))
    out["tenxFiles"] = sorted(in_set)
    return out


# ---------------------------------------------------------------------------
# Per-file context: what the folder says about ONE file (used by the per-file profiler)
# ---------------------------------------------------------------------------
def fastq_layout(name: str, siblings: Sequence[str]) -> Optional[Dict[str, Any]]:
    """For a FASTQ ``name`` and the other files of its directory: {status, sample, role, mate,
    pattern} — status "paired" | "orphan" | "single". None when ``name`` is not a FASTQ."""
    if not is_fastq_name(name):
        return None
    d = posixpath.dirname(name)
    same_dir = [s for s in siblings if s != name and posixpath.dirname(s) == d and is_fastq_name(s)]
    fq = _fastq_section([name] + same_dir)
    for s in fq["samples"]:
        if name in (s["forward"], s["reverse"]):
            if s["status"] == "paired":
                role = "forward" if s["forward"] == name else "reverse"
            else:
                role = s.get("role")
            mate = None
            if s["status"] == "paired":
                mate = s["reverse"] if s["forward"] == name else s["forward"]
            return {"status": s["status"], "sample": s["sample"], "role": role,
                    "mate": posixpath.basename(mate) if mate else None,
                    "pattern": _PATTERN_LABEL.get(fq["pattern"] or "", "")}
    return None


def tenx_member(name: str, siblings: Sequence[str]) -> Optional[Dict[str, Any]]:
    """{role, version, matrix} when ``name`` belongs to a 10x matrix set together with
    ``siblings`` (files of the same directory), else None."""
    for s in tenx_sets([name] + [x for x in siblings if x != name]):
        for role in ("matrix", "barcodes", "features"):
            if s.get(role) == name:
                part = lambda r: posixpath.basename(s[r]) if s.get(r) else None  # noqa: E731
                return {"role": role, "version": s.get("version"), "matrix": part("matrix"),
                        "barcodes": part("barcodes"), "features": part("features")}
    return None


# 10x spec column names for the header-less TSVs (Cell Ranger ≥3: features.tsv has 3 columns;
# v2 genes.tsv has 2).
TENX_COLUMNS = {
    "features": ["feature_id", "feature_name", "feature_type"],
    "barcodes": ["barcode"],
}
