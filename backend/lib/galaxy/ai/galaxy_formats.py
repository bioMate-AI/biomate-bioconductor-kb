"""
Galaxy datatypes for the dataset profiler — format identification + cheap metadata.

BioMate's backend is a Galaxy fork, so the ~740 datatypes Galaxy ships (sniffers and
``set_meta`` metadata extractors for BAM, CRAM, h5ad, loom, GTF/GFF3, BED, FASTA, SDF,
PDB, MatrixMarket, TIFF, …) are reused here instead of re-implementing format parsers.

Contract (all functions NEVER raise):

* :func:`available` — True when ``galaxy.datatypes`` imports and the registry builds.
  On a host without Galaxy's dependencies (a laptop venv) it is False and callers keep
  their own behaviour.
* :func:`identify` ``(path, name) -> Optional[str]`` — the Galaxy extension. A filename
  extension wins when it maps to a datatype the content supports (its sniffer accepts the
  file, or the content is sniffed as a parent type of it, e.g. ``.smi`` → SMILES when the
  content sniffs as plain ``tabular``); otherwise ``guess_ext`` over the sniff order.
* :func:`is_text_ext` ``(ext) -> Optional[bool]`` — whether that datatype is text (the
  profiler's binary judgement honours Galaxy's text identification).
* :func:`metadata` ``(path, ext) -> Dict`` — metadata for an allow-list of datatypes whose
  ``set_meta`` is cheap and safe here: no file-valued metadata (BAM/CRAM/BCF/TIFF/VcfGz
  need ``metadata.spec`` and a real model), no index building (BAM ``set_meta`` sorts and
  indexes). BAM/CRAM headers are read with pysam directly. Text formats above
  ``MAX_TEXT_META_BYTES`` (compressed: ``MAX_COMPRESSED_META_BYTES``) skip ``set_meta``.

The registry is built lazily on first use (≈6 s, ~740 datatypes), once per process,
under a lock — never at import time.
"""
from __future__ import annotations

import copy
import logging
import os
import threading
import time
from typing import Any, Dict, List, Optional

log = logging.getLogger(__name__)

# set_meta reads the whole file for most text datatypes (FASTA counts every line).
MAX_TEXT_META_BYTES = 200 * 1024 * 1024
MAX_COMPRESSED_META_BYTES = 50 * 1024 * 1024
# Archive sniffers (fast5.tar, wiff.tar, database dumps, …) list every tar member, which reads
# the whole archive once per sniffer (11 s for a 100 KB tar.bz2 on dev). Compressed tars, and
# plain tars above this size, are identified from their filename only.
MAX_ARCHIVE_SNIFF_BYTES = 20 * 1024 * 1024
# Lists in the returned metadata are capped so a profile stays small.
MAX_META_LIST = 50

# Filename spellings Galaxy does not register under that name → the Galaxy extension.
_EXT_ALIASES: Dict[str, str] = {
    "fa": "fasta", "fna": "fasta", "faa": "fasta", "fas": "fasta", "fsa": "fasta", "ffn": "fasta",
    "fq": "fastqsanger", "fastq": "fastqsanger",
    "fa.gz": "fasta.gz", "fna.gz": "fasta.gz", "faa.gz": "fasta.gz",
    "fq.gz": "fastqsanger.gz", "fastq.gz": "fastqsanger.gz",
    "fq.bz2": "fastqsanger.bz2", "fastq.bz2": "fastqsanger.bz2",
    "vcf.gz": "vcf_bgzip", "vcf.bgz": "vcf_bgzip",
    "tif": "tiff", "ome.tif": "ome.tiff",
    "mmcif": "cif",
    "smiles": "smi",
    "narrowpeak": "encodepeak",
    "yml": "yaml",
    "bw": "bigwig",
    "xls": "excel.xls",
}

# Galaxy's catch-all answers: they say "some text/binary", not which format.
GENERIC_EXTS = frozenset({"data", "binary", "txt", "text", "tabular", "tsv"})

# Datatypes whose set_meta is safe/cheap with a stub dataset (no file-valued metadata, no
# index building). Keys are Galaxy extensions; the value says whether the type is text
# (size-guarded) or binary (set_meta reads only headers/attributes).
_SET_META_ALLOW: Dict[str, str] = {
    "fasta": "text", "fasta.gz": "text",
    "gff": "text", "gff3": "text", "gtf": "text", "gff3.gz": "text", "gtf.gz": "text",
    "bed": "text", "bed6": "text", "bed12": "text", "bedgraph": "text", "interval": "text",
    "encodepeak": "text",
    "mtx": "text",
    "sdf": "text", "pdb": "text", "cif": "text", "smi": "text",
    "h5ad": "binary", "loom": "binary",
}

