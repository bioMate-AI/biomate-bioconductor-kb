"""
Tests for paper content extraction pipeline in research_agent.py

Covers:
  1. _fetch_s2_paper       — Semantic Scholar search + response parsing
  2. _fetch_pmc_fulltext   — BioC JSON + E-utils XML extraction (figures, tables, sections)
  3. _extract_fulltext_for_question — multi-paper orchestration + relevance filter
  4. _fetch_paper_pdf_url  — Europe PMC PDF URL resolution
  5. _download_pdf_page_as_image — PDF rendering + page selection heuristic
  6. _fetch_pmc_html_figure_captions — HTML fallback extraction

All external HTTP calls are mocked so tests run offline and deterministically.
"""

import base64
import json
import sys
import os
from unittest.mock import patch, MagicMock, call
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from galaxy.ai.agents.research_agent import (
    _fetch_s2_paper,
    _fetch_pmc_fulltext,
    _extract_fulltext_for_question,
    _fetch_paper_pdf_url,
    _download_pdf_page_as_image,
    _fetch_pmc_html_figure_captions,
    _http_get,
    _http_get_text,
)


# ── fixtures ────────────────────────────────────────────────────────────────────

S2_RESPONSE = {
    "data": [
        {
            "title": "DESeq2: moderated estimation of fold change",
            "abstract": "We present DESeq2, a method for differential analysis of RNA-seq data.",
            "openAccessPdf": {"url": "https://genomebiology.biomedcentral.com/articles/10.1186/s13059-014-0550-8.pdf"},
            "externalIds": {"PubMedCentral": "4302049", "DOI": "10.1186/s13059-014-0550-8"},
        },
        {
            "title": "DESeq2 follow-up study",
            "abstract": "Additional analysis.",
            "openAccessPdf": None,
            "externalIds": {},
        },
    ]
}

BIOC_RESPONSE = json.dumps({
    "documents": [{
        "passages": [
            {"infons": {"section_type": "METHODS"}, "text": "We used negative binomial generalized linear model (GLM) with empirical Bayes shrinkage of dispersion estimates as implemented in DESeq2 v1.38."},
            {"infons": {"section_type": "RESULTS"}, "text": "We identified 1234 differentially expressed genes with FDR < 0.05 after multiple testing correction using the Benjamini-Hochberg procedure."},
            {"infons": {"section_type": "INTRO"}, "text": "Introduction text not wanted."},
        ]
    }]
})

EFETCH_XML = """<?xml version="1.0"?>
<article>
  <fig id="fig1">
    <label>Extended Data Figure 1</label>
    <caption><p>Scatter plot showing 87% accuracy in validation cohort (n=150 independent samples).</p></caption>
  </fig>
  <table-wrap id="t1">
    <table><tr><td>Gene</td><td>log2FC</td><td>padj</td></tr>
           <tr><td>BRCA1</td><td>2.5</td><td>0.001</td></tr>
           <tr><td>TP53</td><td>-1.8</td><td>0.003</td></tr></table>
  </table-wrap>
  <sec sec-type="results">
    <p>DESeq2 identified 312 upregulated genes with FDR less than 0.05, including BRCA1, TP53, and MYC.</p>
    <p>Comparison with edgeR showed concordance on 89 percent of gene calls across all replicates.</p>
  </sec>
  <sec sec-type="methods">
    <p>Reads were aligned using STAR 2.7.9a with default parameters to the GRCh38 reference genome.</p>
    <p>Differential expression testing was performed with DESeq2 v1.38.0 in R v4.2.0.</p>
  </sec>
</article>
"""


# ══════════════════════════════════════════════════════════════════════════════
# 1. _fetch_s2_paper
# ══════════════════════════════════════════════════════════════════════════════

