"""
Literature Search Clients

Provides interfaces to major scientific literature databases:
- PubMed (NCBI E-utilities)
- arXiv (arXiv API)
- Semantic Scholar (S2 API)

Used by ResearchAgent to retrieve citations for evidence-based answers.
"""

import logging
import asyncio
import aiohttp
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any
from datetime import datetime
import json
import re
import time

log = logging.getLogger(__name__)


@dataclass
class LiteratureCitation:
    """A citation from literature search."""
    title: str
    authors: List[str] = field(default_factory=list)
    year: Optional[int] = None
    journal: Optional[str] = None
    doi: Optional[str] = None
    pmid: Optional[str] = None
    arxiv_id: Optional[str] = None
    abstract: Optional[str] = None
    url: Optional[str] = None
    source: str = "unknown"  # "pubmed", "arxiv", "semantic_scholar"
    relevance_score: float = 0.0
    citation_count: int = 0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "title": self.title,
            "authors": self.authors,
            "year": self.year,
            "journal": self.journal,
            "doi": self.doi,
            "pmid": self.pmid,
            "arxiv_id": self.arxiv_id,
            "abstract": self.abstract,
            "url": self.url,
            "source": self.source,
            "relevance_score": self.relevance_score,
            "citation_count": self.citation_count,
        }

    def format_apa(self) -> str:
        """Format citation in APA style."""
        authors_str = ", ".join(self.authors[:3])
        if len(self.authors) > 3:
            authors_str += " et al."
        year_str = f"({self.year})" if self.year else "(n.d.)"
        journal_str = f" {self.journal}." if self.journal else ""
        doi_str = f" https://doi.org/{self.doi}" if self.doi else ""
        return f"{authors_str} {year_str}. {self.title}.{journal_str}{doi_str}"