# Human labels for the format chip (Galaxy extensions are lowercase codes).
_LABELS: Dict[str, str] = {
    "bam": "BAM", "cram": "CRAM", "sam": "SAM", "qname_sorted.bam": "BAM (name-sorted)",
    "unsorted.bam": "BAM (unsorted)", "bcf": "BCF", "bcf_uncompressed": "BCF (uncompressed)",
    "vcf": "VCF", "vcf_bgzip": "VCF (bgzip)", "fasta": "FASTA", "fasta.gz": "FASTA (gzip)",
    "fastqsanger": "FASTQ", "fastqsanger.gz": "FASTQ (gzip)", "fastqsanger.bz2": "FASTQ (bzip2)",
    "fastq": "FASTQ", "fastqcssanger": "FASTQ (color space)", "fastqsolexa": "FASTQ (Solexa)",
    "gff": "GFF", "gff3": "GFF3", "gtf": "GTF", "gff3.gz": "GFF3 (gzip)", "gtf.gz": "GTF (gzip)",
    "bed": "BED", "bed6": "BED6", "bed12": "BED12", "bedgraph": "bedGraph", "interval": "Interval",
    "encodepeak": "ENCODE peak (narrowPeak)", "broadpeak": "broadPeak", "narrowpeak": "narrowPeak",
    "mtx": "Matrix Market", "h5ad": "AnnData (h5ad)", "loom": "Loom", "h5": "HDF5",
    "xlsx": "Excel (xlsx)", "excel.xls": "Excel (xls)", "tiff": "TIFF", "ome.tiff": "OME-TIFF",
    "mrc": "MRC", "pod5": "POD5", "sdf": "SDF", "smi": "SMILES", "pdb": "PDB", "cif": "mmCIF",
    "csv": "CSV", "tsv": "TSV", "tabular": "Tabular", "txt": "Text", "json": "JSON", "yaml": "YAML",
    "jsonl": "JSON Lines", "pdf": "PDF", "png": "PNG", "jpg": "JPEG", "zip": "ZIP",
    "bigwig": "bigWig", "bigbed": "bigBed", "data": "Unknown", "binary": "Binary",
    "tar": "Tar archive", "fast5.tar": "FAST5 archive (tar)", "fast5.tar.gz": "FAST5 archive (tar.gz)",
    "fast5.tar.bz2": "FAST5 archive (tar.bz2)", "h5": "HDF5", "bcf_bgzip": "BCF", "fast5": "FAST5",
    "gif": "GIF", "bmp": "BMP", "svg": "SVG", "html": "HTML", "markdown": "Markdown", "docx": "Word document",
    "sqlite": "SQLite database", "rds": "R data (RDS)", "mol2": "MOL2", "genbank": "GenBank",
    "mzml": "mzML", "mzxml": "mzXML", "mgf": "MGF", "biom1": "BIOM", "cool": "Cooler (cool)", "mcool": "Cooler (mcool)",
}


_COMPRESSION_WORDS = {"gz": "gzip", "bz2": "bzip2", "bgz": "bgzip", "xz": "xz", "zst": "zstd"}


def label_for(ext: Optional[str]) -> str:
    """Human label for a Galaxy extension: the known label, else words built from its parts
    ("fast5.tar.gz" → "FAST5 archive (tar.gz)", "mothur.axes" → "Mothur axes") — never a raw
    dotted code."""
    if not ext:
        return "Unknown"
    if ext in _LABELS:
        return _LABELS[ext]
    return humanize_ext(ext)


