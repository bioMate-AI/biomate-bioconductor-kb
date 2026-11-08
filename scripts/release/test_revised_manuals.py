#!/usr/bin/env python3
"""Content regression gates on built Word candidates; not visual QA."""
import hashlib
import io
import json
from pathlib import Path
import unittest
import zipfile

from docx import Document
from revise_onprem_manuals import same_except_comment_dates

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "docs/qa/20261107-onprem-readiness/revised-manuals"


class ManualRegressionTests(unittest.TestCase):
    def test_unchanged_candidates_ignore_dates_but_not_comment_content(self):
        def package(comment):
            target = io.BytesIO()
            with zipfile.ZipFile(target, 'w') as archive:
                archive.writestr('word/document.xml', '<body>unchanged</body>')
                archive.writestr('word/comments.xml', comment)
            return target.getvalue()
        original = package('<w:comment w:date="2026-11-07">review note</w:comment>')
        changed_date = package('<w:comment w:date="2026-11-08">review note</w:comment>')
        changed_content = package('<w:comment w:date="2026-11-08">different note</w:comment>')
        self.assertTrue(same_except_comment_dates(original, changed_date))
        self.assertFalse(same_except_comment_dates(original, changed_content))

    def setUp(self):
        self.journal = json.loads((OUTPUT / "changes.json").read_text())
        self.assertEqual(len(self.journal), 3)

    def test_journal_matches_every_candidate_and_comments_exist(self):
        for item in self.journal:
            path = ROOT / item["candidate_path"]
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), item["candidate_sha256"])
            self.assertGreater(len(item["changes"]), 10)
            with zipfile.ZipFile(path) as archive:
                self.assertIn("word/comments.xml", archive.namelist())

    def test_unsafe_legacy_commands_and_promises_not_left_in_body_or_tables(self):
        forbidden = ("grep LLM /app/biomate/.env", "printenv DEEPSEEK_API_KEY", "printenv DATABASE_URL",
                     "docker system prune -f", " down -v", "-exec rm -rf", "mkfs.ext4 /dev/vdb",
                     "token 一次性", "无停机时间约 30 秒", "80% 的问题", "同样完整支持",
                     "均已发布 ARM64 原生版本", "docs/ONPREM_SETUP.md", "--netfilter-mode=off")
        for item in self.journal:
            doc = Document(ROOT / item["candidate_path"])
            text = "\n".join(p.text for p in doc.paragraphs)
            text += "\n" + "\n".join(cell.text for table in doc.tables for row in table.rows for cell in row.cells)
            for term in forbidden:
                with self.subTest(document=item["document"], term=term):
                    self.assertNotIn(term, text)

    def test_all_table_headers_repeat_and_grids_fit_page(self):
        from docx.oxml.ns import qn
        for item in self.journal:
            doc = Document(ROOT / item["candidate_path"])
            section = doc.sections[0]
            available = int((section.page_width - section.left_margin - section.right_margin) / 635)
            for table in doc.tables:
                self.assertIsNotNone(table.rows[0]._tr.trPr.find(qn("w:tblHeader")))
                widths = [int(x.get(qn("w:w"))) for x in table._tbl.find(qn("w:tblGrid"))]
                self.assertGreater(sum(widths), 0)
                self.assertLessEqual(sum(widths), available)

    def test_remote_support_matches_private_credential_file_interfaces(self):
        item = next(x for x in self.journal if "远程支持" in x["document"])
        doc = Document(ROOT / item["candidate_path"])
        text = "\n".join(p.text for p in doc.paragraphs)
        self.assertIn("--key-file", text)
        self.assertIn("--token-file", text)
        self.assertIn("cloudflare/cloudflared@sha256:", text)
        for old in ("--key tskey", "--token <", "cloudflare --quick\n", "脚本会自动下载", "临时 Cloudflare 隧道已建立"):
            self.assertNotIn(old, text)


if __name__ == "__main__":
    unittest.main()