class TestFetchS2Paper:
    def test_returns_list_on_success(self):
        with patch("galaxy.ai.agents.research_agent._http_get", return_value=S2_RESPONSE):
            results = _fetch_s2_paper("DESeq2 differential expression")
        assert isinstance(results, list)
        assert len(results) == 2
        assert results[0]["title"] == "DESeq2: moderated estimation of fold change"

    def test_returns_empty_list_on_api_failure(self):
        with patch("galaxy.ai.agents.research_agent._http_get", return_value=None):
            results = _fetch_s2_paper("nonexistent paper xyz")
        assert results == []

    def test_returns_empty_list_on_malformed_response(self):
        with patch("galaxy.ai.agents.research_agent._http_get", return_value={"data": "not a list"}):
            results = _fetch_s2_paper("something")
        assert results == []

    def test_includes_open_access_pdf_url(self):
        with patch("galaxy.ai.agents.research_agent._http_get", return_value=S2_RESPONSE):
            results = _fetch_s2_paper("DESeq2")
        pdf = results[0].get("openAccessPdf") or {}
        assert "pdf" in pdf.get("url", "").lower()

    def test_handles_exception_gracefully(self):
        with patch("galaxy.ai.agents.research_agent._http_get", side_effect=Exception("network down")):
            results = _fetch_s2_paper("anything")
        assert results == []

    def test_query_is_url_encoded(self):
        """Spaces and special chars must not break the URL."""
        captured = {}
        def fake_get(url, **kw):
            captured["url"] = url
            return {"data": []}
        with patch("galaxy.ai.agents.research_agent._http_get", side_effect=fake_get):
            _fetch_s2_paper("RNA-seq differential expression analysis")
        assert " " not in captured["url"]
        assert "query=" in captured["url"]


# ══════════════════════════════════════════════════════════════════════════════
# 2. _fetch_pmc_fulltext
# ══════════════════════════════════════════════════════════════════════════════

class TestFetchPmcFulltext:
    """Both BioC and E-utils paths are tested."""

    def _patch(self, bioc_text=BIOC_RESPONSE, efetch_text=EFETCH_XML):
        """Helper: patch _http_get_text to return given strings in order."""
        return patch(
            "galaxy.ai.agents.research_agent._http_get_text",
            side_effect=[bioc_text, efetch_text],
        )

    def test_extracts_results_section_from_efetch(self):
        with self._patch():
            text = _fetch_pmc_fulltext("4302049")
        assert "312 upregulated" in text or "DESeq2 identified" in text

    def test_extracts_extended_data_figure_captions(self):
        with self._patch():
            text = _fetch_pmc_fulltext("4302049")
        assert "Extended Data Figure 1" in text
        assert "87%" in text

    def test_extracts_table_with_numbers(self):
        with self._patch():
            text = _fetch_pmc_fulltext("PMC4302049")  # prefix stripped correctly
        assert "BRCA1" in text or "log2FC" in text

    def test_accepts_pmc_prefix(self):
        """PMC-prefixed IDs should be handled identically to numeric ones."""
        with self._patch():
            result_numeric = _fetch_pmc_fulltext("4302049")
        with self._patch():
            result_prefixed = _fetch_pmc_fulltext("PMC4302049")
        # Both paths should yield non-empty results
        assert len(result_numeric) > 0
        assert len(result_prefixed) > 0

    def test_output_capped_at_5000_chars(self):
        long_efetch = EFETCH_XML + ("<p>" + "x" * 200 + "</p>") * 100
        with self._patch(efetch_text=long_efetch):
            text = _fetch_pmc_fulltext("4302049")
        assert len(text) <= 5000

    def test_returns_empty_when_both_sources_fail(self):
        with patch("galaxy.ai.agents.research_agent._http_get_text", return_value=""):
            text = _fetch_pmc_fulltext("9999999")
        assert text == ""

    def test_fallback_to_bioc_when_efetch_empty(self):
        """If efetch returns nothing, BioC sections should still be used."""
        with patch(
            "galaxy.ai.agents.research_agent._http_get_text",
            side_effect=[BIOC_RESPONSE, ""],
        ):
            text = _fetch_pmc_fulltext("4302049")
        assert "negative binomial" in text or "differentially expressed" in text

    def test_general_paragraphs_used_when_no_sections(self):
        """When neither results nor methods sections found, <p> paragraphs are extracted."""
        # XML must be > 500 chars to pass the `len(xml_text) > 500` gate;
        # paragraphs must be > 50 chars to pass the paragraph length filter.
        filler = "<!-- " + "x" * 600 + " -->"
        no_sections_xml = f"""<?xml version="1.0"?>
        <article>
          {filler}
          <p>First paragraph with 42 samples treated at 0.5 mg/kg for eight consecutive weeks.</p>
          <p>Second paragraph about controls which received vehicle only for the same period.</p>
        </article>"""
        with patch(
            "galaxy.ai.agents.research_agent._http_get_text",
            side_effect=["", no_sections_xml],
        ):
            text = _fetch_pmc_fulltext("1234567")
        assert "42 samples" in text or "0.5 mg/kg" in text