class PubMedClient:
    """
    Client for NCBI PubMed E-utilities API.

    API Docs: https://www.ncbi.nlm.nih.gov/books/NBK25500/
    """

    BASE_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"

    def __init__(self, api_key: Optional[str] = None, email: Optional[str] = None):
        """
        Initialize PubMed client.

        Args:
            api_key: NCBI API key (optional, increases rate limit)
            email: Contact email (recommended by NCBI)
        """
        self.api_key = api_key
        self.email = email or "biomate@example.com"
        self._last_request = 0
        self._rate_limit = 0.34 if api_key else 1.0  # seconds between requests

    async def _rate_limit_wait(self):
        """Respect NCBI rate limits."""
        elapsed = time.time() - self._last_request
        if elapsed < self._rate_limit:
            await asyncio.sleep(self._rate_limit - elapsed)
        self._last_request = time.time()

    async def search(
        self,
        query: str,
        max_results: int = 10,
        sort: str = "relevance",
        min_date: Optional[str] = None,
        max_date: Optional[str] = None
    ) -> List[LiteratureCitation]:
        """
        Search PubMed for articles.

        Args:
            query: Search query (supports PubMed query syntax)
            max_results: Maximum number of results to return
            sort: Sort order ("relevance" or "date")
            min_date: Minimum publication date (YYYY/MM/DD)
            max_date: Maximum publication date (YYYY/MM/DD)

        Returns:
            List of LiteratureCitation objects
        """
        await self._rate_limit_wait()

        # Build search params
        params = {
            "db": "pubmed",
            "term": query,
            "retmax": max_results,
            "sort": sort,
            "retmode": "json",
            "email": self.email,
        }
        if self.api_key:
            params["api_key"] = self.api_key
        if min_date:
            params["mindate"] = min_date
        if max_date:
            params["maxdate"] = max_date
            params["datetype"] = "pdat"  # publication date

        try:
            async with aiohttp.ClientSession() as session:
                # Step 1: Search for PMIDs
                search_url = f"{self.BASE_URL}/esearch.fcgi"
                async with session.get(search_url, params=params) as resp:
                    if resp.status != 200:
                        log.warning(f"PubMed search failed: {resp.status}")
                        return []

                    data = await resp.json()
                    pmids = data.get("esearchresult", {}).get("idlist", [])

                    if not pmids:
                        return []

                # Step 2: Fetch article details
                await self._rate_limit_wait()
                fetch_params = {
                    "db": "pubmed",
                    "id": ",".join(pmids),
                    "retmode": "xml",
                    "email": self.email,
                }
                if self.api_key:
                    fetch_params["api_key"] = self.api_key

                fetch_url = f"{self.BASE_URL}/efetch.fcgi"
                async with session.get(fetch_url, params=fetch_params) as resp:
                    if resp.status != 200:
                        log.warning(f"PubMed fetch failed: {resp.status}")
                        return []

                    xml_text = await resp.text()
                    return self._parse_pubmed_xml(xml_text)

        except Exception as e:
            log.error(f"PubMed search error: {e}")
            return []

    def _parse_pubmed_xml(self, xml_text: str) -> List[LiteratureCitation]:
        """Parse PubMed XML response."""
        citations = []

        try:
            root = ET.fromstring(xml_text)

            for article in root.findall(".//PubmedArticle"):
                try:
                    # Extract PMID
                    pmid_elem = article.find(".//PMID")
                    pmid = pmid_elem.text if pmid_elem is not None else None

                    # Extract title
                    title_elem = article.find(".//ArticleTitle")
                    title = title_elem.text if title_elem is not None else "Unknown Title"

                    # Extract authors
                    authors = []
                    for author in article.findall(".//Author"):
                        last = author.find("LastName")
                        fore = author.find("ForeName")
                        if last is not None and fore is not None:
                            authors.append(f"{last.text} {fore.text[0]}")
                        elif last is not None:
                            authors.append(last.text)

                    # Extract year
                    year = None
                    pub_date = article.find(".//PubDate/Year")
                    if pub_date is not None:
                        try:
                            year = int(pub_date.text)
                        except ValueError:
                            pass

                    # Extract journal
                    journal_elem = article.find(".//Journal/Title")
                    journal = journal_elem.text if journal_elem is not None else None

                    # Extract DOI
                    doi = None
                    for id_elem in article.findall(".//ArticleId"):
                        if id_elem.get("IdType") == "doi":
                            doi = id_elem.text
                            break

                    # Extract abstract
                    abstract_parts = []
                    for abstract_elem in article.findall(".//AbstractText"):
                        if abstract_elem.text:
                            abstract_parts.append(abstract_elem.text)
                    abstract = " ".join(abstract_parts) if abstract_parts else None

                    citations.append(LiteratureCitation(
                        title=title,
                        authors=authors,
                        year=year,
                        journal=journal,
                        doi=doi,
                        pmid=pmid,
                        abstract=abstract,
                        url=f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/" if pmid else None,
                        source="pubmed",
                    ))

                except Exception as e:
                    log.warning(f"Error parsing PubMed article: {e}")
                    continue

        except ET.ParseError as e:
            log.error(f"Error parsing PubMed XML: {e}")

        return citations