def humanize_ext(ext: str) -> str:
    parts = [p for p in ext.lower().split(".") if p]
    if not parts:
        return "Unknown"
    comp = []
    while parts and parts[-1] in _COMPRESSION_WORDS:
        comp.insert(0, parts.pop())
    archive = bool(parts) and parts[-1] in ("tar", "zip")
    if archive:
        comp.insert(0, parts.pop())
    if not parts:
        return ("Tar archive" if comp[0] == "tar" else "ZIP archive") if archive else (
            f"{_COMPRESSION_WORDS.get(comp[0], comp[0])}-compressed file")
    base = _LABELS.get(".".join(parts))
    if base is None:
        words = []
        for i, p in enumerate(parts):
            p = p.replace("_", " ")
            if len(p) <= 5 and any(c.isdigit() for c in p) or len(p) <= 3:
                words.append(p.upper())
            else:
                words.append(p.capitalize() if i == 0 else p)
        base = " ".join(words)
    if archive:
        return f"{base} archive ({'.'.join(comp)})"
    if comp:
        return f"{base} ({', '.join(_COMPRESSION_WORDS[c] for c in comp)})"
    return base


# Galaxy datatype class → the panel's view kind, for formats without an explicit mapping.
def view_for_ext(ext: str) -> Optional[str]:
    """'image' / 'archive' / 'document' / 'binary' from the datatype's class (None if unknown or
    Galaxy is unavailable)."""
    reg = _registry()
    if reg is None:
        return None
    dt = (getattr(reg, "datatypes_by_extension", {}) or {}).get(ext)
    if dt is None:
        return None
    mro = [c.__module__ + "." + c.__name__ for c in type(dt).__mro__]
    if any(m.startswith("galaxy.datatypes.images.") for m in mro):
        return "image"
    if any(m.endswith((".CompressedArchive", ".CompressedZipArchive", ".Tar", ".GenericTar")) for m in mro):
        return "archive"
    if any(m.startswith("galaxy.datatypes.text.Html") or m.endswith(".Pdf") for m in mro):
        return "document"
    if any(m.startswith("galaxy.datatypes.binary.") for m in mro):
        return "binary"
    return None


def is_text_ext(ext: Optional[str]) -> Optional[bool]:
    """Whether Galaxy's datatype for ``ext`` is a TEXT datatype (csv, tabular, txt, json, fasta, …:
    a subclass of ``galaxy.datatypes.data.Text`` and not of ``binary.Binary``). None when Galaxy is
    unavailable or the extension is not registered."""
    reg = _registry()
    if reg is None or not ext:
        return None
    dt = (getattr(reg, "datatypes_by_extension", {}) or {}).get(ext)
    if dt is None:
        return None
    try:
        from galaxy.datatypes.binary import Binary
        from galaxy.datatypes.data import Text
    except Exception:  # noqa: BLE001
        return None
    if isinstance(dt, Binary):
        return False
    return isinstance(dt, Text)


# ---------------------------------------------------------------------------
# Registry (lazy, process-cached, thread-safe)
# ---------------------------------------------------------------------------
_LOCK = threading.Lock()
_STATE: Dict[str, Any] = {"tried": False, "registry": None, "error": None, "build_s": None}


def _build_registry() -> Any:
    from galaxy.datatypes.registry import Registry
    from galaxy.util import galaxy_directory
    from galaxy.util.bunch import Bunch

    root = galaxy_directory()
    conf = None
    for cand in (
        os.environ.get("GALAXY_DATATYPES_CONF"),
        os.path.join(root, "config", "datatypes_conf.xml"),
        os.path.join(root, "lib", "galaxy", "config", "sample", "datatypes_conf.xml.sample"),
    ):
        if cand and os.path.isfile(cand):
            conf = cand
            break
    if conf is None:
        raise RuntimeError("no datatypes_conf.xml found")
    registry = Registry(Bunch(sniff_compressed_dynamic_datatypes_default=True))
    registry.load_datatypes(root_dir=root, config=conf)
    return registry


def _registry() -> Any:
    if _STATE["tried"]:
        return _STATE["registry"]
    with _LOCK:
        if not _STATE["tried"]:
            t0 = time.time()
            try:
                _STATE["registry"] = _build_registry()
            except Exception as exc:  # noqa: BLE001 — no Galaxy deps here: degrade, don't crash
                _STATE["error"] = f"{type(exc).__name__}: {exc}"[:300]
                log.info("[galaxy_formats] Galaxy datatypes unavailable: %s", _STATE["error"])
            _STATE["build_s"] = round(time.time() - t0, 2)
            _STATE["tried"] = True
    return _STATE["registry"]


def available() -> bool:
    return _registry() is not None


def status() -> Dict[str, Any]:
    """Diagnostics (whether the registry was built, why not, how long it took)."""
    return {"tried": _STATE["tried"], "available": _STATE["registry"] is not None,
            "error": _STATE["error"], "build_s": _STATE["build_s"]}


