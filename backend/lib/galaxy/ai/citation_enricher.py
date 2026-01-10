"""
Citation Enricher for Galaxy Tools

Enriches tool citations by:
1. Extracting DOIs/PMIDs from existing raw citation data
2. Fetching structured citations from bio.tools API
3. Resolving DOIs via CrossRef API
4. Storing structured citation data
"""

import sqlite3
import json
import re
import logging
import time
from typing import List, Dict, Any, Optional, Tuple
from pathlib import Path
import urllib.request
import urllib.parse
import urllib.error

log = logging.getLogger(__name__)

# Regex patterns for extracting identifiers
DOI_PATTERN = re.compile(r'10\.\d{4,}/[^\s"<>\]}\)]+')
PMID_PATTERN = re.compile(r'(?:PMID[:\s]*|pubmed[:/]*)(\d{7,8})', re.IGNORECASE)
PMCID_PATTERN = re.compile(r'PMC\d{6,8}', re.IGNORECASE)


class Citation:
    """Structured citation data."""

    def __init__(
        self,
        doi: Optional[str] = None,
        pmid: Optional[str] = None,
        pmcid: Optional[str] = None,
        title: Optional[str] = None,
        authors: Optional[List[str]] = None,
        journal: Optional[str] = None,
        year: Optional[int] = None,
        url: Optional[str] = None,
        source: str = "unknown"
    ):
        self.doi = doi
        self.pmid = pmid
        self.pmcid = pmcid
        self.title = title
        self.authors = authors or []
        self.journal = journal
        self.year = year
        self.url = url
        self.source = source  # 'bio.tools', 'crossref', 'extracted'

    def to_dict(self) -> Dict[str, Any]:
        return {
            "doi": self.doi,
            "pmid": self.pmid,
            "pmcid": self.pmcid,
            "title": self.title,
            "authors": self.authors,
            "journal": self.journal,
            "year": self.year,
            "url": self.url,
            "source": self.source
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Citation":
        return cls(**data)

    def __repr__(self):
        return f"Citation(doi={self.doi}, title={self.title[:30] if self.title else None}...)"


class CitationEnricher:
    """
    Enriches Galaxy tool citations with structured data.
    """

    BIOTOOLS_API = "https://bio.tools/api/tool"
    CROSSREF_API = "https://api.crossref.org/works"
    PUBMED_API = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"

    def __init__(self, db_path: str, rate_limit: float = 0.5):
        """
        Initialize enricher.

        Args:
            db_path: Path to galaxy_ai_tools.db
            rate_limit: Seconds between API calls
        """
        self.db_path = db_path
        self.rate_limit = rate_limit
        self._last_request = 0

        # Ensure structured_citations column exists
        self._init_schema()

    def _init_schema(self):
        """Add structured_citations column if not exists."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Check if column exists
        cursor.execute("PRAGMA table_info(tools)")
        columns = [row[1] for row in cursor.fetchall()]

        if 'structured_citations' not in columns:
            log.info("Adding structured_citations column to tools table")
            cursor.execute("""
                ALTER TABLE tools ADD COLUMN structured_citations TEXT
            """)
            conn.commit()

        conn.close()

    def _rate_limit_wait(self):
        """Respect API rate limits."""
        elapsed = time.time() - self._last_request
        if elapsed < self.rate_limit:
            time.sleep(self.rate_limit - elapsed)
        self._last_request = time.time()

    def _fetch_url(self, url: str, headers: Dict[str, str] = None) -> Optional[str]:
        """Fetch URL with error handling."""
        self._rate_limit_wait()

        try:
            req = urllib.request.Request(url, headers=headers or {})
            req.add_header('User-Agent', 'BioMate/1.0 (Galaxy AI Assistant)')

            with urllib.request.urlopen(req, timeout=10) as response:
                return response.read().decode('utf-8')
        except Exception as e:
            log.debug(f"Failed to fetch {url}: {e}")
            return None

    def extract_dois_from_text(self, text: str) -> List[str]:
        """Extract DOIs from text."""
        if not text:
            return []

        dois = DOI_PATTERN.findall(text)
        # Clean up DOIs (remove trailing punctuation)
        cleaned = []
        for doi in dois:
            doi = doi.rstrip('.,;:"\'>)}]')
            if len(doi) > 10:  # Valid DOI should be longer
                cleaned.append(doi)

        return list(set(cleaned))

    def extract_pmids_from_text(self, text: str) -> List[str]:
        """Extract PMIDs from text."""
        if not text:
            return []

        pmids = PMID_PATTERN.findall(text)
        return list(set(pmids))

    def extract_from_existing_citations(self, citations_json: str) -> List[Citation]:
        """Extract citations from existing JSON data."""
        if not citations_json:
            return []

        try:
            citations_data = json.loads(citations_json)
        except json.JSONDecodeError:
            return []

        citations = []

        for item in citations_data:
            if not isinstance(item, dict):
                continue

            item_type = item.get('type', '')
            value = item.get('value', '')
            url = item.get('url', '')

            if item_type == 'doi' and value:
                # Clean DOI value
                doi = value.split('>')[0].split('<')[0].strip()
                if doi.startswith('10.'):
                    citations.append(Citation(
                        doi=doi,
                        url=f"https://doi.org/{doi}" if not url else url,
                        source='extracted'
                    ))
            elif item_type == 'text' and value:
                # Try to extract DOIs from text
                dois = self.extract_dois_from_text(value)
                for doi in dois:
                    citations.append(Citation(
                        doi=doi,
                        url=f"https://doi.org/{doi}",
                        source='extracted'
                    ))

                # Try to extract PMIDs
                pmids = self.extract_pmids_from_text(value)
                for pmid in pmids:
                    citations.append(Citation(
                        pmid=pmid,
                        url=f"https://pubmed.ncbi.nlm.nih.gov/{pmid}",
                        source='extracted'
                    ))

        return citations

    def fetch_biotools_citation(self, tool_name: str) -> List[Citation]:
        """Fetch citations from bio.tools API."""
        # Clean tool name for search
        search_name = re.sub(r'[^a-zA-Z0-9\s]', '', tool_name).strip()
        if not search_name or len(search_name) < 2:
            return []

        url = f"{self.BIOTOOLS_API}?q={urllib.parse.quote(search_name)}&format=json"

        response = self._fetch_url(url)
        if not response:
            return []

        try:
            data = json.loads(response)
        except json.JSONDecodeError:
            return []

        citations = []

        for tool in data.get('list', [])[:3]:  # Check top 3 matches
            # Check if tool name is similar
            biotools_name = tool.get('name', '').lower()
            if search_name.lower() not in biotools_name and biotools_name not in search_name.lower():
                continue

            for pub in tool.get('publication', []):
                citation = Citation(source='bio.tools')

                if pub.get('doi'):
                    citation.doi = pub['doi']
                    citation.url = f"https://doi.org/{pub['doi']}"

                if pub.get('pmid'):
                    citation.pmid = str(pub['pmid'])

                if pub.get('pmcid'):
                    citation.pmcid = pub['pmcid']

                # Get metadata if available
                metadata = pub.get('metadata', {})
                if metadata:
                    citation.title = metadata.get('title')
                    citation.journal = metadata.get('journal')
                    citation.year = metadata.get('date', '')[:4] if metadata.get('date') else None

                    authors = metadata.get('authors', [])
                    if authors:
                        citation.authors = [a.get('name', '') for a in authors if a.get('name')]

                if citation.doi or citation.pmid:
                    citations.append(citation)

        return citations

    def resolve_doi_crossref(self, doi: str) -> Optional[Citation]:
        """Resolve DOI metadata via CrossRef."""
        url = f"{self.CROSSREF_API}/{urllib.parse.quote(doi, safe='')}"

        response = self._fetch_url(url)
        if not response:
            return None

        try:
            data = json.loads(response)
        except json.JSONDecodeError:
            return None

        work = data.get('message', {})
        if not work:
            return None

        citation = Citation(
            doi=doi,
            url=f"https://doi.org/{doi}",
            source='crossref'
        )

        # Extract title
        titles = work.get('title', [])
        if titles:
            citation.title = titles[0]

        # Extract authors
        authors = work.get('author', [])
        citation.authors = [
            f"{a.get('given', '')} {a.get('family', '')}".strip()
            for a in authors if a.get('family')
        ]

        # Extract journal
        container = work.get('container-title', [])
        if container:
            citation.journal = container[0]

        # Extract year
        published = work.get('published-print') or work.get('published-online') or work.get('created')
        if published and published.get('date-parts'):
            parts = published['date-parts'][0]
            if parts:
                citation.year = parts[0]

        return citation

    def enrich_tool(self, tool_id: str, tool_name: str, existing_citations: str) -> List[Citation]:
        """Enrich citations for a single tool."""
        all_citations = []
        seen_dois = set()
        seen_pmids = set()

        # 1. Extract from existing data
        extracted = self.extract_from_existing_citations(existing_citations)
        for c in extracted:
            if c.doi and c.doi not in seen_dois:
                seen_dois.add(c.doi)
                all_citations.append(c)
            elif c.pmid and c.pmid not in seen_pmids:
                seen_pmids.add(c.pmid)
                all_citations.append(c)

        # 2. Fetch from bio.tools if no citations found
        if not all_citations:
            biotools = self.fetch_biotools_citation(tool_name)
            for c in biotools:
                if c.doi and c.doi not in seen_dois:
                    seen_dois.add(c.doi)
                    all_citations.append(c)
                elif c.pmid and c.pmid not in seen_pmids:
                    seen_pmids.add(c.pmid)
                    all_citations.append(c)

        # 3. Resolve DOIs via CrossRef to get metadata
        for citation in all_citations:
            if citation.doi and not citation.title:
                resolved = self.resolve_doi_crossref(citation.doi)
                if resolved:
                    citation.title = resolved.title
                    citation.authors = resolved.authors
                    citation.journal = resolved.journal
                    citation.year = resolved.year

        return all_citations

    def enrich_all_tools(
        self,
        limit: int = None,
        skip_existing: bool = True,
        resolve_metadata: bool = True
    ) -> Dict[str, int]:
        """
        Enrich citations for all tools.

        Args:
            limit: Maximum number of tools to process
            skip_existing: Skip tools that already have structured_citations
            resolve_metadata: Resolve DOI metadata via CrossRef (slower but more complete)

        Returns:
            Stats dict with counts
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Get tools to process
        if skip_existing:
            query = """
                SELECT tool_id, name, citations
                FROM tools
                WHERE structured_citations IS NULL OR structured_citations = '[]'
            """
        else:
            query = "SELECT tool_id, name, citations FROM tools"

        if limit:
            query += f" LIMIT {limit}"

        cursor.execute(query)
        tools = cursor.fetchall()

        stats = {
            'total': len(tools),
            'enriched': 0,
            'with_doi': 0,
            'with_pmid': 0,
            'from_biotools': 0,
            'errors': 0
        }

        log.info(f"Processing {len(tools)} tools...")

        for i, (tool_id, name, citations) in enumerate(tools):
            try:
                enriched = self.enrich_tool(tool_id, name, citations)

                if enriched:
                    # Convert to JSON and store
                    citations_json = json.dumps([c.to_dict() for c in enriched])

                    cursor.execute(
                        "UPDATE tools SET structured_citations = ? WHERE tool_id = ?",
                        (citations_json, tool_id)
                    )

                    stats['enriched'] += 1

                    for c in enriched:
                        if c.doi:
                            stats['with_doi'] += 1
                        if c.pmid:
                            stats['with_pmid'] += 1
                        if c.source == 'bio.tools':
                            stats['from_biotools'] += 1

                # Commit every 100 tools
                if (i + 1) % 100 == 0:
                    conn.commit()
                    log.info(f"Processed {i + 1}/{len(tools)} tools, enriched {stats['enriched']}")

            except Exception as e:
                log.error(f"Error processing tool {tool_id}: {e}")
                stats['errors'] += 1

        conn.commit()
        conn.close()

        log.info(f"Enrichment complete: {stats}")
        return stats

    def get_stats(self) -> Dict[str, int]:
        """Get current citation statistics."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        stats = {}

        # Total tools
        cursor.execute("SELECT COUNT(*) FROM tools")
        stats['total_tools'] = cursor.fetchone()[0]

        # Tools with any citations
        cursor.execute("SELECT COUNT(*) FROM tools WHERE citations IS NOT NULL AND length(citations) > 10")
        stats['with_raw_citations'] = cursor.fetchone()[0]

        # Tools with structured citations
        cursor.execute("SELECT COUNT(*) FROM tools WHERE structured_citations IS NOT NULL AND structured_citations != '[]'")
        stats['with_structured_citations'] = cursor.fetchone()[0]

        # Count DOIs and PMIDs in structured citations
        cursor.execute("SELECT structured_citations FROM tools WHERE structured_citations IS NOT NULL")

        doi_count = 0
        pmid_count = 0

        for row in cursor.fetchall():
            try:
                citations = json.loads(row[0])
                for c in citations:
                    if c.get('doi'):
                        doi_count += 1
                    if c.get('pmid'):
                        pmid_count += 1
            except:
                pass

        stats['total_dois'] = doi_count
        stats['total_pmids'] = pmid_count

        conn.close()
        return stats


def main():
    """CLI for citation enrichment."""
    import argparse

    logging.basicConfig(level=logging.INFO)

    parser = argparse.ArgumentParser(description='Enrich Galaxy tool citations')
    parser.add_argument('--db', default='database/galaxy_ai_tools.db', help='Database path')
    parser.add_argument('--limit', type=int, help='Limit number of tools to process')
    parser.add_argument('--stats', action='store_true', help='Show statistics only')
    parser.add_argument('--force', action='store_true', help='Reprocess all tools')

    args = parser.parse_args()

    enricher = CitationEnricher(args.db)

    if args.stats:
        stats = enricher.get_stats()
        print("\nCitation Statistics:")
        for k, v in stats.items():
            print(f"  {k}: {v}")
    else:
        stats = enricher.enrich_all_tools(
            limit=args.limit,
            skip_existing=not args.force
        )
        print("\nEnrichment Results:")
        for k, v in stats.items():
            print(f"  {k}: {v}")


if __name__ == '__main__':
    main()