class ArxivClient:
    """
    Client for arXiv API.

    API Docs: https://info.arxiv.org/help/api/index.html
    """

    BASE_URL = "http://export.arxiv.org/api/query"

    def __init__(self):
        self._last_request = 0
        self._rate_limit = 3.0  # arXiv recommends 3 seconds between requests

    async def _rate_limit_wait(self):
        """Respect arXiv rate limits."""
        elapsed = time.time() - self._last_request
        if elapsed < self._rate_limit:
            await asyncio.sleep(self._rate_limit - elapsed)
        self._last_request = time.time()

    async def search(
        self,
        query: str,
        max_results: int = 10,
        sort_by: str = "relevance",
        categories: Optional[List[str]] = None
    ) -> List[LiteratureCitation]:
        """
        Search arXiv for papers.

        Args:
            query: Search query
            max_results: Maximum number of results
            sort_by: Sort order ("relevance", "lastUpdatedDate", "submittedDate")
            categories: Filter by arXiv categories (e.g., ["q-bio.GN", "cs.LG"])

        Returns:
            List of LiteratureCitation objects
        """
        await self._rate_limit_wait()

        # Build search query
        search_query = f"all:{query}"
        if categories:
            cat_query = " OR ".join([f"cat:{cat}" for cat in categories])
            search_query = f"({search_query}) AND ({cat_query})"

        params = {
            "search_query": search_query,
            "start": 0,
            "max_results": max_results,
            "sortBy": sort_by,
            "sortOrder": "descending",
        }

        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(self.BASE_URL, params=params) as resp:
                    if resp.status != 200:
                        log.warning(f"arXiv search failed: {resp.status}")
                        return []

                    xml_text = await resp.text()
                    return self._parse_arxiv_xml(xml_text)

        except Exception as e:
            log.error(f"arXiv search error: {e}")
            return []

    def _parse_arxiv_xml(self, xml_text: str) -> List[LiteratureCitation]:
        """Parse arXiv Atom XML response."""
        citations = []

        # Define namespaces
        ns = {
            "atom": "http://www.w3.org/2005/Atom",
            "arxiv": "http://arxiv.org/schemas/atom",
        }

        try:
            root = ET.fromstring(xml_text)

            for entry in root.findall("atom:entry", ns):
                try:
                    # Extract arXiv ID
                    id_elem = entry.find("atom:id", ns)
                    arxiv_url = id_elem.text if id_elem is not None else ""
                    arxiv_id = arxiv_url.split("/abs/")[-1] if "/abs/" in arxiv_url else None

                    # Extract title
                    title_elem = entry.find("atom:title", ns)
                    title = title_elem.text.strip().replace("\n", " ") if title_elem is not None else "Unknown"

                    # Extract authors
                    authors = []
                    for author in entry.findall("atom:author", ns):
                        name = author.find("atom:name", ns)
                        if name is not None:
                            authors.append(name.text)

                    # Extract year from published date
                    year = None
                    published = entry.find("atom:published", ns)
                    if published is not None and published.text:
                        try:
                            year = int(published.text[:4])
                        except ValueError:
                            pass

                    # Extract abstract
                    summary = entry.find("atom:summary", ns)
                    abstract = summary.text.strip().replace("\n", " ") if summary is not None else None

                    # Extract DOI if available
                    doi = None
                    doi_elem = entry.find("arxiv:doi", ns)
                    if doi_elem is not None:
                        doi = doi_elem.text

                    # Extract primary category
                    primary_cat = entry.find("arxiv:primary_category", ns)
                    category = primary_cat.get("term") if primary_cat is not None else None

                    citations.append(LiteratureCitation(
                        title=title,
                        authors=authors,
                        year=year,
                        journal=f"arXiv:{category}" if category else "arXiv",
                        doi=doi,
                        arxiv_id=arxiv_id,
                        abstract=abstract,
                        url=arxiv_url,
                        source="arxiv",
                    ))

                except Exception as e:
                    log.warning(f"Error parsing arXiv entry: {e}")
                    continue

        except ET.ParseError as e:
            log.error(f"Error parsing arXiv XML: {e}")

        return citations