# ---------------------------------------------------------------------------
# Identification
# ---------------------------------------------------------------------------
def filename_exts(name: str) -> List[str]:
    """Candidate extensions from a filename, most specific first, aliases resolved:
    'a.ome.tif' → ['ome.tiff', 'tiff']; 'x.fastq.gz' → ['fastqsanger.gz', 'gz']."""
    base = os.path.basename(name or "").lower()
    parts = base.split(".")[1:]
    out: List[str] = []
    for i in range(len(parts)):
        ext = ".".join(parts[i:])
        if not ext:
            continue
        ext = _EXT_ALIASES.get(ext, ext)
        if ext not in out:
            out.append(ext)
    return out


def _is_root_class(dt: Any) -> bool:
    try:
        from galaxy.datatypes.binary import Binary
        from galaxy.datatypes.data import Data, Text
    except Exception:  # noqa: BLE001
        return True
    return type(dt) in (Data, Text, Binary)


def _is_large_tar(path: str) -> bool:
    """A tar archive whose sniffing would decompress all of it repeatedly: any compressed tar
    (gzip/bzip2/xz — re-reading a compressed stream for every tar sniffer cost 11 s for a 100 KB
    .tar.bz2 on dev), or a plain tar above MAX_ARCHIVE_SNIFF_BYTES."""
    try:
        with open(path, "rb") as f:
            magic = f.read(6)
        if magic[:2] == b"\x1f\x8b":
            import gzip as _c
            opener: Any = _c.open
        elif magic[:3] == b"BZh":
            import bz2 as _c
            opener = _c.open
        elif magic[:6] == b"\xfd7zXZ\x00":
            import lzma as _c
            opener = _c.open
        else:
            opener = None
        with (opener or open)(path, "rb") as f:
            block = f.read(512)
        if block[257:262] != b"ustar":
            return False
        return opener is not None or os.path.getsize(path) > MAX_ARCHIVE_SNIFF_BYTES
    except Exception:  # noqa: BLE001
        return False


def extension_for_name(name: str) -> Optional[str]:
    """The Galaxy extension a filename claims (most specific registered one), without reading
    the file — for roll-ups over many files. None when Galaxy is unavailable or no candidate
    extension is a registered datatype."""
    reg = _registry()
    if reg is None:
        return None
    by_ext = getattr(reg, "datatypes_by_extension", {}) or {}
    for ext in filename_exts(name):
        if ext in by_ext:
            return ext
    return None


def identify(path: str, name: Optional[str] = None) -> Optional[str]:
    """Galaxy extension of the file at ``path`` (``name`` supplies the filename when the
    path is a temp copy). None when Galaxy is unavailable or nothing could be determined."""
    reg = _registry()
    if reg is None or not path or not os.path.isfile(path):
        return None
    by_ext = getattr(reg, "datatypes_by_extension", {}) or {}
    if _is_large_tar(path):
        for ext in filename_exts(name or path):
            if ext in by_ext:
                return ext
        return "tar"
    try:
        from galaxy.datatypes.sniff import guess_ext
    except Exception:  # noqa: BLE001
        return None
    guessed_cache: Dict[str, Any] = {}

    def guessed() -> Optional[str]:
        if "v" not in guessed_cache:
            try:
                guessed_cache["v"] = guess_ext(path, reg.sniff_order)
            except Exception as exc:  # noqa: BLE001
                log.info("[galaxy_formats] guess_ext failed for %s: %s", path, exc)
                guessed_cache["v"] = None
        return guessed_cache["v"]

    for ext in filename_exts(name or path):
        dt = by_ext.get(ext)
        if dt is None:
            continue
        has_sniffer = hasattr(dt, "sniff_prefix") or hasattr(dt, "sniff")
        if has_sniffer:
            try:
                if dt.sniff(path):
                    return ext
            except Exception:  # noqa: BLE001 — a sniffer error is a "no"
                pass
        # The content sniffs as a parent type of the named one (SMILES ⊂ Tabular, ENCODEPeak ⊂
        # Interval): the filename refines what the content shows. A sniffer that ran and said no
        # is only overruled by a specific parent, never by the catch-all Data/Text/Binary.
        g = guessed()
        gdt = by_ext.get(g) if g else None
        if gdt is not None and isinstance(dt, type(gdt)) and (not has_sniffer or not _is_root_class(gdt)):
            return ext
    return guessed()


# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------
class _Meta:
    """Just enough of Galaxy's MetadataCollection for set_meta on a stub dataset."""

    def __init__(self, spec: Any) -> None:
        self._defaults: Dict[str, Any] = {}
        for key, el in (spec or {}).items():
            default = copy.deepcopy(getattr(el, "default", None))
            self._defaults[key] = default
            object.__setattr__(self, key, default)

    def element_is_set(self, name: str) -> bool:
        return getattr(self, name, None) != self._defaults.get(name)

    def get(self, name: str, default: Any = None) -> Any:
        return getattr(self, name, default)

    def items(self):
        return [(k, getattr(self, k, None)) for k in self._defaults]

    def __getattr__(self, name: str) -> Any:  # unknown element → None, like Galaxy
        if name.startswith("__"):
            raise AttributeError(name)
        return None


class _StubDataset:
    def __init__(self, path: str, datatype: Any, ext: str) -> None:
        self._path = path
        self.datatype = datatype
        self.ext = self.extension = ext
        self.metadata = _Meta(getattr(datatype, "metadata_spec", None))
        self.dataset = None

    def get_file_name(self, sync_cache: bool = True) -> str:
        return self._path

    @property
    def file_name(self) -> str:
        return self._path

    def has_data(self) -> bool:
        return os.path.getsize(self._path) > 0

    def get_size(self, *a: Any, **k: Any) -> int:
        return os.path.getsize(self._path)


def _plain(v: Any, depth: int = 0) -> Any:
    """JSON-safe copy of a metadata value (lists/dicts capped)."""
    if v is None or isinstance(v, (bool, int, float, str)):
        return v
    if isinstance(v, (bytes, bytearray)):
        return bytes(v[:2000]).decode("utf-8", errors="replace")
    if depth > 3:
        return str(v)[:200]
    if isinstance(v, dict):
        return {str(k): _plain(x, depth + 1) for k, x in list(v.items())[:MAX_META_LIST]}
    if isinstance(v, (list, tuple, set, frozenset)):
        return [_plain(x, depth + 1) for x in list(v)[:MAX_META_LIST]]
    try:  # numpy scalars and friends
        return v.item()  # type: ignore[union-attr]
    except Exception:  # noqa: BLE001
        return str(v)[:200]


def _is_compressed(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            head = f.read(4)
    except OSError:
        return False
    return head[:2] == b"\x1f\x8b" or head[:3] == b"BZh" or head[:4] == b"\x28\xb5\x2f\xfd"


def alignment_header(path: str) -> Dict[str, Any]:
    """BAM/CRAM header via pysam (never set_meta: Galaxy's BAM set_meta sorts + indexes)."""
    import pysam  # present in the Galaxy image

    with pysam.AlignmentFile(path, check_sq=False) as af:  # type: ignore[attr-defined]
        hdr = af.header.to_dict()
        refs = list(af.references or [])
        lengths = list(af.lengths or [])
    hd = hdr.get("HD") or {}
    rgs = hdr.get("RG") or []
    samples = sorted({str(r.get("SM")) for r in rgs if r.get("SM")})
    programs = [str(p.get("ID") or p.get("PN")) for p in (hdr.get("PG") or [])]
    return {
        "reference_count": len(refs),
        "reference_names": refs[:MAX_META_LIST],
        "reference_total_length": int(sum(lengths)) if lengths else 0,
        "sort_order": str(hd.get("SO") or "unknown"),
        "read_groups": [str(r.get("ID")) for r in rgs][:MAX_META_LIST],
        "read_group_count": len(rgs),
        "samples": samples[:MAX_META_LIST],
        "programs": programs[:MAX_META_LIST],
    }


def anndata_layers(path: str) -> Optional[List[str]]:
    """The AnnData layers of an h5ad (keys of its ``layers`` group; [] when it has none), via h5py
    (present in the Galaxy image). None when h5py is missing or the file cannot be opened."""
    try:
        import h5py
    except Exception:  # noqa: BLE001
        return None
    try:
        try:
            f = h5py.File(path, "r", locking=False)  # h5py ≥ 3.5 (as Galaxy's own set_meta opens it)
        except TypeError:
            f = h5py.File(path, "r")  # older h5py: no ``locking`` argument
        with f:
            grp = f.get("layers")
            if grp is None or not hasattr(grp, "keys"):
                return []
            return [str(k) for k in list(grp.keys())[:MAX_META_LIST]]
    except Exception as exc:  # noqa: BLE001
        log.info("[galaxy_formats] h5ad layers unreadable for %s: %s", path, exc)
        return None


# The first sheet's preview: at most this many rows (header + data) × columns, read with a
# BOUNDED streaming scan (openpyxl read-only mode stops after the last requested row) — opening a
# workbook never parses whole sheets.
XLSX_PREVIEW_ROWS = 101
XLSX_PREVIEW_COLS = 50


def _xlsx_cell(v: Any) -> str:
    if v is None:
        return ""
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, float) and v.is_integer() and abs(v) < 2 ** 53:
        return str(int(v))
    iso = getattr(v, "isoformat", None)
    if iso is not None:
        out = iso()
        return out[:-9] if out.endswith("T00:00:00") else out
    return str(v)