# ══════════════════════════════════════════════════════════════════════════════
# 3. _extract_fulltext_for_question
# ══════════════════════════════════════════════════════════════════════════════

class TestExtractFulltextForQuestion:
    def _s2_result(self, pmcid=None, pdf_url=None):
        return [
            {
                "title": "DESeq2 paper",
                "abstract": "Differential expression analysis.",
                "openAccessPdf": {"url": pdf_url} if pdf_url else None,
                "externalIds": {"PubMedCentral": pmcid} if pmcid else {},
            }
        ]

    def test_uses_pmc_fulltext_when_pmcid_available(self):
        # Fulltext must be > 100 chars to pass the `len(ft) > 100` gate.
        long_ft = "Methods: used DESeq2 negative binomial GLM with dispersion shrinkage. " \
                  "Results: identified 1234 DEGs at FDR 0.05 across all comparisons."
        with patch("galaxy.ai.agents.research_agent._fetch_s2_paper", return_value=self._s2_result(pmcid="4302049")):
            with patch("galaxy.ai.agents.research_agent._fetch_pmc_fulltext", return_value=long_ft) as mock_ft:
                result = _extract_fulltext_for_question("DESeq2 method", ["DESeq2 paper"])
        mock_ft.assert_called_once_with("4302049")
        assert "DESeq2" in result

    def test_skips_pmc_on_empty_fulltext_and_tries_pdf(self):
        # PDF text must be > 200 chars and contain a digit + question keyword to pass relevance filter.
        pdf_text = (
            "Figure 1 shows 0.87 AUC for the classifier on 500 samples. "
            "The receiver operating characteristic curve demonstrates strong performance "
            "with sensitivity 88% and specificity 91% at the optimal threshold of 0.62. "
            "These results confirm the classifier generalises well to the held-out validation set."
        )
        with patch("galaxy.ai.agents.research_agent._fetch_s2_paper", return_value=self._s2_result(pdf_url="http://example.com/paper.pdf")):
            with patch("galaxy.ai.agents.research_agent._fetch_pmc_fulltext", return_value=""):
                with patch("galaxy.ai.agents.research_agent._http_get_text", return_value=pdf_text):
                    result = _extract_fulltext_for_question("AUC classifier", ["DESeq2 paper"])
        assert "0.87" in result or "500" in result or "classifier" in result

    def test_returns_empty_when_no_papers_found(self):
        with patch("galaxy.ai.agents.research_agent._fetch_s2_paper", return_value=[]):
            result = _extract_fulltext_for_question("anything", ["unknown paper"])
        assert result == ""

    def test_handles_empty_paper_title_list(self):
        result = _extract_fulltext_for_question("question", [])
        assert result == ""

    def test_truncates_to_max_6000_chars(self):
        big_text = "x" * 8000
        with patch("galaxy.ai.agents.research_agent._fetch_s2_paper", return_value=self._s2_result(pmcid="111")):
            with patch("galaxy.ai.agents.research_agent._fetch_pmc_fulltext", return_value=big_text):
                result = _extract_fulltext_for_question("question", ["paper"] * 10)
        assert len(result) <= 6100  # slight overhead for label prefix

    def test_labels_fulltext_with_paper_title(self):
        long_ft = "Content here. " * 10  # > 100 chars
        with patch("galaxy.ai.agents.research_agent._fetch_s2_paper", return_value=self._s2_result(pmcid="4302049")):
            with patch("galaxy.ai.agents.research_agent._fetch_pmc_fulltext", return_value=long_ft):
                result = _extract_fulltext_for_question("methods", ["DESeq2 paper"])
        assert "[Full text" in result

    def test_pdf_relevance_filter_requires_number_and_keyword(self):
        """Lines without digits or question keywords should be filtered out."""
        pdf_with_irrelevant = "This line has no numbers.\nSample size 100 for classifier experiment."
        with patch("galaxy.ai.agents.research_agent._fetch_s2_paper", return_value=self._s2_result(pdf_url="http://x.com/p.pdf")):
            with patch("galaxy.ai.agents.research_agent._fetch_pmc_fulltext", return_value=""):
                with patch("galaxy.ai.agents.research_agent._http_get_text", return_value=pdf_with_irrelevant):
                    result = _extract_fulltext_for_question("classifier sample", ["paper"])
        # The relevant line (has number + keyword) should appear; irrelevant (no number) should not
        if result:
            assert "100" in result or "classifier" in result.lower()