class SemanticScholarClient:
    """
    Client for Semantic Scholar Academic Graph API.

    API Docs: https://api.semanticscholar.org/api-docs/
    """

    BASE_URL = "https://api.semanticscholar.org/graph/v1"

    def __init__(self, api_key: Optional[str] = None):
        """
        Initialize Semantic Scholar client.

        Args:
            api_key: S2 API key (optional, increases rate limit)
        """
        self.api_key = api_key
        self._last_request = 0
        self._rate_limit = 1.0 if api_key else 5.0  # seconds between requests

    async def _rate_limit_wait(self):
        """Respect S2 rate limits."""
        elapsed = time.time() - self._last_request
        if elapsed < self._rate_limit:
            await asyncio.sleep(self._rate_limit - elapsed)
        self._last_request = time.time()

    async def search(
        self,
        query: str,
        max_results: int = 10,
        year_range: Optional[tuple] = None,
        fields_of_study: Optional[List[str]] = None,
        open_access_only: bool = False
    ) -> List[LiteratureCitation]:
        """
        Search Semantic Scholar for papers.

        Args:
            query: Search query
            max_results: Maximum number of results
            year_range: Filter by year range (start, end)
            fields_of_study: Filter by fields (e.g., ["Biology", "Medicine"])
            open_access_only: Only return open access papers

        Returns:
            List of LiteratureCitation objects
        """
        await self._rate_limit_wait()

        params = {
            "query": query,
            "limit": max_results,
            "fields": "title,authors,year,venue,externalIds,abstract,citationCount,openAccessPdf",
        }

        if year_range:
            params["year"] = f"{year_range[0]}-{year_range[1]}"
        if fields_of_study:
            params["fieldsOfStudy"] = ",".join(fields_of_study)
        if open_access_only:
            params["openAccessPdf"] = ""

        headers = {}
        if self.api_key:
            headers["x-api-key"] = self.api_key

        try:
            async with aiohttp.ClientSession() as session:
                url = f"{self.BASE_URL}/paper/search"
                async with session.get(url, params=params, headers=headers) as resp:
                    if resp.status != 200:
                        log.warning(f"Semantic Scholar search failed: {resp.status}")
                        return []

                    data = await resp.json()
                    return self._parse_s2_response(data)

        except Exception as e:
            log.error(f"Semantic Scholar search error: {e}")
            return []

    def _parse_s2_response(self, data: Dict[str, Any]) -> List[LiteratureCitation]:
        """Parse Semantic Scholar JSON response."""
        citations = []

        for paper in data.get("data", []):
            try:
                # Extract authors
                authors = []
                for author in paper.get("authors", []):
                    if author.get("name"):
                        authors.append(author["name"])

                # Extract external IDs
                external_ids = paper.get("externalIds", {})
                doi = external_ids.get("DOI")
                pmid = external_ids.get("PubMed")
                arxiv_id = external_ids.get("ArXiv")

                # Get URL
                url = None
                open_access = paper.get("openAccessPdf")
                if open_access and open_access.get("url"):
                    url = open_access["url"]
                elif doi:
                    url = f"https://doi.org/{doi}"

                citations.append(LiteratureCitation(
                    title=paper.get("title", "Unknown"),
                    authors=authors,
                    year=paper.get("year"),
                    journal=paper.get("venue"),
                    doi=doi,
                    pmid=pmid,
                    arxiv_id=arxiv_id,
                    abstract=paper.get("abstract"),
                    url=url,
                    source="semantic_scholar",
                    citation_count=paper.get("citationCount", 0),
                ))

            except Exception as e:
                log.warning(f"Error parsing S2 paper: {e}")
                continue

        return citations

    async def get_paper_by_id(
        self,
        paper_id: str,
        id_type: str = "DOI"
    ) -> Optional[LiteratureCitation]:
        """
        Get a specific paper by ID.

        Args:
            paper_id: The paper identifier
            id_type: Type of ID ("DOI", "PMID", "ArXiv", "S2")

        Returns:
            LiteratureCitation or None
        """
        await self._rate_limit_wait()

        # Format paper ID based on type
        if id_type == "DOI":
            formatted_id = f"DOI:{paper_id}"
        elif id_type == "PMID":
            formatted_id = f"PMID:{paper_id}"
        elif id_type == "ArXiv":
            formatted_id = f"ArXiv:{paper_id}"
        else:
            formatted_id = paper_id

        params = {
            "fields": "title,authors,year,venue,externalIds,abstract,citationCount,openAccessPdf",
        }

        headers = {}
        if self.api_key:
            headers["x-api-key"] = self.api_key

        try:
            async with aiohttp.ClientSession() as session:
                url = f"{self.BASE_URL}/paper/{formatted_id}"
                async with session.get(url, params=params, headers=headers) as resp:
                    if resp.status != 200:
                        return None

                    data = await resp.json()
                    results = self._parse_s2_response({"data": [data]})
                    return results[0] if results else None

        except Exception as e:
            log.error(f"Semantic Scholar get paper error: {e}")
            return None


