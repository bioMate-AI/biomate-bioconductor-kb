import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile
from verify_fastqc import verify


class ArtifactTests(unittest.TestCase):
    def fixture(self, root, count='100', duplicate=False):
        html, archive = root/'report.html', root/'report.zip'
        html.write_text('<html><body>FastQC</body></html>')
        with ZipFile(archive, 'w') as z:
            z.writestr('qc/fastqc_data.txt', '>>Basic Statistics\tpass\n#Measure\tValue\nTotal Sequences\t'+count+'\nSequence length\t100\n%GC\t50\n>>END_MODULE\n')
            z.writestr('qc/summary.txt', 'PASS\tBasic Statistics\tsynthetic.fastq\nFAIL\tOverrepresented sequences\tsynthetic.fastq\n')
            if duplicate:
                z.writestr('other/fastqc_data.txt', 'ambiguous')
        return html, archive

    def test_quality_failure_is_reported_without_hiding_execution_success(self):
        with tempfile.TemporaryDirectory() as d:
            result = verify(*self.fixture(Path(d)))
            self.assertTrue(result['artifact_validation_passed'])
            self.assertEqual(result['qc_modules'][1]['status'], 'FAIL')

    def test_wrong_counts_fail(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError, 'Total Sequences'):
                verify(*self.fixture(Path(d), count='99'))

    def test_ambiguous_archive_fails(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError, 'exactly one'):
                verify(*self.fixture(Path(d), duplicate=True))

    def test_non_html_fails(self):
        with tempfile.TemporaryDirectory() as d:
            html, archive = self.fixture(Path(d))
            html.write_text('server error')
            with self.assertRaisesRegex(ValueError, 'HTML'):
                verify(html, archive)