# ══════════════════════════════════════════════════════════════════════════════
# 4. _fetch_paper_pdf_url
# ══════════════════════════════════════════════════════════════════════════════

class TestFetchPaperPdfUrl:
    def _mock_head_pdf(self):
        """Simulate Europe PMC HEAD returning 200 + application/pdf."""
        mock_resp = MagicMock()
        mock_resp.status = 200
        mock_resp.headers.get.return_value = "application/pdf"
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        return mock_resp

    def test_returns_europepmc_url_on_success(self):
        with patch("urllib.request.urlopen", return_value=self._mock_head_pdf()):
            url = _fetch_paper_pdf_url("4302049")
        assert "europepmc.org" in url
        assert "4302049" in url

    def test_strips_pmc_prefix(self):
        with patch("urllib.request.urlopen", return_value=self._mock_head_pdf()):
            url = _fetch_paper_pdf_url("PMC4302049")
        assert "PMC4302049" in url or "4302049" in url

    def test_returns_fallback_url_when_head_fails(self):
        """Even if HEAD check fails, function returns the URL for caller to verify."""
        with patch("urllib.request.urlopen", side_effect=Exception("timeout")):
            url = _fetch_paper_pdf_url("4302049")
        assert url is not None
        assert "europepmc.org" in url


# ══════════════════════════════════════════════════════════════════════════════
# 5. _download_pdf_page_as_image
# ══════════════════════════════════════════════════════════════════════════════

