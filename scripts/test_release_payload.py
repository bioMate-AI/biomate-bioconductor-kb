#!/usr/bin/env python3
import gzip
import io
import tarfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from check_release_payload import PayloadAudit


class PayloadTests(unittest.TestCase):
    def audit(self, data, name="release.bin", **kwargs):
        result = PayloadAudit(["RetiredBrand"], **kwargs)
        result.stream(io.BytesIO(data), name)
        return result.result()

    def test_clean_bytes_pass(self):
        self.assertTrue(self.audit(b"BioMate release") ["passed"])

    def test_case_insensitive_name_and_content(self):
        result = self.audit(b"RETIREDbrand", "retiredBRAND/file")
        self.assertFalse(result["passed"])
        self.assertEqual({x["kind"] for x in result["findings"]}, {"name", "content"})

    def test_chunk_boundary_and_utf16(self):
        self.assertFalse(self.audit(b"x" * (1024 * 1024 - 4) + b"RetiredBrand")["passed"])
        self.assertFalse(self.audit("RetiredBrand".encode("utf-16le"))["passed"])

    def test_word_zip_contents_are_scanned(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("word/document.xml", "<t>RetiredBrand</t>")
        result = self.audit(buffer.getvalue(), "guide.docx")
        self.assertFalse(result["passed"])
        self.assertTrue(any("document.xml" in x["path"] for x in result["findings"]))

    def test_gzip_tar_layer_contents_are_scanned_without_extraction(self):
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w") as archive:
            member = tarfile.TarInfo("app/config.txt")
            data = b"RetiredBrand"
            member.size = len(data)
            archive.addfile(member, io.BytesIO(data))
        result = self.audit(gzip.compress(buffer.getvalue()), "image-layer.gz")
        self.assertFalse(result["passed"])
        self.assertTrue(any("app/config.txt" in x["path"] for x in result["findings"]))

    def test_limits_and_bad_archives_are_not_silent_passes(self):
        for result in (self.audit(b"x" * 20, max_bytes=10), self.audit(b"not a zip", "broken.docx"), self.audit(b"\x28\xb5\x2f\xfdunknown")):
            self.assertFalse(result["passed"])
            self.assertTrue(result["errors"])

    def test_empty_input_set_cannot_pass(self):
        self.assertFalse(PayloadAudit(["RetiredBrand"]).result()["passed"])

    def test_pdf_requires_separate_content_review_even_without_raw_term(self):
        for data, name in ((b"%PDF-1.7\ncompressed-content", "disguised.bin"),
                           (b"encoded-content", "delivery.pdf")):
            with self.subTest(name=name):
                result = self.audit(data, name)
                self.assertFalse(result["passed"])
                self.assertTrue(result["errors"])

    def test_corrupt_or_unsupported_archive_suffix_cannot_pass(self):
        for suffix in (".gz", ".tgz", ".tar", ".docx", ".xz", ".zst", ".bz2", ".7z", ".rar"):
            with self.subTest(suffix=suffix):
                result = self.audit(b"not an archive", "delivery" + suffix)
                self.assertFalse(result["passed"])
                self.assertTrue(result["errors"])

    def test_unreadable_member_is_reported_not_unhandled(self):
        audit = PayloadAudit(["RetiredBrand"])
        audit.stream(io.BytesIO(b"clean"), "readable")
        with patch.object(Path, "is_symlink", return_value=False), patch.object(Path, "is_dir", return_value=False), patch.object(Path, "is_file", return_value=True), patch.object(Path, "open", side_effect=PermissionError("secret canary")):
            audit.path("blocked")
        result = audit.result()
        self.assertFalse(result["passed"])
        self.assertEqual(result["errors"], [{"path": "blocked", "error": "PermissionError"}])

    def test_nested_archive_depth_is_enforced(self):
        result = self.audit(gzip.compress(gzip.compress(b"clean")), "nested.gz", max_depth=1)
        self.assertFalse(result["passed"])
        self.assertTrue(any(x["error"] == "archive-depth-budget" for x in result["errors"]))

    def test_nested_gzip_content_is_actually_read(self):
        result = self.audit(gzip.compress(gzip.compress(b"RetiredBrand")), "nested.gz")
        self.assertFalse(result["passed"])
        self.assertEqual(result["errors"], [])
        self.assertTrue(any(x["kind"] == "content" and x["path"].endswith("!gzip-payload!gzip-payload")
                            for x in result["findings"]))


if __name__ == "__main__":
    unittest.main()
