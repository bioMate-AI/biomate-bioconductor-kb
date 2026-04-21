"""
ResearchAgent - Literature-backed research question answering

Provides evidence-based answers to research questions using:
- Literature search (PubMed, arXiv, Semantic Scholar)
- Benchmark knowledge for tool comparisons
- Scientific thinking skills for structured reasoning
- Citation generation and methods section writing

This agent addresses the SGI-Bench finding that LLMs need domain expertise
and literature grounding to provide scientifically accurate responses.
"""

import base64
import io
import logging
import os
import re
import urllib.request
import urllib.parse
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any
from concurrent.futures import ThreadPoolExecutor, as_completed
import json

log = logging.getLogger(__name__)


# ── Biomedical DB live lookups ─────────────────────────────────────────────────
# All APIs below are free REST services, no API key required.
# Called BEFORE the LLM synthesis so Claude receives real facts, not guesses.

def _http_get(url: str, headers: dict = None, timeout: int = 10) -> Optional[dict]:
    req = urllib.request.Request(url, headers=headers or {"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except Exception as e:
        log.debug(f"HTTP GET {url} failed: {e}")
        return None


def _http_get_text(url: str, headers: dict = None, timeout: int = 15) -> str:
    """Fetch a URL and return raw text (not parsed JSON)."""
    req = urllib.request.Request(url, headers=headers or {"Accept": "text/html,application/xhtml+xml,application/xml,text/plain"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            # Try to detect charset from headers
            content_type = r.headers.get("Content-Type", "")
            charset = "utf-8"
            if "charset=" in content_type:
                charset = content_type.split("charset=")[-1].strip().split(";")[0].strip()
            return raw.decode(charset, errors="replace")
    except Exception as e:
        log.debug(f"HTTP GET text {url} failed: {e}")
        return ""


def _fetch_s2_paper(title_or_query: str) -> list:
    """
    Search Semantic Scholar for papers matching the title/query.

    Returns a list of dicts with keys: title, abstract, openAccessPdf, externalIds.
    openAccessPdf is a dict with 'url' key when available.
    """
    try:
        q = urllib.parse.quote(title_or_query[:200])
        url = (
            f"https://api.semanticscholar.org/graph/v1/paper/search"
            f"?query={q}&fields=title,abstract,openAccessPdf,externalIds&limit=3"
        )
        result = _http_get(url, headers={"Accept": "application/json"}, timeout=15)
        if result and isinstance(result.get("data"), list):
            return result["data"]
    except Exception as e:
        log.debug(f"S2 paper search failed for '{title_or_query[:60]}': {e}")
    return []


def _fetch_pmc_fulltext(pmid_or_pmcid: str) -> str:
    """
    Fetch full-text for a PMC open-access paper via NCBI E-utils XML or BioC JSON.

    Extracts Methods + Results section text, returning up to 3000 chars.
    """
    # Normalise: strip leading "PMC" if present to get numeric ID
    pmcid = pmid_or_pmcid.strip()
    if pmcid.upper().startswith("PMC"):
        pmcid_num = pmcid[3:]
    else:
        pmcid_num = pmcid

    extracted = ""

    # --- Try BioC JSON (cleaner structure) ------------------------------------
    try:
        bioc_url = (
            f"https://www.ncbi.nlm.nih.gov/research/bionlp/RESTful/pmcoa.cgi"
            f"/BioC_json/PMC{pmcid_num}/unicode"
        )
        bioc_text = _http_get_text(bioc_url, timeout=15)
        if bioc_text and len(bioc_text) > 100:
            try:
                bioc_data = json.loads(bioc_text)
                passages = []
                # BioC JSON structure: documents[0].passages[*]
                docs = bioc_data if isinstance(bioc_data, list) else [bioc_data]
                for doc in docs:
                    for passage in doc.get("documents", [doc])[0].get("passages", []):
                        infons = passage.get("infons", {})
                        section = (infons.get("section_type") or infons.get("type") or "").lower()
                        text = passage.get("text", "")
                        if section in ("methods", "results", "methods and materials",
                                       "materials and methods", "study design"):
                            passages.append(text)
                if passages:
                    extracted = " ".join(passages)
            except Exception:
                pass  # fall through to XML approach
    except Exception as e:
        log.debug(f"PMC BioC fetch failed for {pmcid_num}: {e}")

    # --- E-utils efetch XML: primary source for Extended Data + tables -------
    # Always try this — it provides Extended Data figure captions and table data
    # that BioC JSON misses entirely. This is essential for SGI-style questions
    # that ask about specific numbers from Extended Data Figures.
    efetch_text = ""
    try:
        xml_url = (
            f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
            f"?db=pmc&id={pmcid_num}&rettype=xml&retmode=text"
        )
        xml_text = _http_get_text(xml_url, timeout=20)
        if xml_text and len(xml_text) > 500:
            parts: list = []

            # 1. Extended Data figure captions (highest priority for SGI questions)
            figs = re.findall(r'<fig[^>]*>(.*?)</fig>', xml_text, re.DOTALL)
            for fig in figs:
                label = re.search(r'<label>(.*?)</label>', fig)
                cap = re.search(r'<caption>(.*?)</caption>', fig, re.DOTALL)
                if label and cap:
                    lbl = re.sub(r'<[^>]+>', '', label.group(1)).strip()
                    cap_text = re.sub(r'<[^>]+>', ' ', cap.group(1))
                    cap_text = re.sub(r'\s+', ' ', cap_text).strip()
                    parts.append(f"[{lbl}] {cap_text[:400]}")

            # 2. Tables — contain actual numerical results
            tables = re.findall(r'<table-wrap[^>]*>(.*?)</table-wrap>', xml_text, re.DOTALL)
            for tbl in tables:
                clean = re.sub(r'<[^>]+>', ' ', tbl)
                clean = re.sub(r'\s+', ' ', clean).strip()
                if re.search(r'\d', clean):  # only include tables with numbers
                    parts.append(f"[Table] {clean[:500]}")

            # 3. Results + Methods paragraphs
            result_secs = re.findall(
                r'<sec[^>]*sec-type=["\']results?["\'][^>]*>(.*?)</sec>',
                xml_text, re.DOTALL | re.IGNORECASE
            )
            method_secs = re.findall(
                r'<sec[^>]*sec-type=["\'](?:methods?|materials[^"\']*)["\'][^>]*>(.*?)</sec>',
                xml_text, re.DOTALL | re.IGNORECASE
            )
            for sec in (result_secs + method_secs)[:6]:
                clean = re.sub(r'<[^>]+>', ' ', sec)
                clean = re.sub(r'\s+', ' ', clean).strip()
                parts.append(clean[:500])

            # 4. If no sections found, use general paragraphs
            if not result_secs and not method_secs:
                paras = re.findall(r'<p[^>]*>(.*?)</p>', xml_text, re.DOTALL)[:20]
                for p in paras:
                    clean = re.sub(r'<[^>]+>', ' ', p)
                    clean = re.sub(r'\s+', ' ', clean).strip()
                    if len(clean) > 50:
                        parts.append(clean[:300])

            efetch_text = "\n".join(parts)
    except Exception as e:
        log.debug(f"PMC efetch XML failed for {pmcid_num}: {e}")

    # Merge: prefer efetch (has Extended Data) but supplement with BioC text
    if efetch_text and extracted:
        combined = f"{efetch_text}\n\n[BioC sections]\n{extracted}"
    elif efetch_text:
        combined = efetch_text
    else:
        combined = extracted

    return combined[:5000]


def _extract_fulltext_for_question(question: str, paper_titles: list) -> str:
    """
    For each paper title, attempt to retrieve full-text excerpts via Semantic Scholar
    and PMC Open Access.

    Returns combined relevant text (max 4000 chars total).
    """
    collected: list = []
    total_chars = 0
    MAX_TOTAL = 6000  # increased: efetch XML includes Extended Data captions + tables

    for title in paper_titles[:5]:
        if total_chars >= MAX_TOTAL:
            break
        if not title or not title.strip():
            continue

        try:
            s2_papers = _fetch_s2_paper(title)
        except Exception:
            s2_papers = []

        for paper in s2_papers[:2]:
            if total_chars >= MAX_TOTAL:
                break

            paper_title = paper.get("title", "")
            external_ids = paper.get("externalIds") or {}
            open_pdf = paper.get("openAccessPdf") or {}

            # Try PMC full-text first (structured sections)
            pmcid = external_ids.get("PubMedCentral") or external_ids.get("PMC")
            if pmcid:
                try:
                    ft = _fetch_pmc_fulltext(str(pmcid))
                    if ft and len(ft) > 100:
                        snippet = ft[: MAX_TOTAL - total_chars]
                        collected.append(
                            f"[Full text — {paper_title or title}]\n{snippet}"
                        )
                        total_chars += len(snippet)
                        continue  # got PMC text, skip PDF for this paper
                except Exception:
                    pass

            # Fall back to PDF text if available — fetch first 8 KB and scan for key numbers
            pdf_url = open_pdf.get("url", "")
            if pdf_url and total_chars < MAX_TOTAL:
                try:
                    # Fetch as text (PDFs fetched this way typically return binary,
                    # but some S2 links resolve to HTML/text abstracts)
                    pdf_text = _http_get_text(pdf_url, timeout=15)
                    if pdf_text and len(pdf_text) > 200:
                        # Crude relevance filter: look for numbers/percentages near question keywords
                        q_words = set(re.findall(r'\b\w{4,}\b', question.lower()))
                        lines = pdf_text.split('\n')
                        relevant_lines = [
                            ln for ln in lines
                            if re.search(r'\d', ln) and
                            any(w in ln.lower() for w in q_words)
                        ]
                        snippet_text = " ".join(relevant_lines[:20])[:MAX_TOTAL - total_chars]
                        if snippet_text:
                            collected.append(
                                f"[PDF excerpt — {paper_title or title}]\n{snippet_text}"
                            )
                            total_chars += len(snippet_text)
                except Exception:
                    pass

    return "\n\n".join(collected)


def _http_get_bytes(url: str, headers: dict = None, timeout: int = 30) -> Optional[bytes]:
    """Fetch a URL and return raw bytes (for PDF download)."""
    req = urllib.request.Request(
        url,
        headers=headers or {"User-Agent": "Mozilla/5.0", "Accept": "application/pdf,*/*"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read()
    except Exception as e:
        log.debug(f"HTTP GET bytes {url} failed: {e}")
        return None


def _fetch_paper_pdf_url(pmcid: str) -> Optional[str]:
    """
    Try to get a PDF URL for a PMC paper.

    Uses Europe PMC's direct PDF render endpoint which returns actual PDF bytes
    (unlike NCBI which shows an HTML interstitial page before the download).

    Returns the URL string if a PDF is accessible, else None.
    """
    pmcid_num = pmcid.strip().lstrip("PMCpmc")

    # 1. Europe PMC direct PDF render — returns actual PDF bytes, no interstitial
    epmc_url = f"https://europepmc.org/backend/ptpmcrender.fcgi?accid=PMC{pmcid_num}&blobtype=pdf"
    try:
        req = urllib.request.Request(
            epmc_url,
            method="HEAD",
            headers={"User-Agent": "Mozilla/5.0 BioMate/1.0"},
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            ct = r.headers.get("Content-Type", "")
            if r.status == 200 and "pdf" in ct.lower():
                return epmc_url
    except Exception:
        pass

    # 2. Fallback: try Europe PMC without HEAD check (some servers block HEAD)
    # Return the URL and let the downloader verify by checking bytes
    return epmc_url


def _download_pdf_page_as_image(pdf_url: str, page_hint: str, pdf_bytes: Optional[bytes] = None) -> Optional[str]:
    """
    Download a PDF and render a relevant page to a base64 PNG string.

    Uses PyMuPDF (fitz) to render pages. When the page_hint mentions
    'extended data', 'supplementary', or 'figure', we look in the last 30%
    of pages (where extended data figures typically live), otherwise we scan
    results-section pages.

    Returns base64-encoded PNG string or None on any error.
    """
    try:
        import fitz  # PyMuPDF
    except ImportError:
        log.debug("PyMuPDF (fitz) not available — cannot render PDF pages")
        return None

    try:
        if pdf_bytes is None:
            pdf_bytes = _http_get_bytes(pdf_url, timeout=30)
        if not pdf_bytes or len(pdf_bytes) < 1000:
            return None
        # Reject HTML interstitial pages (PoW challenges, bot gates)
        if pdf_bytes[:4] not in (b'%PDF', b'\x25\x50\x44\x46'):
            log.debug(f"PDF URL returned non-PDF content (got {pdf_bytes[:20]!r}): {pdf_url}")
            return None

        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        n_pages = doc.page_count
        if n_pages == 0:
            return None

        hint_lower = page_hint.lower()
        is_extended = any(kw in hint_lower for kw in ("extended data", "supplementary", "figure", "fig"))

        if is_extended:
            # Last 30% of pages (extended data figures)
            start = max(0, int(n_pages * 0.70))
            candidate_pages = list(range(start, n_pages))
        else:
            # Middle section — skip cover/abstract (first 10%) and references (last 10%)
            start = max(0, int(n_pages * 0.10))
            end = max(start + 1, int(n_pages * 0.90))
            candidate_pages = list(range(start, end))

        # Extract text per candidate page and pick most relevant by keyword overlap
        q_words = set(re.findall(r'\b\w{4,}\b', page_hint.lower()))
        best_page_idx = candidate_pages[0] if candidate_pages else 0
        best_score = -1

        for idx in candidate_pages[:20]:  # Check at most 20 pages
            try:
                page = doc.load_page(idx)
                text = page.get_text("text")
                score = sum(1 for w in q_words if w in text.lower())
                if score > best_score:
                    best_score = score
                    best_page_idx = idx
            except Exception:
                continue

        # Render the best page at 150 DPI → PNG
        page = doc.load_page(best_page_idx)
        mat = fitz.Matrix(150 / 72, 150 / 72)  # 150 DPI
        pix = page.get_pixmap(matrix=mat, colorspace=fitz.csRGB)
        png_bytes = pix.tobytes("png")
        return base64.b64encode(png_bytes).decode("ascii")

    except Exception as e:
        log.debug(f"PDF page render failed for {pdf_url}: {e}")
        return None


def _fetch_pmc_html_figure_captions(pmcid: str, question: str) -> str:
    """
    Fallback: fetch PMC HTML page and extract figure captions / table values
    relevant to the question. Used when PDF rendering is unavailable.

    Returns a text snippet (max 1000 chars) or empty string.
    """
    pmcid_num = pmcid.strip().lstrip("PMCpmc")
    url = f"https://www.ncbi.nlm.nih.gov/pmc/articles/PMC{pmcid_num}/"
    html = _http_get_text(
        url,
        headers={"User-Agent": "Mozilla/5.0", "Accept": "text/html"},
        timeout=15,
    )
    if not html:
        return ""

    # Extract figure caption blocks
    fig_captions = re.findall(
        r'<p[^>]*class="[^"]*caption[^"]*"[^>]*>(.*?)</p>',
        html, re.DOTALL | re.IGNORECASE
    )
    # Also grab <div class="fig"> or <figure> blocks
    fig_blocks = re.findall(
        r'<(?:div[^>]*class="[^"]*fig[^"]*"|figure)[^>]*>(.*?)</(?:div|figure)>',
        html, re.DOTALL | re.IGNORECASE
    )

    all_text_parts = fig_captions + fig_blocks
    q_words = set(re.findall(r'\b\w{4,}\b', question.lower()))
    relevant = []
    for part in all_text_parts:
        clean = re.sub(r'<[^>]+>', ' ', part)
        clean = re.sub(r'\s+', ' ', clean).strip()
        if clean and any(w in clean.lower() for w in q_words):
            relevant.append(clean)

    return " ".join(relevant)[:1000]


def _http_post(url: str, payload: dict, timeout: int = 10) -> Optional[Any]:
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data,
                                  headers={"Content-Type": "application/json", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except Exception as e:
        log.debug(f"HTTP POST {url} failed: {e}")
        return None


def lookup_ensembl_ids(ensg_ids: List[str]) -> Dict[str, Any]:
    """Ensembl REST POST lookup/id — returns gene symbol, biotype, description for each ENSG ID."""
    if not ensg_ids:
        return {}
    result = _http_post(
        "https://rest.ensembl.org/lookup/id",
        {"ids": ensg_ids[:50], "expand": 0},
        timeout=15,
    )
    if not isinstance(result, dict):
        return {}
    out = {}
    for ensg, info in result.items():
        if isinstance(info, dict):
            out[ensg] = {
                "symbol": info.get("display_name") or info.get("id"),
                "description": info.get("description", ""),
                "biotype": info.get("biotype", ""),
                "chromosome": info.get("seq_region_name", ""),
            }
    return out


def lookup_mygene(identifiers: List[str], fields: str = "symbol,name,summary,OMIM") -> List[dict]:
    """MyGene.info — gene annotation including OMIM disease IDs.
    Accepts ENSG IDs, Entrez IDs, or gene symbols (auto-detects via /query endpoint for symbols).
    """
    if not identifiers:
        return []
    results = []
    for ident in identifiers[:10]:
        # ENSG IDs and numeric IDs → direct lookup via POST
        if re.match(r"^ENSG\d+$", ident) or re.match(r"^\d+$", ident):
            r = _http_post(
                "https://mygene.info/v3/gene",
                {"ids": [ident], "fields": fields, "species": "human"},
                timeout=10,
            )
            if isinstance(r, list):
                results.extend(r)
        else:
            # Gene symbol → query endpoint
            url = (f"https://mygene.info/v3/query?q=symbol:{urllib.parse.quote(ident)}"
                   f"&fields={urllib.parse.quote(fields)}&species=human&size=1")
            r = _http_get(url, timeout=10)
            if r and r.get("hits"):
                results.extend(r["hits"])
    return results


def lookup_hpo_genes(hp_terms: List[str], limit: int = 20) -> Dict[str, List[dict]]:
    """Monarch Initiative API — for each HP term return associated genes (gene has_phenotype HP)."""
    out: Dict[str, List[dict]] = {}
    for hp in hp_terms[:5]:
        url = (
            f"https://api-v3.monarchinitiative.org/v3/api/association/all"
            f"?object={urllib.parse.quote(hp)}"
            f"&subject_category=biolink%3AGene"
            f"&limit={limit}&offset=0"
        )
        data = _http_get(url, timeout=12)
        if data and "items" in data:
            genes = []
            for item in data["items"]:
                gene_id = item.get("subject", "")
                gene_name = item.get("subject_label", "")
                genes.append({"id": gene_id, "symbol": gene_name,
                              "predicate": item.get("predicate", "")})
            out[hp] = genes
    return out


def lookup_clinvar_gene(gene_symbol: str, max_results: int = 5) -> List[dict]:
    """NCBI ClinVar E-utils — pathogenic variants for a gene symbol."""
    search_url = (
        f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
        f"?db=clinvar&term={urllib.parse.quote(gene_symbol)}%5Bgene%5D+pathogenic%5BCLNSIG%5D"
        f"&retmax={max_results}&retmode=json"
    )
    search = _http_get(search_url, timeout=10)
    if not search:
        return []
    ids = search.get("esearchresult", {}).get("idlist", [])
    if not ids:
        return []
    summary_url = (
        f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi"
        f"?db=clinvar&id={','.join(ids)}&retmode=json"
    )
    summary = _http_get(summary_url, timeout=10)
    if not summary:
        return []
    results = []
    for uid, doc in summary.get("result", {}).items():
        if uid == "uids":
            continue
        results.append({
            "variant_id": uid,
            "title": doc.get("title", ""),
            "clinical_significance": doc.get("clinical_significance", {}).get("description", ""),
            "condition": doc.get("trait_set", [{}])[0].get("trait_name", "") if doc.get("trait_set") else "",
        })
    return results


def lookup_omim_gene(gene_symbol: str) -> List[dict]:
    """NCBI Gene → MIM IDs via mygene.info (OMIM API key not required this way)."""
    result = _http_get(
        f"https://mygene.info/v3/query?q=symbol:{urllib.parse.quote(gene_symbol)}"
        f"&fields=symbol,name,omim,OMIM&species=human&size=3",
        timeout=10,
    )
    if not result:
        return []
    hits = result.get("hits", [])
    out = []
    for h in hits:
        omim_ids = h.get("OMIM") or h.get("omim") or []
        if isinstance(omim_ids, str):
            omim_ids = [omim_ids]
        out.append({"symbol": h.get("symbol", ""), "name": h.get("name", ""), "omim_ids": omim_ids})
    return out


# ── Improvement A: HPO gene phenotype scorer ──────────────────────────────────

def _lookup_hpo_associated_genes(hp_terms: list) -> dict:
    """Return {HP:XXXXXXX: [gene_symbol1, gene_symbol2, ...]} via Monarch API."""
    result = {}
    for hp in hp_terms[:10]:  # cap at 10 HPO terms
        try:
            url = (
                f"https://api-v3.monarchinitiative.org/v3/api/association/all"
                f"?object={urllib.parse.quote(hp)}"
                f"&subject_category=biolink%3AGene"
                f"&limit=20&offset=0"
            )
            data = _http_get(url, timeout=8)
            if data and "items" in data:
                genes = [item.get("subject_label", "") for item in data["items"] if item.get("subject_label")]
                result[hp] = genes
            else:
                result[hp] = []
        except Exception:
            result[hp] = []
    return result


def _score_ensg_by_hpo(ensg_info: dict, hpo_gene_map: dict) -> dict:
    """
    Score candidate ENSG IDs by how many HPO terms map to them.

    ensg_info: {ensg_id: {"symbol": ..., ...}}
    hpo_gene_map: {hp_term: [gene_symbol1, ...]}
    Returns: {ensg_id: {"symbol": ..., "hpo_score": int, "matching_hps": [...]}}
    """
    scores = {}
    total_hps = len(hpo_gene_map)
    for ensg_id, info in ensg_info.items():
        symbol = info.get("symbol", "")
        if not symbol:
            continue
        matching_hps = []
        for hp, genes in hpo_gene_map.items():
            if symbol.upper() in [g.upper() for g in genes]:
                matching_hps.append(hp)
        scores[ensg_id] = {
            "symbol": symbol,
            "hpo_score": len(matching_hps),
            "total_hps": total_hps,
            "matching_hps": matching_hps,
        }
    # Sort by score descending
    return dict(sorted(scores.items(), key=lambda x: -x[1]["hpo_score"]))


# ── Improvement B: OMIM disease phenotype scoring ────────────────────────────

def lookup_omim_disease_phenotypes(omim_id: str) -> list:
    """Return HPO terms associated with an OMIM disease via Monarch."""
    try:
        url = (
            f"https://api-v3.monarchinitiative.org/v3/api/association/all"
            f"?subject=OMIM%3A{urllib.parse.quote(str(omim_id))}"
            f"&object_category=biolink%3APhenotypicFeature"
            f"&limit=30&offset=0"
        )
        data = _http_get(url, timeout=8)
        if data and "items" in data:
            return [item.get("object", "") for item in data["items"] if item.get("object", "").startswith("HP:")]
        return []
    except Exception:
        return []


def _score_omim_diseases_by_hpo_overlap(
    gene_omim_results: list,
    patient_hp_terms: list,
) -> list:
    """
    For each gene in gene_omim_results, fetch OMIM disease phenotypes and score
    overlap with patient HPO terms.

    gene_omim_results: output of lookup_omim_gene()
    patient_hp_terms: list of HP:XXXXXXX strings from the question
    Returns: list of dicts sorted by overlap score desc
    """
    if not patient_hp_terms:
        return []
    patient_hp_set = set(patient_hp_terms)
    scored = []
    for gene_entry in gene_omim_results[:3]:  # limit to avoid long waits
        symbol = gene_entry.get("symbol", "")
        for omim_id in (gene_entry.get("omim_ids") or [])[:3]:
            disease_hps = lookup_omim_disease_phenotypes(str(omim_id))
            overlap = patient_hp_set & set(disease_hps)
            scored.append({
                "gene": symbol,
                "omim_id": omim_id,
                "overlap_count": len(overlap),
                "total_patient_hps": len(patient_hp_set),
                "overlapping_hps": sorted(overlap),
                "disease_total_hps": len(disease_hps),
            })
    scored.sort(key=lambda x: -x["overlap_count"])
    return scored


# ── Improvement C: CRISPR screen literature search ───────────────────────────

def _search_crispr_screen_pubmed(condition: str) -> str:
    """Search PubMed for CRISPR screen papers matching condition, return top abstracts."""
    try:
        query = urllib.parse.quote(f"CRISPR screen {condition[:80]} fitness")
        url = (
            f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
            f"?db=pubmed&term={query}&retmax=3&retmode=json"
        )
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=8) as r:
            ids = json.loads(r.read()).get("esearchresult", {}).get("idlist", [])
        if not ids:
            return ""
        # Fetch abstracts
        id_str = ",".join(ids[:3])
        url2 = (
            f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
            f"?db=pubmed&id={id_str}&rettype=abstract&retmode=text"
        )
        req2 = urllib.request.Request(url2)
        with urllib.request.urlopen(req2, timeout=10) as r:
            return r.read().decode("utf-8", errors="ignore")[:3000]
    except Exception:
        return ""


def lookup_gwas_catalog(phenotype: str, candidate_rsids: List[str]) -> Dict[str, Any]:
    """
    Query GWAS Catalog REST API for each candidate rsID and rank by association
    strength with the given phenotype.

    Returns a dict with:
      - top_rsid: str — best-scoring rsID (lowest p-value for phenotype-matching associations)
      - ranked: List[dict] — [{rsid, pvalue_exp, pvalue_mantissa, trait, mapped_gene}, ...]
      - phenotype_matches: List[dict] — associations where trait name overlaps with phenotype
    """
    if not candidate_rsids:
        return {}

    phenotype_words = set(re.findall(r"\b\w{4,}\b", phenotype.lower()))
    results: List[Dict[str, Any]] = []

    for rsid in candidate_rsids[:20]:   # cap at 20 to avoid timeout
        rsid = rsid.strip()
        url = (
            f"https://www.ebi.ac.uk/gwas/rest/api/singleNucleotidePolymorphisms"
            f"/{urllib.parse.quote(rsid)}/associations?projection=associationBySnp"
        )
        data = _http_get(url, timeout=12)
        if not data:
            continue
        assocs = (data.get("_embedded") or {}).get("associations") or []
        for assoc in assocs[:10]:   # top 10 associations per rsID
            exp = assoc.get("pvalueExponent", 0)
            mant = assoc.get("pvalueMantissa", 1.0)
            # Collect trait names
            efo_traits = [
                t.get("trait", "") for t in (assoc.get("efoTraits") or [])
            ]
            mapped_genes = []
            for locus in (assoc.get("loci") or []):
                for mg in (locus.get("strongestRiskAlleles") or []):
                    pass   # not gene info here
                for mg in (locus.get("authorReportedMappedGenes") or []):
                    s = mg.get("geneName", "")
                    if s:
                        mapped_genes.append(s)
            trait_str = "; ".join(efo_traits)
            trait_words = set(re.findall(r"\b\w{4,}\b", trait_str.lower()))
            overlap = len(phenotype_words & trait_words)
            results.append({
                "rsid": rsid,
                "pvalue_exp": exp,
                "pvalue_mantissa": mant,
                "trait": trait_str,
                "mapped_genes": mapped_genes,
                "phenotype_overlap": overlap,
            })

    if not results:
        return {}

    # Sort: primary = phenotype overlap (desc), secondary = p-value exponent (asc)
    results.sort(key=lambda x: (-x["phenotype_overlap"], x["pvalue_exp"], x["pvalue_mantissa"]))
    phenotype_matches = [r for r in results if r["phenotype_overlap"] > 0]

    return {
        "top_rsid": results[0]["rsid"],
        "ranked": results[:10],
        "phenotype_matches": phenotype_matches[:5],
    }


def lookup_open_targets_gene(rsid_or_variant: str, phenotype: str = "") -> Dict[str, Any]:
    """
    Query Open Targets Genetics for L2G (locus-to-gene) scores given a lead rsID.
    Returns top gene candidates ranked by L2G score.
    Falls back to GWAS Catalog mapped genes if Open Targets is unavailable.
    """
    results: Dict[str, Any] = {}

    # Try Open Targets Genetics API (GraphQL)
    ot_query = """
    query L2G($variantId: String!) {
      genesForVariantSchema(variantId: $variantId) {
        gene { id symbol }
        overallScore
      }
    }
    """
    # Convert rsID → chr_pos_ref_alt via GWAS Catalog first
    variant_url = (
        f"https://www.ebi.ac.uk/gwas/rest/api/singleNucleotidePolymorphisms"
        f"/{urllib.parse.quote(rsid_or_variant)}"
    )
    snp_data = _http_get(variant_url, timeout=10)
    if snp_data:
        locations = snp_data.get("locations") or []
        chr_name = ""
        chr_pos = ""
        if locations:
            loc = locations[0]
            chr_name = loc.get("chromosomeName", "")
            chr_pos = str(loc.get("chromosomePosition", ""))
        if chr_name and chr_pos:
            results["chromosomal_location"] = f"chr{chr_name}:{chr_pos}"
        # Mapped genes directly from GWAS Catalog
        mapped = snp_data.get("genomicContexts") or []
        gene_candidates = []
        for ctx in mapped[:5]:
            gene = ctx.get("gene") or {}
            gene_name = gene.get("geneName", "")
            if gene_name:
                gene_candidates.append({
                    "symbol": gene_name,
                    "distance": ctx.get("distance", 9999999),
                    "is_closest_gene": ctx.get("isClosestGene", False),
                    "is_intergenic": ctx.get("isIntergenic", False),
                })
        gene_candidates.sort(key=lambda x: (not x["is_closest_gene"], x["distance"]))
        if gene_candidates:
            results["mapped_genes"] = gene_candidates
            results["top_gene"] = gene_candidates[0]["symbol"]

    return results


def lookup_gwas_catalog_genes(phenotype: str, candidate_genes: List[str]) -> Dict[str, Any]:
    """
    Given a GWAS phenotype and a list of candidate gene symbols, find which genes
    have the most evidence for that phenotype via:
      1. Open Targets Platform (gene-disease association scores) — primary source
      2. GWAS Catalog Solr for EFO trait ID then study associations — fallback

    Returns:
      - top_gene: str — best-scoring candidate gene
      - ranked: List[dict] — [{gene, score, source, traits}, ...]
      - top_ot_genes: List[str] — top Open Targets genes for context (not filtered to candidates)
    """
    if not candidate_genes or not phenotype:
        return {}

    candidate_upper = {g.upper(): g for g in candidate_genes}
    gene_scores: Dict[str, float] = {}
    top_ot_genes: List[str] = []

    # ── Step 1: Get EFO ID from GWAS Catalog Solr ────────────────────────────
    solr_url = (
        f"https://www.ebi.ac.uk/gwas/api/search?q={urllib.parse.quote(phenotype)}"
        f"&facet=efo&max=5"
    )
    solr_data = _http_get(solr_url, timeout=12)
    efo_ids: List[str] = []
    if solr_data:
        docs = (solr_data.get("response") or {}).get("docs") or []
        for doc in docs[:3]:
            sf = doc.get("shortForm", [])
            if isinstance(sf, list):
                sf = sf[0] if sf else ""
            if sf and isinstance(sf, str) and sf.startswith("EFO"):
                efo_ids.append(sf)

    # ── Step 2: Open Targets Platform — gene-disease association scores ───────
    for efo_id in (efo_ids[:2] or [""]):
        if not efo_id:
            continue
        ot_query = (
            'query($efo: String!) { disease(efoId: $efo) { '
            'associatedTargets(page: {index: 0, size: 50}) { '
            'rows { target { approvedSymbol } score } } } }'
        )
        payload = {"query": ot_query, "variables": {"efo": efo_id}}
        ot_result = _http_post(
            "https://api.platform.opentargets.org/api/v4/graphql",
            payload, timeout=15
        )
        if not ot_result:
            continue
        rows = (
            (ot_result.get("data") or {})
            .get("disease", {})
            .get("associatedTargets", {})
            .get("rows", [])
        )
        for row in rows:
            sym = row.get("target", {}).get("approvedSymbol", "")
            score = float(row.get("score") or 0)
            top_ot_genes.append(sym)
            if sym.upper() in candidate_upper:
                orig = candidate_upper[sym.upper()]
                gene_scores[orig] = max(gene_scores.get(orig, 0.0), score)
        if rows:
            break   # got results; no need to try second EFO

    # ── Step 3: GWAS Catalog study-level gene lookup (fallback) ─────────────
    if not gene_scores and efo_ids:
        study_url = (
            f"https://www.ebi.ac.uk/gwas/rest/api/studies/search/findByDiseaseTrait"
            f"?diseaseTrait={urllib.parse.quote(phenotype)}&size=5"
        )
        study_data = _http_get(study_url, timeout=12)
        if study_data:
            studies = (study_data.get("_embedded") or {}).get("studies") or []
            for study in studies[:3]:
                acc = study.get("accessionId", "")
                if not acc:
                    continue
                assoc_url = (
                    f"https://www.ebi.ac.uk/gwas/rest/api/studies/{acc}/associations?size=30"
                )
                assoc_data = _http_get(assoc_url, timeout=12)
                if not assoc_data:
                    continue
                assocs = (assoc_data.get("_embedded") or {}).get("associations") or []
                for assoc in assocs:
                    p_exp = assoc.get("pvalueExponent", 0) or 0
                    # p-value-based score: lower exponent = stronger evidence
                    pval_score = max(0.0, (-p_exp) / 50.0)   # normalise to ~0–1
                    for locus in (assoc.get("loci") or []):
                        for gene in (locus.get("authorReportedGenes") or []):
                            gname = gene.get("geneName", "").upper()
                            if gname in candidate_upper:
                                orig = candidate_upper[gname]
                                gene_scores[orig] = max(gene_scores.get(orig, 0.0), pval_score)

    if not gene_scores:
        return {"top_ot_genes": top_ot_genes[:15]}

    ranked = sorted(
        [{"gene": g, "score": s, "source": "open_targets_or_gwas"} for g, s in gene_scores.items()],
        key=lambda x: -x["score"],
    )
    return {
        "top_gene": ranked[0]["gene"],
        "ranked": ranked[:10],
        "top_ot_genes": top_ot_genes[:15],
    }


def extract_biomedical_identifiers(text: str) -> Dict[str, List[str]]:
    """Pull HP codes, ENSG IDs, gene symbols, OMIM IDs from free text."""
    return {
        "hp_terms": re.findall(r"\bHP:\d{7}\b", text),
        "ensg_ids": re.findall(r"\bENSG\d{10,}\b", text),
        "omim_ids": re.findall(r"\b(?:OMIM[:\s#]?)?(\d{6})\b", text),
        # Simple heuristic: ALL-CAPS 2-15 char tokens that look like gene symbols
        "gene_symbols": list(dict.fromkeys(
            g for g in re.findall(r"\b([A-Z][A-Z0-9]{1,14})\b", text)
            if not g.startswith("HP") and g not in {
                "DNA", "RNA", "PCR", "NGS", "WGS", "WES", "SNP", "CNV", "VCF",
                "BAM", "SAM", "FASTQ", "QC", "GC", "AT", "OR", "NO", "DO", "IF",
                "IN", "IS", "IT", "ON", "THE", "FOR", "AND", "OR", "NOT", "ANY",
                "ALL", "YES", "TSV", "CSV", "JSON", "ID", "NA", "NF", "DE",
                "ORR", "DCB", "IHC", "PD", "TC", "IC", "KM", "CI", "HR",
            }
        ))[:10],
    }


@dataclass
class Citation:
    """A literature citation."""
    title: str
    authors: List[str]
    year: int
    journal: str
    doi: Optional[str] = None
    pmid: Optional[str] = None
    abstract: Optional[str] = None
    relevance_score: float = 0.0


@dataclass
class ResearchResponse:
    """Response from the ResearchAgent."""
    answer: str
    citations: List[Citation] = field(default_factory=list)
    confidence: float = 0.8
    follow_up_questions: List[str] = field(default_factory=list)
    methods_used: List[str] = field(default_factory=list)
    benchmark_evidence: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


class ResearchAgent:
    """
    Agent for answering research questions with literature-backed evidence.

    Uses a multi-step process:
    1. Analyze the question to identify key concepts
    2. Search literature (PubMed, arXiv, etc.)
    3. Query benchmark knowledge for tool comparisons
    4. Synthesize findings with skill-guided prompts
    5. Generate response with citations
    """

    def __init__(
        self,
        llm_client: Optional[Any] = None,
        skill_loader: Optional[Any] = None,
        benchmark_db: Optional[Any] = None,
        literature_client: Optional[Any] = None,
        max_citations: int = 5,
        max_workers: int = 3
    ):
        """
        Initialize ResearchAgent.

        Args:
            llm_client: LLM client for Claude API calls
            skill_loader: SkillLoader for loading scientific skills
            benchmark_db: BenchmarkKnowledgeDB for tool comparisons
            literature_client: UnifiedLiteratureClient for citation retrieval
            max_citations: Maximum citations to include in response
            max_workers: Max parallel workers for literature search
        """
        self.llm_client = llm_client
        self.skill_loader = skill_loader
        self.benchmark_db = benchmark_db
        self.literature_client = literature_client
        self.max_citations = max_citations
        self.max_workers = max_workers

        # Lazy import to avoid circular dependencies
        self._init_components()

    def _init_components(self):
        """Initialize components lazily."""
        # Import LLM client if not provided
        if self.llm_client is None:
            try:
                from galaxy.ai.llm_client import LLMClient
                from galaxy.ai.config import DEFAULT_AI_CONFIG
                self.llm_client = LLMClient(DEFAULT_AI_CONFIG)
            except ImportError:
                log.warning("LLMClient not available")
            except Exception as e:
                log.warning(f"LLMClient initialization failed: {e}")

        # Import SkillLoader if not provided
        if self.skill_loader is None:
            try:
                from galaxy.ai.agents.skill_loader import SkillLoader
                self.skill_loader = SkillLoader()
            except ImportError:
                log.warning("SkillLoader not available")

        # Import BenchmarkKnowledgeDB if not provided
        if self.benchmark_db is None:
            try:
                from galaxy.ai.benchmark_knowledge import BenchmarkKnowledgeDB
                self.benchmark_db = BenchmarkKnowledgeDB()
            except ImportError:
                log.warning("BenchmarkKnowledgeDB not available")

        # Import UnifiedLiteratureClient if not provided
        if self.literature_client is None:
            try:
                from galaxy.ai.agents.literature_clients import create_literature_client
                self.literature_client = create_literature_client()
            except ImportError:
                log.warning("UnifiedLiteratureClient not available")

    async def answer_question(
        self,
        question: str,
        context: Optional[Dict[str, Any]] = None,
        include_citations: bool = True,
        include_benchmark_evidence: bool = True
    ) -> ResearchResponse:
        """
        Answer a research question with literature-backed evidence.

        Args:
            question: The research question to answer
            context: Optional context (domain, workflow results, etc.)
            include_citations: Whether to search and include citations
            include_benchmark_evidence: Whether to query benchmarks

        Returns:
            ResearchResponse with answer, citations, and evidence
        """
        try:
            # Step 1: Analyze question
            analysis = await self._analyze_question(question, context)

            # Step 2: Gather evidence in parallel
            evidence = await self._gather_evidence(
                question=question,
                analysis=analysis,
                include_citations=include_citations,
                include_benchmark_evidence=include_benchmark_evidence
            )

            # Step 3: Synthesize response
            response = await self._synthesize_response(
                question=question,
                analysis=analysis,
                evidence=evidence,
                context=context
            )

            return response

        except Exception as e:
            log.error(f"Error answering question: {e}")
            return ResearchResponse(
                answer=f"I encountered an error while researching your question: {str(e)}",
                error=str(e),
                confidence=0.0
            )

    async def _analyze_question(
        self,
        question: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Analyze the question to extract key concepts and intent."""
        # Determine intent type
        intent = self._classify_intent(question)

        # Extract key terms
        key_terms = self._extract_key_terms(question)

        # Determine domain
        domain = context.get('domain') if context else None
        if not domain:
            domain = self._infer_domain(question, key_terms)

        return {
            'intent': intent,
            'key_terms': key_terms,
            'domain': domain,
            'is_tool_comparison': self._is_tool_comparison(question),
            'is_method_question': self._is_method_question(question)
        }

    def _classify_intent(self, question: str) -> str:
        """Classify the intent of the question."""
        question_lower = question.lower()

        if any(word in question_lower for word in ['compare', 'vs', 'versus', 'better', 'best']):
            return 'result_comparison'
        elif any(word in question_lower for word in ['how', 'method', 'protocol', 'procedure']):
            return 'research_question'
        elif any(word in question_lower for word in ['conclude', 'interpret', 'mean', 'implication']):
            return 'conclusion_drawing'
        elif any(word in question_lower for word in ['hypothesis', 'predict', 'expect']):
            return 'hypothesis_generation'
        elif any(word in question_lower for word in ['literature', 'review', 'papers', 'studies']):
            return 'literature_survey'
        else:
            return 'research_question'

    def _extract_key_terms(self, question: str) -> List[str]:
        """Extract key scientific terms from the question."""
        # Common scientific terms to look for
        bio_terms = [
            'rna-seq', 'dna', 'protein', 'gene', 'genome', 'transcriptome',
            'alignment', 'variant', 'expression', 'differential', 'single-cell',
            'chip-seq', 'atac-seq', 'methylation', 'sequencing', 'assembly',
            'annotation', 'pathway', 'enrichment', 'clustering', 'normalization'
        ]

        # Tool names
        tool_names = [
            'star', 'hisat2', 'bowtie', 'bwa', 'salmon', 'kallisto',
            'deseq2', 'edger', 'limma', 'scanpy', 'seurat', 'scvi',
            'gatk', 'deepvariant', 'freebayes', 'macs2', 'homer'
        ]

        question_lower = question.lower()
        found_terms = []

        for term in bio_terms + tool_names:
            if term in question_lower:
                found_terms.append(term)

        # Also extract any capitalized terms (likely proper nouns/tool names)
        words = question.split()
        for word in words:
            if word[0].isupper() and len(word) > 2 and word.lower() not in ['the', 'what', 'how', 'why']:
                found_terms.append(word)

        return list(set(found_terms))

    def _infer_domain(self, question: str, key_terms: List[str]) -> str:
        """Infer the scientific domain from the question."""
        domain_keywords = {
            'genomics': ['dna', 'genome', 'variant', 'snp', 'indel', 'assembly', 'wgs', 'wes'],
            'transcriptomics': ['rna', 'transcriptome', 'expression', 'differential', 'rna-seq'],
            'proteomics': ['protein', 'mass spec', 'peptide', 'proteome'],
            'single-cell': ['single-cell', 'scrna', 'scatac', '10x', 'clustering'],
            'epigenomics': ['chip-seq', 'atac-seq', 'methylation', 'histone', 'chromatin'],
            'metagenomics': ['microbiome', 'metagenome', '16s', 'shotgun', 'taxonomy'],
            'pharmacology': ['drug', 'compound', 'target', 'binding', 'admet', 'docking']
        }

        question_lower = question.lower()
        terms_lower = [t.lower() for t in key_terms]

        for domain, keywords in domain_keywords.items():
            for keyword in keywords:
                if keyword in question_lower or keyword in terms_lower:
                    return domain

        return 'general'

    def _is_tool_comparison(self, question: str) -> bool:
        """Check if the question is about comparing tools."""
        comparison_words = ['compare', 'vs', 'versus', 'better', 'best', 'difference', 'prefer']
        return any(word in question.lower() for word in comparison_words)

    def _is_method_question(self, question: str) -> bool:
        """Check if the question is about methodology."""
        method_words = ['how', 'method', 'protocol', 'procedure', 'steps', 'workflow', 'pipeline']
        return any(word in question.lower() for word in method_words)

    def _get_anthropic_client(self):
        """Lazily create a direct Anthropic client for vision calls."""
        if not hasattr(self, '_anthropic_client') or self._anthropic_client is None:
            try:
                import anthropic as _anthropic
                api_key = os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("GALAXY_AI_API_KEY")
                self._anthropic_client = _anthropic.Anthropic(api_key=api_key)
            except Exception as e:
                log.warning(f"Failed to create Anthropic client for vision: {e}")
                self._anthropic_client = None
        return self._anthropic_client

    def _vision_read_figure(self, image_b64: str, question: str) -> str:
        """
        Call Claude Haiku with a base64-encoded PNG image and extract numerical
        values relevant to the question.

        Returns the model's textual answer or "" on any failure.
        """
        client = self._get_anthropic_client()
        if client is None:
            return ""
        try:
            response = client.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=300,
                messages=[{
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": "image/png",
                                "data": image_b64,
                            },
                        },
                        {
                            "type": "text",
                            "text": (
                                "This is a figure from a scientific paper. "
                                "Extract the specific numerical values or data relevant to this question: "
                                f"{question}\n"
                                "Be concise — report only the specific numbers asked for."
                            ),
                        },
                    ],
                }]
            )
            return response.content[0].text
        except Exception as e:
            log.debug(f"Vision call failed: {e}")
            return ""

    def _extract_figure_data_for_question(
        self,
        question: str,
        pmcids: List[str],
        s2_pdf_urls: Optional[List[str]] = None,
    ) -> str:
        """
        For each PMCID (up to 2), attempt to:
          1. Obtain a PDF URL for the paper (prefer S2 direct links, then Europe PMC).
          2. Render a relevant page as a PNG image.
          3. Use Claude vision to read numerical values from the figure.

        Falls back to PMC HTML figure-caption extraction when PDF rendering fails.

        Args:
            pmcids: List of PMC IDs to try.
            s2_pdf_urls: Optional direct PDF URLs from Semantic Scholar (preferred source).

        Returns combined results (max 500 chars) or "" on total failure.
        """
        results: List[str] = []

        # Try S2 direct PDF URLs first (no bot protection)
        if s2_pdf_urls:
            for pdf_url in s2_pdf_urls[:2]:
                try:
                    image_b64 = _download_pdf_page_as_image(pdf_url, question)
                    if image_b64:
                        vision_result = self._vision_read_figure(image_b64, question)
                        if vision_result:
                            results.append(f"[Figure via vision (S2)]: {vision_result}")
                            if len(results) >= 2:
                                break
                except Exception as e:
                    log.debug(f"S2 PDF figure extraction failed for {pdf_url}: {e}")

        # Fall through to PMCID-based approach if S2 didn't yield results
        for pmcid in pmcids[:2]:
            try:
                image_b64 = None

                # Try Europe PMC direct PDF URL (actual PDF bytes, no interstitial)
                epmc_url = f"https://europepmc.org/backend/ptpmcrender.fcgi?accid=PMC{pmcid}&blobtype=pdf"
                epmc_bytes = _http_get_bytes(epmc_url, timeout=25)
                if epmc_bytes and len(epmc_bytes) > 5000 and epmc_bytes[:4] == b'%PDF':
                    # Pass bytes directly to avoid re-downloading
                    image_b64 = _download_pdf_page_as_image(epmc_url, question, pdf_bytes=epmc_bytes)

                if image_b64:
                    # Vision read
                    vision_result = self._vision_read_figure(image_b64, question)
                    if vision_result:
                        results.append(f"[PMC{pmcid} figure via vision]: {vision_result}")
                else:
                    # Fallback: HTML figure captions from PMC
                    html_result = _fetch_pmc_html_figure_captions(str(pmcid), question)
                    if html_result:
                        results.append(f"[PMC{pmcid} figure captions]: {html_result}")

            except Exception as e:
                log.debug(f"Figure extraction failed for PMC{pmcid}: {e}")
                continue

        combined = "\n".join(results)
        return combined[:500]

    async def _gather_evidence(
        self,
        question: str,
        analysis: Dict[str, Any],
        include_citations: bool,
        include_benchmark_evidence: bool
    ) -> Dict[str, Any]:
        """Gather evidence from multiple sources."""
        evidence = {
            'citations': [],
            'benchmark_results': None,
            'skill_guidance': '',
            'db_facts': {}   # live DB lookup results injected before LLM synthesis
        }

        # Load relevant skills
        if self.skill_loader:
            intent = analysis.get('intent', 'research_question')
            evidence['skill_guidance'] = self.skill_loader.load_skills_for_intent(
                intent,
                include_references=False,
                max_tokens=4000
            )

            # Also load domain-specific skills
            domain = analysis.get('domain')
            if domain and domain != 'general':
                domain_skills = self.skill_loader.load_skills_for_domain(
                    domain,
                    include_references=False,
                    max_tokens=2000
                )
                evidence['skill_guidance'] += f"\n\n{domain_skills}"

        # Search literature using UnifiedLiteratureClient
        if include_citations and self.literature_client:
            try:
                key_terms = analysis.get('key_terms', [])
                search_query = ' '.join(key_terms) if key_terms else question

                # Use bioinformatics-focused search
                citations = await self.literature_client.search_bioinformatics(
                    query=search_query,
                    max_results=self.max_citations,
                    recent_years=5
                )

                evidence['citations'] = citations
                log.info(f"Retrieved {len(citations)} citations from literature search")
            except Exception as e:
                log.warning(f"Literature search failed: {e}")

        # ── Full-text retrieval (S2 + PMC OA) ────────────────────────────────
        # Attempt to fetch Methods/Results sections from open-access papers so
        # the LLM has exact numbers rather than just abstracts.
        collected_pmcids: List[str] = []
        collected_s2_pdf_urls: List[str] = []
        try:
            # Collect paper titles from PubMed citations we just found
            citation_titles = [
                c.title for c in evidence.get('citations', [])
                if getattr(c, 'title', None)
            ]
            # Collect PMCIDs from citations for figure extraction
            for cit in evidence.get('citations', []):
                pmcid_val = getattr(cit, 'pmcid', None) or getattr(cit, 'pmid', None)
                if pmcid_val:
                    collected_pmcids.append(str(pmcid_val))

            # Also add a direct S2 search on the question to catch papers not
            # in the citation list (e.g. preprints, non-PubMed indexed work)
            fulltext_context = _extract_fulltext_for_question(question, citation_titles)
            if fulltext_context:
                evidence['paper_fulltext'] = fulltext_context
                log.info(f"Full-text context retrieved: {len(fulltext_context)} chars")
            else:
                # Fallback: search S2 directly on the question
                s2_direct = _fetch_s2_paper(question[:200])
                # Collect PMCIDs and open-access PDF URLs from S2 results
                for s2p in s2_direct:
                    ext_ids = s2p.get("externalIds") or {}
                    pmc = ext_ids.get("PubMedCentral") or ext_ids.get("PMC")
                    if pmc:
                        collected_pmcids.append(str(pmc))
                    open_pdf = s2p.get("openAccessPdf") or {}
                    pdf_url = open_pdf.get("url", "")
                    if pdf_url and pdf_url.endswith(".pdf"):
                        collected_s2_pdf_urls.append(pdf_url)
                s2_titles = [p.get('title', '') for p in s2_direct if p.get('title')]
                if s2_titles:
                    fulltext_context = _extract_fulltext_for_question(question, s2_titles)
                    if fulltext_context:
                        evidence['paper_fulltext'] = fulltext_context
                        log.info(f"Full-text context (S2 fallback): {len(fulltext_context)} chars")

            # Also collect S2 PDF URLs from the citation-driven full-text fetch
            # (reuse S2 results already fetched inside _extract_fulltext_for_question)
            if not collected_s2_pdf_urls:
                for title in citation_titles[:3]:
                    try:
                        s2p_list = _fetch_s2_paper(title)
                        for s2p in s2p_list[:1]:
                            open_pdf = s2p.get("openAccessPdf") or {}
                            pdf_url = open_pdf.get("url", "")
                            if pdf_url and pdf_url.endswith(".pdf"):
                                collected_s2_pdf_urls.append(pdf_url)
                    except Exception:
                        pass
        except Exception as e:
            log.warning(f"Full-text retrieval failed (non-fatal): {e}")

        # ── Figure extraction via vision ──────────────────────────────────────
        # For questions that reference specific figures (e.g. "Figure 4c"),
        # attempt to render the PDF page and extract numerical values via vision.
        figure_keywords = ("figure", "fig.", "extended data", "supplementary", "table")
        has_figure_ref = any(kw in question.lower() for kw in figure_keywords)
        if (collected_pmcids or collected_s2_pdf_urls) and has_figure_ref:
            try:
                figure_data = self._extract_figure_data_for_question(
                    question,
                    collected_pmcids,
                    s2_pdf_urls=collected_s2_pdf_urls or None,
                )
                if figure_data:
                    evidence['figure_data'] = figure_data
                    log.info(f"Figure data extracted: {len(figure_data)} chars")
            except Exception as e:
                log.warning(f"Figure extraction failed (non-fatal): {e}")

        # ── Live biomedical DB lookups ────────────────────────────────────────
        # Query real APIs (Ensembl, Monarch, MyGene, ClinVar) so Claude gets
        # actual database facts rather than relying on training-data knowledge.
        try:
            ids = extract_biomedical_identifiers(question)
            db_facts: Dict[str, Any] = {}

            # ENSG IDs → gene symbols + descriptions (Ensembl REST)
            if ids["ensg_ids"]:
                ensembl_info = lookup_ensembl_ids(ids["ensg_ids"])
                if ensembl_info:
                    db_facts["ensembl_genes"] = ensembl_info
                    # Also get OMIM IDs via mygene for these genes
                    symbols = [v["symbol"] for v in ensembl_info.values() if v.get("symbol")]
                    if symbols:
                        mg = lookup_mygene(symbols, fields="symbol,name,summary,OMIM")
                        if mg:
                            db_facts["mygene_annotation"] = mg

            # HP terms → associated genes (Monarch Initiative)
            if ids["hp_terms"]:
                monarch_genes = lookup_hpo_genes(ids["hp_terms"])
                if monarch_genes:
                    db_facts["hpo_gene_associations"] = monarch_genes

            # Gene symbols mentioned → OMIM disease IDs (mygene.info)
            gene_syms = ids["gene_symbols"]
            if gene_syms and not db_facts.get("mygene_annotation"):
                mg = lookup_mygene(gene_syms[:5], fields="symbol,name,summary,OMIM")
                if mg:
                    db_facts["mygene_annotation"] = mg

            # If a gene symbol appears with disease-lookup context → ClinVar
            clinical_keywords = {"pathogenic", "variant", "disease", "diagnosis", "rare", "clinvar", "mutation"}
            if gene_syms and any(kw in question.lower() for kw in clinical_keywords):
                clinvar_hits = lookup_clinvar_gene(gene_syms[0])
                if clinvar_hits:
                    db_facts["clinvar_variants"] = clinvar_hits

            # ── GWAS Catalog lookup — for SNP prioritization / causal gene questions ─
            # Triggers when: question contains candidate rsIDs (≥2) which indicates a
            # GWAS variant prioritization task rather than a general knowledge query.
            rs_ids_in_question = list(dict.fromkeys(
                re.findall(r"\brs\d{4,}\b", question)
            ))
            gwas_keywords = {
                "gwas", "snp", "variant", "locus", "allele", "association",
                "eqtl", "causal", "risk", "phenotype", "trait", "fine-map",
            }
            has_gwas_context = (
                len(rs_ids_in_question) >= 2
                or any(kw in question.lower() for kw in gwas_keywords)
            )
            if has_gwas_context and rs_ids_in_question:
                # Extract phenotype from question (text before first rsID)
                first_rs_pos = question.find(rs_ids_in_question[0])
                phenotype_text = question[:first_rs_pos].strip() if first_rs_pos > 0 else question
                try:
                    gwas_hits = lookup_gwas_catalog(phenotype_text, rs_ids_in_question)
                    if gwas_hits:
                        db_facts["gwas_catalog"] = gwas_hits
                        log.info(
                            f"GWAS Catalog lookup: top_rsid={gwas_hits.get('top_rsid')}, "
                            f"{len(gwas_hits.get('ranked', []))} associations"
                        )
                except Exception as e:
                    log.warning(f"GWAS Catalog lookup failed (non-fatal): {e}")

            # ── Open Targets gene lookup — for causal-gene questions ──────────────
            # Triggers when the question already has a known lead variant but asks for gene.
            if has_gwas_context and len(rs_ids_in_question) == 1:
                try:
                    _pheno = phenotype_text if 'phenotype_text' in locals() else question
                    ot_hits = lookup_open_targets_gene(rs_ids_in_question[0], _pheno)
                    if ot_hits:
                        db_facts["open_targets_gene"] = ot_hits
                        log.info(f"Open Targets gene lookup: {ot_hits.get('top_gene')}")
                except Exception as e:
                    log.warning(f"Open Targets lookup failed (non-fatal): {e}")

            # ── GWAS gene-phenotype lookup — for causal-gene questions with gene list ─
            # Triggers when the question has gene names in curly braces like {GENE1},{GENE2}
            # (BiomniEval1 gwas_causal_gene format).
            gene_list_match = re.findall(r"\{([A-Za-z][A-Za-z0-9\-_]{1,20})\}", question)
            if not gene_list_match:
                # Also pick up comma-separated gene lists: "Genes: GENE1, GENE2, GENE3"
                locus_match = re.search(
                    r"(?:genes?[^:]*:|locus[^:]*:)\s*([A-Z][A-Z0-9,\- ]{5,})",
                    question, re.IGNORECASE
                )
                if locus_match:
                    gene_list_match = [
                        g.strip() for g in locus_match.group(1).split(",") if g.strip()
                    ]
            if gene_list_match and has_gwas_context:
                _pheno = phenotype_text if 'phenotype_text' in locals() else question
                # Extract phenotype from question for gene lookup
                pheno_for_gene = _pheno
                if "gwas phenotype" in question.lower() or "phenotype:" in question.lower():
                    pm = re.search(r"(?:gwas phenotype|phenotype)\s*:\s*([^\n,]{5,100})", question, re.IGNORECASE)
                    if pm:
                        pheno_for_gene = pm.group(1).strip()
                try:
                    gene_hits = lookup_gwas_catalog_genes(pheno_for_gene, gene_list_match)
                    if gene_hits:
                        db_facts["gwas_catalog_genes"] = gene_hits
                        log.info(
                            f"GWAS gene lookup: top={gene_hits.get('top_gene')}, "
                            f"{len(gene_hits.get('ranked', []))} hits"
                        )
                except Exception as e:
                    log.warning(f"GWAS gene lookup failed (non-fatal): {e}")

            # ── Improvement A: HPO gene phenotype scoring ─────────────────────
            # When the question has both HPO terms and ENSG candidate genes,
            # score each ENSG by how many HPO phenotypes map to it.
            if ids["hp_terms"] and ids["ensg_ids"] and db_facts.get("ensembl_genes"):
                try:
                    hpo_gene_map = _lookup_hpo_associated_genes(ids["hp_terms"])
                    if hpo_gene_map:
                        hpo_scores = _score_ensg_by_hpo(db_facts["ensembl_genes"], hpo_gene_map)
                        if hpo_scores:
                            db_facts["hpo_ensg_scores"] = hpo_scores
                            log.info(
                                f"HPO-ENSG scoring: {len(hpo_scores)} genes scored, "
                                f"top={next(iter(hpo_scores.values()), {}).get('symbol','?')}"
                            )
                except Exception as e:
                    log.warning(f"HPO-ENSG scoring failed (non-fatal): {e}")

            # ── Improvement B: OMIM disease phenotype overlap scoring ─────────
            # For rare-disease questions, score OMIM diseases by HPO overlap.
            rare_disease_keywords = {"omim", "rare disease", "disease_name", "search omim", "mendelian"}
            is_rare_disease_task = any(kw in question.lower() for kw in rare_disease_keywords)
            if is_rare_disease_task and ids["hp_terms"] and ids["ensg_ids"] and db_facts.get("mygene_annotation"):
                try:
                    # Build gene_omim_results from mygene_annotation
                    gene_omim_for_scoring = [
                        {"symbol": hit.get("symbol", ""), "omim_ids": hit.get("OMIM") or hit.get("omim") or []}
                        for hit in db_facts["mygene_annotation"]
                        if hit.get("symbol")
                    ]
                    if gene_omim_for_scoring:
                        omim_disease_scores = _score_omim_diseases_by_hpo_overlap(
                            gene_omim_for_scoring, ids["hp_terms"]
                        )
                        if omim_disease_scores:
                            db_facts["omim_disease_hpo_scores"] = omim_disease_scores
                            log.info(
                                f"OMIM disease HPO scoring: {len(omim_disease_scores)} diseases scored, "
                                f"top={omim_disease_scores[0].get('gene','?')} OMIM:{omim_disease_scores[0].get('omim_id','?')}"
                            )
                except Exception as e:
                    log.warning(f"OMIM disease HPO scoring failed (non-fatal): {e}")

            # ── Improvement C: CRISPR screen PubMed search ────────────────────
            # For screen_gene questions, fetch targeted PubMed literature.
            crispr_keywords = {"crispr screen", "perturbation effect", "fitness effect", "genetic screen"}
            is_screen_gene_task = any(kw in question.lower() for kw in crispr_keywords)
            if is_screen_gene_task:
                try:
                    # Extract experimental condition: look for cell line / disease name
                    condition_match = re.search(
                        r"(?:in\s+|condition[:\s]+|cell\s+line[:\s]+|cancer[:\s]+)([A-Za-z0-9 \-]{5,60})",
                        question, re.IGNORECASE
                    )
                    condition = condition_match.group(1).strip() if condition_match else question[:80]
                    crispr_abstracts = _search_crispr_screen_pubmed(condition)
                    if crispr_abstracts:
                        db_facts["crispr_screen_literature"] = crispr_abstracts
                        log.info(f"CRISPR screen PubMed: {len(crispr_abstracts)} chars retrieved")
                except Exception as e:
                    log.warning(f"CRISPR screen PubMed search failed (non-fatal): {e}")

            if db_facts:
                evidence["db_facts"] = db_facts
                log.info(f"DB lookup populated: {list(db_facts.keys())}")

        except Exception as e:
            log.warning(f"Biomedical DB lookup failed (non-fatal): {e}")

        # ── Molecular biology tool context injection ─────────────────────────
        # For protocol/cloning/wet-lab questions, inject relevant tool knowledge
        # from the AI tool DB so answers use BioMate's actual capabilities.
        try:
            mol_bio_context = self._fetch_mol_bio_tool_context(question, analysis)
            if mol_bio_context:
                if not evidence.get("db_facts"):
                    evidence["db_facts"] = {}
                evidence["db_facts"]["mol_bio_tools"] = mol_bio_context
                log.info(f"Molecular biology tool context injected: {len(mol_bio_context)} chars")
        except Exception as e:
            log.warning(f"Mol-bio tool context injection failed (non-fatal): {e}")

        # Query benchmarks for tool comparisons
        if include_benchmark_evidence and self.benchmark_db:
            if analysis.get('is_tool_comparison'):
                # Try to extract tool names and compare
                benchmark_results = self._query_benchmarks(question, analysis)
                evidence['benchmark_results'] = benchmark_results

        return evidence

    def _query_benchmarks(
        self,
        question: str,
        analysis: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """Query benchmark database for tool comparisons."""
        if not self.benchmark_db:
            return None

        try:
            # Use semantic search on the question
            results = self.benchmark_db.query_semantic(question, top_k=5)

            if results:
                return {
                    'query': question,
                    'results': results,
                    'best_tool': results[0].get('tool_name') if results else None,
                    'evidence': results[0].get('evidence_text') if results else None
                }
        except Exception as e:
            log.warning(f"Benchmark query failed: {e}")

        return None

    # ── Molecular biology tool DB keywords ────────────────────────────────────
    _MOL_BIO_QUESTION_KEYWORDS = frozenset([
        "restriction", "enzyme", "digest", "cloning", "clone", "plasmid", "vector",
        "primer", "pcr", "amplif", "annealing", "tm", "melting", "gc content",
        "golden gate", "gibson", "assembly", "ligation", "restriction site",
        "cut site", "recognition sequence", "ecori", "bamhi", "hindiii", "xhoi",
        "xbai", "sali", "blunt end", "sticky end", "overhang", "cohesive",
        "transformation", "transfection", "competent", "electroporation",
        "mutagenesis", "site-directed", "site directed", "orf", "open reading frame",
        "codon", "crispr", "sgrna", "guide rna", "knockout", "knock-in", "nickase",
        "cas9", "cpf1", "base edit", "prime edit", "homology arm", "hdr",
        "molecular cloning", "expression vector", "insert", "backbone",
        "sequencing primer", "reverse complement", "complement strand",
        "gel electrophoresis", "agarose gel", "band size", "fragment size",
        "restriction map", "cloning strategy", "subcloning",
    ])

    _MOL_BIO_TOOL_KEYWORD_MAP: Dict[str, List[str]] = {
        "restriction enzyme": ["Find Restriction Enzymes", "Find Restriction Sites", "Digest Sequence"],
        "restriction site": ["Find Restriction Sites", "Digest Sequence", "Find Restriction Enzymes"],
        "cloning": ["Molecular Cloning Design Pipeline", "Annotate Plasmid", "Golden Gate Assembly"],
        "golden gate": ["Golden Gate Assembly", "Design Golden Gate Oligos", "Get Golden Gate Assembly Protocol"],
        "primer": ["Design Primer", "Design Verification Primers", "Align Sequences"],
        "pcr": ["Pcr Simple", "Design Primer", "Perform Pcr And Gel Electrophoresis"],
        "sgrna": ["Design Knockout Sgrna", "Crispr Gene Editing Design Pipeline"],
        "crispr": ["Design Knockout Sgrna", "Crispr Gene Editing Design Pipeline"],
        "orf": ["Annotate Open Reading Frames", "Find Orfs In Frame", "Get Coding Sequences"],
        "reverse complement": ["Reverse Complement"],
        "transformation": ["Get Bacterial Transformation Protocol"],
        "plasmid": ["Annotate Plasmid", "Get Plasmid Sequence", "Molecular Cloning Design Pipeline"],
        "annealing": ["Get Oligo Annealing Protocol", "Design Primer"],
        "sequence": ["Align Sequences", "Find Sequence Mutations", "Search Gene"],
    }

    def _fetch_mol_bio_tool_context(
        self, question: str, analysis: Dict[str, Any]
    ) -> str:
        """
        Query the AI tool DB for molecular biology tools relevant to the question.
        Returns a formatted context block for synthesis prompt injection, or '' if
        the question is not molecular-biology protocol-related.

        Gate: LLM intent type is the primary signal. Keywords from
        _MOL_BIO_QUESTION_KEYWORDS are used only as selection hints to surface
        the most relevant tool subset — not as hard activation gates.
        """
        q_lower = question.lower()

        # Primary gate: LLM-classified intent type
        info_need = analysis.get("intent", "")
        mol_bio_intents = {"protocol_guidance", "experiment_design", "research_question",
                           "general_question", "teaching_explanation", "methods_writing"}
        if info_need not in mol_bio_intents:
            return ""

        # Secondary signal: keyword hints to select which tools to surface.
        # If no keywords match, still try the category-wide fetch (let the LLM judge relevance).
        has_any_mol_bio_hint = any(kw in q_lower for kw in self._MOL_BIO_QUESTION_KEYWORDS)

        # Use keyword map as hints to prioritise specific tools; keywords are advisory only.
        relevant_tool_names: List[str] = []
        for kw, tools in self._MOL_BIO_TOOL_KEYWORD_MAP.items():
            if kw in q_lower:
                for t in tools:
                    if t not in relevant_tool_names:
                        relevant_tool_names.append(t)

        # If no keyword hints matched AND this doesn't look like a wet-lab question,
        # skip to avoid noise (genomics/bioinformatics questions don't need mol-bio tools).
        if not relevant_tool_names and not has_any_mol_bio_hint:
            return ""

        if not relevant_tool_names:
            # Fallback: fetch all mol-bio tools
            relevant_tool_names = []  # will do category query below

        # Query DB
        db_paths = [
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "database", "galaxy_ai_tools.db"),
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "galaxy_ai_tools.db"),
            "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db",
        ]
        db_path = None
        for p in db_paths:
            p = os.path.normpath(p)
            if os.path.exists(p):
                db_path = p
                break

        if not db_path:
            log.debug("galaxy_ai_tools.db not found for mol-bio context injection")
            return ""

        import sqlite3 as _sqlite3
        try:
            conn = _sqlite3.connect(db_path, timeout=3)
            cur = conn.cursor()

            if relevant_tool_names:
                placeholders = ",".join("?" * len(relevant_tool_names[:8]))
                cur.execute(
                    f"SELECT tool_name, use_cases, recommended_parameters FROM tool_knowledge "
                    f"WHERE tool_name IN ({placeholders}) LIMIT 8",
                    relevant_tool_names[:8]
                )
            else:
                cur.execute(
                    "SELECT tool_name, use_cases, recommended_parameters FROM tool_knowledge "
                    "WHERE category='molecular_biology' LIMIT 10"
                )
            rows = cur.fetchall()
            conn.close()
        except Exception as e:
            log.warning(f"mol_bio_tool_context DB query failed: {e}")
            return ""

        if not rows:
            return ""

        import json as _json
        lines = ["BioMate has these molecular biology tools available for this analysis:"]
        for tool_name, use_cases_raw, params_raw in rows:
            try:
                use_cases = _json.loads(use_cases_raw or "[]") if use_cases_raw else []
            except Exception:
                use_cases = [use_cases_raw] if use_cases_raw else []
            # Show first use case as a one-liner
            use_case_str = use_cases[0] if use_cases else ""
            lines.append(f"- **{tool_name}**: {use_case_str}")

        return "\n".join(lines)

    async def _synthesize_response(
        self,
        question: str,
        analysis: Dict[str, Any],
        evidence: Dict[str, Any],
        context: Optional[Dict[str, Any]] = None
    ) -> ResearchResponse:
        """Synthesize a response from gathered evidence."""
        if not self.llm_client:
            return ResearchResponse(
                answer="LLM client not available for response synthesis.",
                error="LLM client not initialized",
                confidence=0.0
            )

        # Build the synthesis prompt
        prompt = self._build_synthesis_prompt(question, analysis, evidence, context)

        try:
            # Call LLM for synthesis
            response = await self._call_llm(prompt)

            # Parse the response
            parsed = self._parse_llm_response(response)

            # Build citations from literature search and benchmark evidence
            citations = []

            # Add citations from literature search (LiteratureCitation -> Citation)
            if evidence.get('citations'):
                for lit_citation in evidence['citations'][:self.max_citations]:
                    citations.append(Citation(
                        title=lit_citation.title,
                        authors=lit_citation.authors,
                        year=lit_citation.year or 2023,
                        journal=lit_citation.journal or "Unknown",
                        doi=lit_citation.doi,
                        pmid=lit_citation.pmid,
                        abstract=lit_citation.abstract,
                        relevance_score=lit_citation.relevance_score
                    ))

            # Add citations from benchmark evidence
            if evidence.get('benchmark_results'):
                for result in evidence['benchmark_results'].get('results', [])[:self.max_citations]:
                    if result.get('doi'):
                        # Avoid duplicate DOIs
                        existing_dois = {c.doi for c in citations if c.doi}
                        if result.get('doi') not in existing_dois:
                            citations.append(Citation(
                                title=result.get('study_name', 'Benchmark Study'),
                                authors=[],
                                year=2023,  # Default
                                journal='Benchmark',
                                doi=result.get('doi')
                            ))

            return ResearchResponse(
                answer=parsed.get('answer', response),
                citations=citations,
                confidence=parsed.get('confidence', 0.8),
                follow_up_questions=parsed.get('follow_ups', []),
                methods_used=list(analysis.keys()),
                benchmark_evidence=evidence.get('benchmark_results')
            )

        except Exception as e:
            log.error(f"LLM synthesis failed: {e}")
            return ResearchResponse(
                answer=f"Error synthesizing response: {str(e)}",
                error=str(e),
                confidence=0.0
            )

    def _build_synthesis_prompt(
        self,
        question: str,
        analysis: Dict[str, Any],
        evidence: Dict[str, Any],
        context: Optional[Dict[str, Any]] = None
    ) -> str:
        """Build the prompt for LLM synthesis."""
        prompt_parts = []

        # Add skill guidance if available
        if evidence.get('skill_guidance'):
            prompt_parts.append(f"## Scientific Skill Guidance\n{evidence['skill_guidance'][:4000]}")

        # Add benchmark evidence
        if evidence.get('benchmark_results'):
            benchmark_text = self._format_benchmark_evidence(evidence['benchmark_results'])
            prompt_parts.append(f"## Benchmark Evidence\n{benchmark_text}")

        # Add live DB facts — these are real query results, not LLM guesses
        if evidence.get('db_facts'):
            db_section = ["## Live Database Facts (retrieved from GWAS Catalog / Open Targets / Ensembl / Monarch / MyGene / ClinVar)"]
            db_section.append("Use these EXACT values in your answer — do not substitute from memory.\n")
            df = evidence['db_facts']

            # ── GWAS Catalog associations — for SNP prioritization tasks ──────────
            if df.get('gwas_catalog'):
                gc = df['gwas_catalog']
                db_section.append("### GWAS Catalog: variant associations (ranked by phenotype relevance, then p-value)")
                top = gc.get('top_rsid', '')
                if top:
                    db_section.append(f"**Top candidate rsID: {top}**")
                for r in gc.get('ranked', [])[:8]:
                    genes_str = ", ".join(r.get('mapped_genes', [])) or "—"
                    db_section.append(
                        f"- {r['rsid']}: trait='{r['trait'][:80]}' | "
                        f"p={r['pvalue_mantissa']}×10^{r['pvalue_exp']} | "
                        f"genes={genes_str} | phenotype_match={r['phenotype_overlap']}"
                    )
                if gc.get('phenotype_matches'):
                    db_section.append("**Phenotype-matching associations:**")
                    for m in gc['phenotype_matches'][:3]:
                        db_section.append(f"  → {m['rsid']} matched trait '{m['trait'][:80]}'")

            # ── Open Targets gene candidates — for causal-gene questions ──────────
            if df.get('open_targets_gene'):
                ot = df['open_targets_gene']
                db_section.append("### Open Targets / GWAS Catalog: genes at locus")
                if ot.get('chromosomal_location'):
                    db_section.append(f"Variant location: {ot['chromosomal_location']}")
                if ot.get('top_gene'):
                    db_section.append(f"**Top mapped gene: {ot['top_gene']}**")
                for g in (ot.get('mapped_genes') or [])[:5]:
                    dist = g.get('distance', '?')
                    flags = []
                    if g.get('is_closest_gene'):
                        flags.append('closest')
                    if not g.get('is_intergenic'):
                        flags.append('intragenic')
                    db_section.append(
                        f"- {g['symbol']}: distance={dist}bp "
                        f"({'  '.join(flags) if flags else 'intergenic'})"
                    )

            # ── GWAS gene-phenotype rankings ─────────────────────────────────────
            if df.get('gwas_catalog_genes'):
                gcg = df['gwas_catalog_genes']
                db_section.append("### Open Targets / GWAS Catalog: genes associated with phenotype")
                top_g = gcg.get('top_gene', '')
                if top_g:
                    db_section.append(f"**Top candidate gene (highest association score): {top_g}**")
                for r in gcg.get('ranked', [])[:8]:
                    db_section.append(
                        f"- {r['gene']}: score={r.get('score', '?'):.3f} "
                        f"(source: {r.get('source', 'unknown')})"
                    )
                # Top OT genes give biological context even if not in candidate list
                ot_genes = gcg.get('top_ot_genes', [])
                if ot_genes:
                    db_section.append(
                        f"Top Open Targets genes for this disease (for context): "
                        f"{', '.join(ot_genes[:10])}"
                    )
                    db_section.append(
                        "If the highest-scoring candidate gene is also in this list, "
                        "it has strong Open Targets support — prefer it."
                    )

            if df.get('ensembl_genes'):
                db_section.append("### Ensembl gene lookup (ENSG IDs → symbols)")
                for ensg, info in df['ensembl_genes'].items():
                    db_section.append(f"- {ensg} → {info.get('symbol','')} | {info.get('description','')[:100]}")

            if df.get('mygene_annotation'):
                db_section.append("### MyGene.info annotation (includes OMIM disease IDs)")
                for hit in df['mygene_annotation'][:8]:
                    omim = hit.get('OMIM') or hit.get('omim') or []
                    db_section.append(f"- {hit.get('symbol','?')}: {hit.get('name','')} | OMIM: {omim}")
                    if hit.get('summary'):
                        db_section.append(f"  Summary: {hit.get('summary','')[:150]}")

            if df.get('hpo_gene_associations'):
                db_section.append("### Monarch Initiative: HPO term → associated genes")
                for hp_term, genes in df['hpo_gene_associations'].items():
                    gene_list = ", ".join(f"{g['symbol']} ({g['id']})" for g in genes[:10])
                    db_section.append(f"- {hp_term}: {gene_list}")

            if df.get('clinvar_variants'):
                db_section.append("### ClinVar: pathogenic variants")
                for v in df['clinvar_variants'][:5]:
                    db_section.append(f"- {v.get('title','')} | {v.get('clinical_significance','')} | {v.get('condition','')}")

            # ── Molecular biology tool context ────────────────────────────────
            if df.get('mol_bio_tools'):
                db_section.append("### BioMate Molecular Biology Tools")
                db_section.append("These tools are available in BioMate for molecular biology tasks:")
                db_section.append(df['mol_bio_tools'])

            # ── Improvement A: HPO phenotype scoring ─────────────────────────
            if df.get('hpo_ensg_scores'):
                db_section.append(
                    "### HPO phenotype scoring (ENSG candidates ranked by phenotype match count)"
                )
                db_section.append(
                    "**Use this to rank candidate genes — higher score = more phenotype evidence.**"
                )
                total_hps = next(iter(df['hpo_ensg_scores'].values()), {}).get("total_hps", 0)
                for ensg_id, s in df['hpo_ensg_scores'].items():
                    hp_list = ", ".join(s.get("matching_hps", []))
                    db_section.append(
                        f"- {ensg_id} ({s['symbol']}): score {s['hpo_score']}/{total_hps} HPO terms matched"
                        + (f" → {hp_list}" if hp_list else "")
                    )

            # ── Improvement B: OMIM disease HPO overlap scoring ───────────────
            if df.get('omim_disease_hpo_scores'):
                db_section.append(
                    "### OMIM disease HPO overlap scoring (ranked by patient phenotype overlap)"
                )
                db_section.append(
                    "**Higher overlap_count = disease phenotype better matches patient HPO terms.**"
                )
                for entry in df['omim_disease_hpo_scores'][:6]:
                    overlap_hps = ", ".join(entry.get("overlapping_hps", []))
                    db_section.append(
                        f"- {entry['gene']} / OMIM:{entry['omim_id']}: "
                        f"overlap {entry['overlap_count']}/{entry['total_patient_hps']} patient HPOs"
                        + (f" (matching: {overlap_hps})" if overlap_hps else "")
                    )

            prompt_parts.append("\n".join(db_section))

        # ── Improvement C: CRISPR screen literature ──────────────────────────
        if evidence.get('db_facts', {}).get('crispr_screen_literature'):
            crispr_section = (
                "## Published CRISPR screen literature found:\n"
                "These PubMed abstracts describe published CRISPR fitness screens relevant to the question. "
                "Use gene names, experimental conditions, and fitness effects from these abstracts to answer.\n\n"
                f"{evidence['db_facts']['crispr_screen_literature']}"
            )
            prompt_parts.append(crispr_section)

        # Add full-text paper excerpts (Methods / Results sections) — highest-priority facts
        if evidence.get('paper_fulltext'):
            fulltext_section = (
                "<paper_full_text>\n"
                "These are full-text excerpts from the most relevant papers including Extended Data figure "
                "captions and tables — ALWAYS use these specific numbers/facts over your training knowledge.\n\n"
                f"{evidence['paper_fulltext'][:6000]}\n"
                "</paper_full_text>"
            )
            prompt_parts.append(fulltext_section)

        # Add figure-extracted data (vision-read from paper PDFs) — highest priority for numeric answers
        if evidence.get('figure_data'):
            figure_section = (
                "<figure_extracted_data>\n"
                "These values were extracted from paper figures using vision — "
                "use them preferentially for specific numerical answers.\n\n"
                f"{evidence['figure_data']}\n"
                "</figure_extracted_data>"
            )
            prompt_parts.append(figure_section)

        # Add context if available
        if context:
            prompt_parts.append(f"## Context\n{json.dumps(context, indent=2)}")

        # Add the question
        prompt_parts.append(f"""
## Research Question
{question}

## Analysis
- Intent: {analysis.get('intent')}
- Domain: {analysis.get('domain')}
- Key Terms: {', '.join(analysis.get('key_terms', []))}

## Instructions
Provide a concise, evidence-based answer to the research question.

1. Be direct — lead with the answer, not preamble
2. Keep it brief: 2–4 sentences for simple factual questions; 1–3 short paragraphs for complex ones
3. Ground claims in the benchmark evidence and database facts above (use them preferentially over training knowledge)
4. If tool recommendations are relevant, name them specifically (1–2 max)
5. Cite sources inline with [N] notation only when a specific paper supports the claim

Format: plain prose or a short bulleted list. No lengthy introductions, no "In summary" footers.
""")

        return "\n\n".join(prompt_parts)

    def _format_benchmark_evidence(self, benchmark_results: Dict[str, Any]) -> str:
        """Format benchmark results for the prompt."""
        if not benchmark_results:
            return "No benchmark data available."

        lines = []
        lines.append(f"Query: {benchmark_results.get('query', 'N/A')}")

        if benchmark_results.get('best_tool'):
            lines.append(f"Best Tool: {benchmark_results['best_tool']}")

        if benchmark_results.get('evidence'):
            lines.append(f"Evidence: {benchmark_results['evidence']}")

        results = benchmark_results.get('results', [])
        if results:
            lines.append("\nRanked Results:")
            for i, result in enumerate(results[:5], 1):
                tool = result.get('tool_name', 'Unknown')
                rank = result.get('rank', 'N/A')
                metric = result.get('metric_name', '')
                value = result.get('metric_value', '')
                lines.append(f"  {i}. {tool} (Rank: {rank}, {metric}: {value})")

        return "\n".join(lines)

    async def _call_llm(self, prompt: str) -> str:
        """Call the LLM with the synthesis prompt."""
        if not self.llm_client:
            raise ValueError("LLM client not available")

        # generate() is synchronous; generate_async() is the awaitable version
        if hasattr(self.llm_client, 'generate_async'):
            response = await self.llm_client.generate_async(
                prompt=prompt,
                max_tokens=2000,
                temperature=0.7
            )
        else:
            # Fallback: call sync version in thread executor to avoid blocking
            import asyncio
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None,
                lambda: self.llm_client.generate(prompt, max_tokens=2000, temperature=0.7)
            )

        return response

    def _parse_llm_response(self, response: str) -> Dict[str, Any]:
        """Parse the LLM response to extract structured data."""
        # For now, return the response as-is with default metadata
        # In future, could parse structured sections
        return {
            'answer': response,
            'confidence': 0.8,
            'follow_ups': []
        }

    # Synchronous wrapper for compatibility
    def answer_question_sync(
        self,
        question: str,
        context: Optional[Dict[str, Any]] = None,
        include_citations: bool = True,
        include_benchmark_evidence: bool = True
    ) -> ResearchResponse:
        """Synchronous wrapper for answer_question.

        Properly handles event loop creation to avoid "Event loop is closed" errors.
        Works correctly in Python 3.10+ where get_event_loop() behavior changed.
        """
        import asyncio

        async_coro = self.answer_question(
            question=question,
            context=context,
            include_citations=include_citations,
            include_benchmark_evidence=include_benchmark_evidence
        )

        # Check if we're already inside an async context
        try:
            loop = asyncio.get_running_loop()
            # We're inside an async context - use nest_asyncio or run in thread
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor() as executor:
                future = executor.submit(asyncio.run, async_coro)
                return future.result()
        except RuntimeError:
            # No running event loop - safe to use asyncio.run()
            # asyncio.run() creates a new event loop, runs the coroutine, and closes it
            return asyncio.run(async_coro)


# Factory function
def create_research_agent(
    llm_client: Optional[Any] = None,
    skill_loader: Optional[Any] = None,
    benchmark_db: Optional[Any] = None,
    literature_client: Optional[Any] = None
) -> ResearchAgent:
    """Create a ResearchAgent instance."""
    return ResearchAgent(
        llm_client=llm_client,
        skill_loader=skill_loader,
        benchmark_db=benchmark_db,
        literature_client=literature_client
    )