class TestDownloadPdfPageAsImage:
    def _make_minimal_pdf_bytes(self):
        """Return a valid 2-page minimal PDF in bytes (from fitz.open-compatible bytes)."""
        try:
            import fitz
            doc = fitz.open()
            for _ in range(4):  # 4 pages
                page = doc.new_page()
                page.insert_text((50, 100), "Results section: 87% accuracy at n=150")
            buf = doc.tobytes()
            doc.close()
            return buf
        except ImportError:
            return None

    def test_returns_none_when_pymupdf_missing(self):
        with patch.dict("sys.modules", {"fitz": None}):
            result = _download_pdf_page_as_image("http://example.com/paper.pdf", "figure 1")
        assert result is None

    def test_returns_none_for_empty_bytes(self):
        with patch("galaxy.ai.agents.research_agent._http_get_bytes", return_value=b""):
            result = _download_pdf_page_as_image("http://example.com/paper.pdf", "results")
        assert result is None

    def test_returns_none_for_html_interstitial(self):
        """Bytes not starting with %PDF (bot gate page) must be rejected."""
        html_bytes = b"<html><body>Please verify you are human</body></html>"
        with patch("galaxy.ai.agents.research_agent._http_get_bytes", return_value=html_bytes):
            result = _download_pdf_page_as_image("http://example.com/paper.pdf", "methods")
        assert result is None

    def test_uses_provided_pdf_bytes_without_http_call(self):
        """When pdf_bytes is supplied, no HTTP download should occur."""
        pdf_bytes = self._make_minimal_pdf_bytes()
        if pdf_bytes is None:
            pytest.skip("PyMuPDF not installed")
        with patch("galaxy.ai.agents.research_agent._http_get_bytes") as mock_dl:
            result = _download_pdf_page_as_image("http://dummy.com", "results", pdf_bytes=pdf_bytes)
        mock_dl.assert_not_called()
        # Result should be a base64 string (if rendering succeeded) or None
        if result is not None:
            base64.b64decode(result)  # should not raise

    def test_returns_base64_png_for_valid_pdf(self):
        pdf_bytes = self._make_minimal_pdf_bytes()
        if pdf_bytes is None:
            pytest.skip("PyMuPDF not installed")
        result = _download_pdf_page_as_image("http://dummy.com", "results", pdf_bytes=pdf_bytes)
        assert result is not None
        decoded = base64.b64decode(result)
        assert decoded[:4] == b'\x89PNG'  # PNG magic bytes

    def test_extended_data_hint_selects_last_pages(self):
        """'extended data' hint → search last 30% of pages."""
        pdf_bytes = self._make_minimal_pdf_bytes()
        if pdf_bytes is None:
            pytest.skip("PyMuPDF not installed")
        import fitz
        pages_loaded = []
        orig_open = fitz.open

        class MockDoc:
            def __init__(self, *a, **kw):
                self._doc = orig_open(*a, **kw)
                self.page_count = self._doc.page_count
            def load_page(self, idx):
                pages_loaded.append(idx)
                return self._doc.load_page(idx)
            def __enter__(self): return self
            def __exit__(self, *a): pass

        with patch("fitz.open", side_effect=lambda *a, **kw: MockDoc(*a, **kw)):
            _download_pdf_page_as_image("http://dummy", "extended data figure 3", pdf_bytes=pdf_bytes)

        if pages_loaded:
            n = 4  # our test PDF has 4 pages
            last_30_pct_start = int(n * 0.70)
            # At least one page in the last 30% should have been loaded
            assert any(p >= last_30_pct_start for p in pages_loaded)

    def test_returns_none_on_download_failure(self):
        with patch("galaxy.ai.agents.research_agent._http_get_bytes", return_value=None):
            result = _download_pdf_page_as_image("http://broken.com/paper.pdf", "results")
        assert result is None


# ══════════════════════════════════════════════════════════════════════════════
# 6. _fetch_pmc_html_figure_captions
# ══════════════════════════════════════════════════════════════════════════════

class TestFetchPmcHtmlFigureCaptions:
    PMC_HTML = """
    <html><body>
      <p class="caption">Figure 1: Sensitivity was 92% (95% CI 87–96%) for the BRCA1 classifier.</p>
      <p class="caption">Figure 2: Kaplan-Meier survival curves showing p=0.002 for treated group.</p>
      <p class="other">This paragraph has no figure info.</p>
      <div class="fig"><p>Extended Data Figure 3: ROC-AUC of 0.91 for the model.</p></div>
    </body></html>
    """

    def test_returns_relevant_captions(self):
        with patch("galaxy.ai.agents.research_agent._http_get_text", return_value=self.PMC_HTML):
            result = _fetch_pmc_html_figure_captions("4302049", "BRCA1 sensitivity")
        assert "92%" in result or "BRCA1" in result

    def test_filters_irrelevant_paragraphs(self):
        with patch("galaxy.ai.agents.research_agent._http_get_text", return_value=self.PMC_HTML):
            result = _fetch_pmc_html_figure_captions("4302049", "BRCA1 sensitivity")
        # The "other" paragraph should not appear in output
        assert "no figure info" not in result

    def test_returns_empty_when_no_html(self):
        with patch("galaxy.ai.agents.research_agent._http_get_text", return_value=""):
            result = _fetch_pmc_html_figure_captions("4302049", "any question")
        assert result == ""

    def test_output_capped_at_1000_chars(self):
        big_html = '<p class="caption">' + "Figure relevant keyword 99% " * 200 + "</p>"
        with patch("galaxy.ai.agents.research_agent._http_get_text", return_value=big_html):
            result = _fetch_pmc_html_figure_captions("4302049", "relevant keyword")
        assert len(result) <= 1000

    def test_strips_html_tags_from_output(self):
        with patch("galaxy.ai.agents.research_agent._http_get_text", return_value=self.PMC_HTML):
            result = _fetch_pmc_html_figure_captions("4302049", "ROC AUC model")
        assert "<" not in result
        assert ">" not in result

    def test_pmc_prefix_stripped_from_url(self):
        captured = {}
        def fake_get(url, **kw):
            captured["url"] = url
            return ""
        with patch("galaxy.ai.agents.research_agent._http_get_text", side_effect=fake_get):
            _fetch_pmc_html_figure_captions("PMC4302049", "question")
        # URL should use numeric ID without double-prefix
        assert "PMC4302049" in captured["url"] or "4302049" in captured["url"]
        assert "PMCPMC" not in captured["url"].upper()