class UnifiedLiteratureClient:
    """
    Unified interface for searching multiple literature databases.
    """

    def __init__(
        self,
        pubmed_api_key: Optional[str] = None,
        s2_api_key: Optional[str] = None
    ):
        self.pubmed = PubMedClient(api_key=pubmed_api_key)
        self.arxiv = ArxivClient()
        self.semantic_scholar = SemanticScholarClient(api_key=s2_api_key)

    async def search_all(
        self,
        query: str,
        max_results_per_source: int = 5,
        sources: Optional[List[str]] = None,
        deduplicate: bool = True
    ) -> List[LiteratureCitation]:
        """
        Search all literature databases.

        Args:
            query: Search query
            max_results_per_source: Max results from each source
            sources: Which sources to search (default: all)
            deduplicate: Remove duplicate papers (by DOI/PMID)

        Returns:
            Combined list of citations
        """
        if sources is None:
            sources = ["pubmed", "arxiv", "semantic_scholar"]

        # Run searches in parallel
        tasks = []
        if "pubmed" in sources:
            tasks.append(self.pubmed.search(query, max_results_per_source))
        if "arxiv" in sources:
            tasks.append(self.arxiv.search(query, max_results_per_source))
        if "semantic_scholar" in sources:
            tasks.append(self.semantic_scholar.search(query, max_results_per_source))

        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Combine results
        all_citations = []
        for result in results:
            if isinstance(result, list):
                all_citations.extend(result)
            elif isinstance(result, Exception):
                log.warning(f"Literature search error: {result}")

        # Deduplicate by DOI or PMID
        if deduplicate:
            seen = set()
            unique = []
            for citation in all_citations:
                key = citation.doi or citation.pmid or citation.arxiv_id or citation.title
                if key and key not in seen:
                    seen.add(key)
                    unique.append(citation)
            all_citations = unique

        # Sort by relevance (citation count as proxy)
        all_citations.sort(key=lambda c: c.citation_count, reverse=True)

        return all_citations

    async def search_bioinformatics(
        self,
        query: str,
        max_results: int = 10,
        recent_years: int = 5
    ) -> List[LiteratureCitation]:
        """
        Search specifically for bioinformatics/computational biology papers.

        Args:
            query: Search query
            max_results: Maximum total results
            recent_years: Only papers from last N years

        Returns:
            List of citations
        """
        current_year = datetime.now().year
        min_year = current_year - recent_years

        # Enhance query for bioinformatics
        enhanced_query = f"{query} AND (bioinformatics OR computational biology OR genomics OR proteomics)"

        # Search with year filters
        tasks = [
            self.pubmed.search(
                enhanced_query,
                max_results // 2,
                min_date=f"{min_year}/01/01"
            ),
            self.semantic_scholar.search(
                query,
                max_results // 2,
                year_range=(min_year, current_year),
                fields_of_study=["Biology", "Computer Science"]
            ),
        ]

        results = await asyncio.gather(*tasks, return_exceptions=True)

        all_citations = []
        for result in results:
            if isinstance(result, list):
                all_citations.extend(result)

        # Deduplicate and sort
        seen = set()
        unique = []
        for citation in all_citations:
            key = citation.doi or citation.pmid or citation.title
            if key and key not in seen:
                seen.add(key)
                unique.append(citation)

        unique.sort(key=lambda c: (c.year or 0, c.citation_count), reverse=True)

        return unique[:max_results]


# Factory function
def create_literature_client(
    pubmed_api_key: Optional[str] = None,
    s2_api_key: Optional[str] = None
) -> UnifiedLiteratureClient:
    """Create a UnifiedLiteratureClient instance."""
    return UnifiedLiteratureClient(
        pubmed_api_key=pubmed_api_key,
        s2_api_key=s2_api_key
    )