def _bounded_workbook(path: str) -> Any:
    """The workbook in openpyxl's read-only mode WITHOUT a full parse of every sheet at open.

    openpyxl's read-only ``load_workbook`` sizes each sheet in ``ReadOnlyWorksheet.__init__``
    through ``WorkSheetParser.parse_dimensions``, which iterparses END events: when a sheet stores
    no ``<dimension>`` element (openpyxl's own write-only mode and several other writers omit it)
    the ``<sheetData>`` end event comes only after the WHOLE sheet, so opening a 4 MB workbook
    parsed all of its cells (≈ 5 s on a laptop, every sheet, before a single row was read). Here
    each sheet is sized from START events and the scan stops at ``<sheetData>``; rows are then read
    lazily (and only as many as asked for) by openpyxl's own row parser.
    """
    from xml.etree.ElementTree import iterparse

    from openpyxl.reader.excel import ExcelReader
    from openpyxl.utils.cell import range_boundaries
    from openpyxl.worksheet._read_only import ReadOnlyWorksheet
    from openpyxl.xml.constants import SHEET_MAIN_NS

    dim_tag, data_tag = f"{{{SHEET_MAIN_NS}}}dimension", f"{{{SHEET_MAIN_NS}}}sheetData"

    class _BoundedSheet(ReadOnlyWorksheet):
        def _get_size(self) -> None:  # noqa: D401 — openpyxl hook
            src = self._get_source()
            try:
                for _event, el in iterparse(src, events=("start",)):
                    if el.tag == dim_tag:
                        ref = el.get("ref") or ""
                        try:
                            bounds = range_boundaries(ref if ":" in ref else f"{ref}:{ref}")
                        except (ValueError, TypeError):
                            bounds = None
                        if bounds and None not in bounds:
                            self._min_column, self._min_row, self._max_column, self._max_row = bounds
                        return
                    if el.tag == data_tag:
                        return  # no stored dimension: unsized (max_row / max_column stay None)
            finally:
                src.close()

    class _Reader(ExcelReader):
        def read_worksheets(self) -> None:
            for sheet, rel in self.parser.find_sheets():
                if rel.target not in self.valid_files or "chartsheet" in (rel.Type or ""):
                    continue
                ws = _BoundedSheet(self.wb, sheet.name, rel.target, self.shared_strings)
                ws.sheet_state = sheet.state
                self.wb._sheets.append(ws)

    reader = _Reader(path, read_only=True, data_only=True, keep_links=False)
    reader.read()
    return reader.wb