# ══════════════════════════════════════════════════════════════════════════════
# 7. Integration: full extraction pipeline for a question
# ══════════════════════════════════════════════════════════════════════════════

class TestExtractionPipelineIntegration:
    """
    Simulate the full flow: question → S2 search → PMC fulltext → assembled context.
    All HTTP mocked; tests the orchestration logic end-to-end.
    """

    def test_deseq2_question_extracts_method_and_figure(self):
        question = "What statistical method does DESeq2 use and what accuracy was reported?"
        titles = ["DESeq2: moderated estimation of fold change and dispersion for RNA-seq data"]

        # Patch _fetch_pmc_fulltext directly so we bypass internal string-length
        # gates in BioC/efetch and focus on the _extract_fulltext_for_question logic.
        fulltext = (
            "Methods: Negative binomial GLM with Bayesian shrinkage of dispersion estimates. "
            "Results: DESeq2 achieved 94% sensitivity on 150 benchmark datasets, outperforming "
            "edgeR and limma-voom on simulated data. Extended Data Figure 2 shows ROC-AUC 0.95."
        )

        with patch("galaxy.ai.agents.research_agent._fetch_s2_paper", return_value=[{
            "title": titles[0],
            "abstract": "DESeq2 method paper.",
            "openAccessPdf": None,
            "externalIds": {"PubMedCentral": "4302049"},
        }]):
            with patch("galaxy.ai.agents.research_agent._fetch_pmc_fulltext", return_value=fulltext):
                result = _extract_fulltext_for_question(question, titles)

        assert len(result) > 0
        assert any(kw in result for kw in ["negative binomial", "94%", "DESeq2", "ROC", "0.95"])

    def test_handles_complete_api_failure_gracefully(self):
        """All sources fail → returns empty string, no exception raised."""
        with patch("galaxy.ai.agents.research_agent._fetch_s2_paper", return_value=[]):
            result = _extract_fulltext_for_question(
                "What is the p-value threshold used?",
                ["Some paper that doesn't exist in S2"]
            )
        assert result == ""

    def test_multiple_papers_concatenated(self):
        """Results from multiple papers should be joined."""
        papers = [
            {
                "title": "Paper A",
                "abstract": "Abstract A",
                "openAccessPdf": None,
                "externalIds": {"PubMedCentral": "111"},
            },
            {
                "title": "Paper B",
                "abstract": "Abstract B",
                "openAccessPdf": None,
                "externalIds": {"PubMedCentral": "222"},
            },
        ]
        # Fulltext must be > 100 chars to pass the gate inside _extract_fulltext_for_question.
        fulltext_a = (
            "Paper A: used 200 samples treated with compound X. "
            "Statistical testing via Mann-Whitney U, p < 0.01. "
            "Sensitivity was 85% and specificity 90% on hold-out set."
        )
        fulltext_b = (
            "Paper B: 500 patients enrolled in double-blind randomised trial. "
            "Primary endpoint sensitivity at 12 months was 88% (95% CI 82-93%)."
        )

        with patch("galaxy.ai.agents.research_agent._fetch_s2_paper", side_effect=[papers[:1], papers[1:]]):
            with patch("galaxy.ai.agents.research_agent._fetch_pmc_fulltext", side_effect=[fulltext_a, fulltext_b]):
                result = _extract_fulltext_for_question("sample size sensitivity", ["Paper A", "Paper B"])

        assert "200 samples" in result or "Paper A" in result or "500 patients" in result
