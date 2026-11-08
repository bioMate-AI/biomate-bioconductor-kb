#!/usr/bin/env python3
"""Fail-closed name/content gate for explicit delivery artifacts, never a scrubber.

Pass forbidden terms explicitly. Supports files/directories, ZIP/Word/wheels,
tar layers and gzip streams. Reads archives without extracting or executing.
Budget, depth, unreadable and unsupported-compression failures are not passes.
"""
import argparse
import gzip
import json
from pathlib import Path
import tarfile
import zipfile


class PayloadAudit:
    def __init__(self, terms, max_bytes=512 * 1024 * 1024, max_depth=8):
        if not terms or any(not term for term in terms):
            raise ValueError("At least one nonempty forbidden term is required")
        self.terms = terms
        self.patterns = [(term, term.encode(encoding).lower()) for term in terms for encoding in ("utf-8", "utf-16le", "utf-16be")]
        self.overlap = max(len(pattern) for _, pattern in self.patterns) - 1
        self.max_bytes, self.max_depth = max_bytes, max_depth
        self.bytes_read = 0
        self.entries = 0
        self.findings, self.errors = [], []

    def name(self, name):
        for term in self.terms:
            if term.casefold() in name.casefold():
                self.findings.append({"path": name, "kind": "name", "term": term})

    def stream(self, stream, name, depth=0):
        self.entries += 1
        self.name(name)
        if depth > self.max_depth:
            self.errors.append({"path": name, "error": "archive-depth-budget"})
            return
        try:
            tail, header, matches = b"", b"", set()
            while True:
                chunk = stream.read(1024 * 1024)
                if not chunk:
                    break
                self.bytes_read += len(chunk)
                if self.bytes_read > self.max_bytes:
                    raise ValueError("byte-budget-exceeded")
                if not header:
                    header = chunk[:512]
                data = (tail + chunk).lower()
                matches.update(term for term, pattern in self.patterns if pattern in data)
                tail = data[-self.overlap:] if self.overlap else b""
            self.findings.extend({"path": name, "kind": "content", "term": term} for term in sorted(matches))
            stream.seek(0)
            if header.startswith(b"%PDF-") or name.lower().endswith(".pdf"):
                # Compressed streams, font encodings and image-only pages need
                # a dedicated extraction/OCR review. Raw-byte absence is not a
                # certificate that a rendered PDF is free of the retired term.
                raise ValueError("pdf-requires-separate-rendered-content-audit")
            elif header.startswith(b"PK\x03\x04") or name.lower().endswith((".zip", ".docx", ".pptx", ".xlsx", ".whl")):
                with zipfile.ZipFile(stream) as archive:
                    for member in archive.infolist():
                        if member.is_dir():
                            self.name(name + "!" + member.filename)
                        else:
                            with archive.open(member) as content:
                                self.stream(content, name + "!" + member.filename, depth + 1)
            elif header.startswith(b"\x1f\x8b") or name.lower().endswith((".gz", ".tgz")):
                # Older Python versions inherit an integer .mode from an
                # enclosing GzipFile unless an explicit mode is supplied.
                with gzip.GzipFile(fileobj=stream, mode="rb") as content:
                    self.stream(content, name + "!gzip-payload", depth + 1)
            elif header[257:262] == b"ustar" or name.lower().endswith(".tar"):
                with tarfile.open(fileobj=stream, mode="r:") as archive:
                    for member in archive:
                        member_name = name + "!" + member.name
                        if member.isfile():
                            with archive.extractfile(member) as content:
                                self.stream(content, member_name, depth + 1)
                        else:
                            self.name(member_name)
                            if member.issym() or member.islnk():
                                self.name(member_name + "->" + member.linkname)
            elif header.startswith((b"7z\xbc\xaf\x27\x1c", b"\xfd7zXZ", b"\x28\xb5\x2f\xfd", b"BZh")) or name.lower().endswith((".7z", ".xz", ".zst", ".zstd", ".bz2", ".rar")):
                raise ValueError("unsupported-compression-requires-separate-scan")
        except Exception as error:
            # Record only the category, never raw input or exception payloads.
            self.errors.append({"path": name, "error": type(error).__name__})

    def path(self, path):
        path = Path(path)
        try:
            if path.is_symlink():
                self.errors.append({"path": str(path), "error": "external-symlink-not-scanned"})
            elif path.is_dir():
                self.name(str(path))
                for child in sorted(path.iterdir()):
                    self.path(child)
            elif path.is_file():
                with path.open("rb") as content:
                    self.stream(content, str(path))
            else:
                self.errors.append({"path": str(path), "error": "not-readable-regular-file"})
        except OSError as error:
            self.errors.append({"path": str(path), "error": type(error).__name__})

    def result(self):
        return {"passed": bool(self.entries) and not self.findings and not self.errors,
                "entries": self.entries, "bytes_read_including_archive_layers": self.bytes_read,
                "findings": self.findings, "errors": self.errors}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--forbidden-term", action="append", required=True)
    parser.add_argument("--max-bytes", type=int, default=512 * 1024 * 1024)
    args = parser.parse_args()
    audit = PayloadAudit(args.forbidden_term, max_bytes=args.max_bytes)
    for path in args.paths:
        audit.path(path)
    result = audit.result()
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