def xlsx_summary(path: str) -> Optional[Dict[str, Any]]:
    """{"sheets": [{name, rows, cols}], "preview": {"sheet", "rows": [[str]]}} via openpyxl in
    read-only mode (see _bounded_workbook); None when openpyxl is missing. ``rows`` / ``cols`` come
    from the sheet's stored dimension (None when the writer stored none, or one the preview
    contradicts); the preview holds the first sheet's first non-empty rows (≤ XLSX_PREVIEW_ROWS ×
    XLSX_PREVIEW_COLS). Cost: the shared-string table + the preview rows, whatever the sheet size."""
    try:
        import openpyxl  # noqa: F401
    except Exception:  # noqa: BLE001
        return None
    wb = _bounded_workbook(path)
    try:
        sheets: List[Dict[str, Any]] = []
        for ws in wb.worksheets[:MAX_META_LIST]:
            sheets.append({"name": str(ws.title), "rows": ws.max_row, "cols": ws.max_column})
        preview: Optional[Dict[str, Any]] = None
        if wb.worksheets:
            ws = wb.worksheets[0]
            rows: List[List[str]] = []
            for raw in ws.iter_rows(min_row=1, max_row=XLSX_PREVIEW_ROWS, max_col=XLSX_PREVIEW_COLS,
                                    values_only=True):
                cells = [_xlsx_cell(v) for v in raw]
                while cells and cells[-1] == "":
                    cells.pop()
                if cells:
                    rows.append(cells)
            preview = {"sheet": str(ws.title), "rows": rows}
            first = sheets[0]
            width = max((len(r) for r in rows), default=0)
            if (first["rows"] is not None and first["rows"] < len(rows)) or \
                    (first["cols"] is not None and first["cols"] < width):
                first["rows"] = first["cols"] = None  # a stale stored dimension ("A1"): unknown
        return {"sheets": sheets, "preview": preview}
    finally:
        wb.close()


def metadata(path: str, ext: Optional[str]) -> Dict[str, Any]:
    """Metadata for ``ext`` read from ``path``. ``{}`` when not applicable/available;
    ``{"skipped": reason}`` when a guard skipped it; ``{"error": …}`` on failure."""
    if not ext or not path or not os.path.isfile(path):
        return {}
    try:
        if ext in ("bam", "cram", "qname_sorted.bam", "unsorted.bam"):
            try:
                import pysam  # noqa: F401 — present in the Galaxy image, not on every host
            except ImportError:
                return {"skipped": "pysam_missing"}
            return alignment_header(path)
        if ext == "xlsx":
            summary = xlsx_summary(path)
            return summary if summary is not None else {"skipped": "openpyxl_missing"}
        kind = _SET_META_ALLOW.get(ext)
        if kind is None:
            return {}
        reg = _registry()
        if reg is None:
            return {}
        dt = reg.get_datatype_by_extension(ext)
        if dt is None:
            return {}
        size = os.path.getsize(path)
        if kind == "text":
            cap = MAX_COMPRESSED_META_BYTES if _is_compressed(path) else MAX_TEXT_META_BYTES
            if size > cap:
                return {"skipped": "too_large", "bytes": size, "cap": cap}
        ds = _StubDataset(path, dt, ext)
        dt.set_meta(ds, overwrite=True)
        out = {k: _plain(v) for k, v in ds.metadata.items()}
        if ext == "h5ad":
            # Galaxy's "layers_names" are the file's TOP-LEVEL groups (X, obs, var, obsm, …), not
            # AnnData layers; the layers are the keys of the ``layers`` group.
            layers = anndata_layers(path)
            if layers is not None:
                out["anndata_layers"] = layers
        return {k: v for k, v in out.items() if v is not None}
    except Exception as exc:  # noqa: BLE001 — metadata is best-effort
        log.info("[galaxy_formats] metadata(%s) failed for %s: %s", ext, path, exc)
        return {"error": f"{type(exc).__name__}: {exc}"[:300]}


_SPEC_NAMES_CACHE: Dict[str, Optional[List[str]]] = {}


def spec_column_names(ext: str) -> Optional[List[str]]:
    """Galaxy's column names for a header-less spec format (class attribute; importing the
    datatype module does not need the registry). None when Galaxy is unavailable."""
    if ext not in _SPEC_NAMES_CACHE:
        _SPEC_NAMES_CACHE[ext] = _spec_column_names(ext)
    return _SPEC_NAMES_CACHE[ext]


def _spec_column_names(ext: str) -> Optional[List[str]]:
    targets = {
        "bed": ("galaxy.datatypes.interval", "Bed"),
        "encodepeak": ("galaxy.datatypes.interval", "ENCODEPeak"),
        "gff": ("galaxy.datatypes.interval", "Gff"),
        "gff3": ("galaxy.datatypes.interval", "Gff3"),
        "gtf": ("galaxy.datatypes.interval", "Gtf"),
        "smi": ("galaxy.datatypes.molecules", "SMILES"),
    }
    tgt = targets.get(ext)
    if not tgt:
        return None
    try:
        import importlib

        cls = getattr(importlib.import_module(tgt[0]), tgt[1])
        names = getattr(cls, "column_names", None)
        return [str(n) for n in names] if names else None
    except Exception:  # noqa: BLE001
        return None
