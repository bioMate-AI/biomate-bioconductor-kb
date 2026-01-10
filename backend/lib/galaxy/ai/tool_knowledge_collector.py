"""
Tool Knowledge Collector

Collects citations, benchmarking papers, and best practices for key bioinformatics tools.
Focuses on Biomni and nf-core tools.
"""

import sqlite3
import json
import re
import logging
import time
import urllib.request
import urllib.parse
from typing import List, Dict, Any, Optional, Set
from dataclasses import dataclass, asdict
from pathlib import Path

log = logging.getLogger(__name__)


@dataclass
class Publication:
    """Publication metadata."""
    doi: Optional[str] = None
    pmid: Optional[str] = None
    title: Optional[str] = None
    authors: List[str] = None
    journal: Optional[str] = None
    year: Optional[int] = None
    abstract: Optional[str] = None
    citation_count: Optional[int] = None
    pub_type: str = "tool"  # 'tool', 'benchmark', 'review', 'protocol'
    url: Optional[str] = None

    def __post_init__(self):
        if self.authors is None:
            self.authors = []

    def to_dict(self):
        return asdict(self)


@dataclass
class ToolKnowledge:
    """Knowledge about a bioinformatics tool."""
    tool_name: str
    tool_id: Optional[str] = None
    category: Optional[str] = None

    # Publications
    primary_citation: Optional[Publication] = None
    benchmark_papers: List[Publication] = None
    review_papers: List[Publication] = None

    # Best practices
    recommended_parameters: Dict[str, Any] = None
    use_cases: List[str] = None
    limitations: List[str] = None
    alternatives: List[str] = None

    # Metadata
    last_updated: Optional[str] = None

    def __post_init__(self):
        if self.benchmark_papers is None:
            self.benchmark_papers = []
        if self.review_papers is None:
            self.review_papers = []
        if self.recommended_parameters is None:
            self.recommended_parameters = {}
        if self.use_cases is None:
            self.use_cases = []
        if self.limitations is None:
            self.limitations = []
        if self.alternatives is None:
            self.alternatives = []


class ToolKnowledgeCollector:
    """Collects and stores tool knowledge from multiple sources."""

    PUBMED_SEARCH = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
    PUBMED_FETCH = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
    PUBMED_SUMMARY = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi"
    SEMANTIC_SCHOLAR = "https://api.semanticscholar.org/graph/v1/paper/search"
    CROSSREF_API = "https://api.crossref.org/works"

    def __init__(self, db_path: str, rate_limit: float = 0.35):
        self.db_path = db_path
        self.rate_limit = rate_limit
        self._last_request = 0
        self._init_schema()

    def _init_schema(self):
        """Create tool_knowledge table."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tool_knowledge (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                tool_name TEXT UNIQUE NOT NULL,
                tool_id TEXT,
                category TEXT,
                primary_citation TEXT,  -- JSON
                benchmark_papers TEXT,  -- JSON array
                review_papers TEXT,     -- JSON array
                recommended_parameters TEXT,  -- JSON
                use_cases TEXT,         -- JSON array
                limitations TEXT,       -- JSON array
                alternatives TEXT,      -- JSON array
                raw_pubmed_results TEXT,  -- JSON for debugging
                last_updated TEXT
            )
        """)

        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_tool_knowledge_name
            ON tool_knowledge(tool_name)
        """)

        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_tool_knowledge_category
            ON tool_knowledge(category)
        """)

        conn.commit()
        conn.close()

    def _rate_limit_wait(self):
        """Respect API rate limits."""
        elapsed = time.time() - self._last_request
        if elapsed < self.rate_limit:
            time.sleep(self.rate_limit - elapsed)
        self._last_request = time.time()

    def _fetch_url(self, url: str, headers: Dict = None) -> Optional[str]:
        """Fetch URL with error handling."""
        self._rate_limit_wait()
        try:
            req = urllib.request.Request(url, headers=headers or {})
            req.add_header('User-Agent', 'BioMate/1.0 (mailto:admin@biomate.io)')
            with urllib.request.urlopen(req, timeout=15) as response:
                return response.read().decode('utf-8')
        except Exception as e:
            log.debug(f"Failed to fetch {url}: {e}")
            return None

    def search_pubmed(self, query: str, max_results: int = 10) -> List[Dict]:
        """Search PubMed for publications."""
        # Search
        search_url = f"{self.PUBMED_SEARCH}?db=pubmed&term={urllib.parse.quote(query)}&retmax={max_results}&retmode=json"
        search_result = self._fetch_url(search_url)

        if not search_result:
            return []

        try:
            search_data = json.loads(search_result)
            pmids = search_data.get('esearchresult', {}).get('idlist', [])
        except:
            return []

        if not pmids:
            return []

        # Fetch summaries
        pmid_str = ','.join(pmids)
        summary_url = f"{self.PUBMED_SUMMARY}?db=pubmed&id={pmid_str}&retmode=json"
        summary_result = self._fetch_url(summary_url)

        if not summary_result:
            return []

        try:
            summary_data = json.loads(summary_result)
            results = summary_data.get('result', {})
        except:
            return []

        publications = []
        for pmid in pmids:
            if pmid not in results:
                continue

            article = results[pmid]
            if not isinstance(article, dict):
                continue

            # Extract authors
            authors = []
            for author in article.get('authors', [])[:5]:
                if isinstance(author, dict):
                    authors.append(author.get('name', ''))

            pub = {
                'pmid': pmid,
                'doi': None,
                'title': article.get('title', ''),
                'authors': authors,
                'journal': article.get('source', ''),
                'year': None,
                'abstract': None,
                'citation_count': None,
                'url': f"https://pubmed.ncbi.nlm.nih.gov/{pmid}"
            }

            # Extract year from pubdate
            pubdate = article.get('pubdate', '')
            if pubdate:
                year_match = re.search(r'(\d{4})', pubdate)
                if year_match:
                    pub['year'] = int(year_match.group(1))

            # Extract DOI from articleids
            for aid in article.get('articleids', []):
                if isinstance(aid, dict) and aid.get('idtype') == 'doi':
                    pub['doi'] = aid.get('value')
                    break

            publications.append(pub)

        return publications

    def search_semantic_scholar(self, query: str, max_results: int = 5) -> List[Dict]:
        """Search Semantic Scholar for papers with citation counts."""
        url = f"{self.SEMANTIC_SCHOLAR}?query={urllib.parse.quote(query)}&limit={max_results}&fields=title,authors,year,citationCount,abstract,externalIds,venue"

        result = self._fetch_url(url)
        if not result:
            return []

        try:
            data = json.loads(result)
            papers = data.get('data', [])
        except:
            return []

        publications = []
        for paper in papers:
            authors = [a.get('name', '') for a in paper.get('authors', [])[:5]]
            ext_ids = paper.get('externalIds', {}) or {}

            pub = {
                'pmid': ext_ids.get('PubMed'),
                'doi': ext_ids.get('DOI'),
                'title': paper.get('title', ''),
                'authors': authors,
                'journal': paper.get('venue', ''),
                'year': paper.get('year'),
                'abstract': paper.get('abstract', '')[:500] if paper.get('abstract') else None,
                'citation_count': paper.get('citationCount'),
                'url': f"https://doi.org/{ext_ids['DOI']}" if ext_ids.get('DOI') else None
            }
            publications.append(pub)

        return publications

    def search_tool_citation(self, tool_name: str) -> Optional[Publication]:
        """Find the primary citation for a tool."""
        # Search PubMed for tool paper
        query = f'"{tool_name}"[Title] AND (bioinformatics OR software OR tool OR pipeline)'
        results = self.search_pubmed(query, max_results=5)

        if not results:
            # Try broader search
            query = f'"{tool_name}" bioinformatics'
            results = self.search_pubmed(query, max_results=5)

        if not results:
            # Try Semantic Scholar
            results = self.search_semantic_scholar(f"{tool_name} bioinformatics tool", max_results=3)

        if results:
            # Return the most relevant (first) result
            pub_data = results[0]
            return Publication(
                doi=pub_data.get('doi'),
                pmid=pub_data.get('pmid'),
                title=pub_data.get('title'),
                authors=pub_data.get('authors', []),
                journal=pub_data.get('journal'),
                year=pub_data.get('year'),
                abstract=pub_data.get('abstract'),
                citation_count=pub_data.get('citation_count'),
                pub_type='tool',
                url=pub_data.get('url')
            )

        return None

    def search_benchmarks(self, tool_name: str, category: str = None) -> List[Publication]:
        """Find benchmarking papers for a tool."""
        benchmarks = []

        # Bioinformatics journals to validate results
        BIO_JOURNALS = {
            'nature methods', 'nat methods', 'genome biol', 'genome biology',
            'bioinformatics', 'nucleic acids res', 'nat biotechnol', 'nature biotechnology',
            'cell', 'nature', 'science', 'plos comput biol', 'bmc bioinformatics',
            'briefings in bioinformatics', 'genome res', 'gigascience', 'f1000research',
            'cell systems', 'mol syst biol', 'nat commun', 'elife', 'peerj'
        }

        # Keywords that indicate non-bioinformatics papers to filter out
        EXCLUDE_KEYWORDS = [
            'fish', 'salmon fish', 'atlantic salmon', 'salmo salar',
            'plant growth', 'animal', 'clinical trial', 'patient',
            'mucus', 'mucin', 'epithelial'
        ]

        # Search for benchmark papers with bioinformatics context
        queries = [
            f'"{tool_name}"[Title] AND (benchmark OR comparison) AND (bioinformatics OR software OR algorithm)',
            f'"{tool_name}" benchmark comparison bioinformatics',
            f'"{tool_name}" evaluation performance (sequencing OR genomics OR proteomics)',
        ]

        if category:
            queries.append(f'{category} tools benchmark comparison "{tool_name}"')

        seen_titles = set()

        for query in queries:
            results = self.search_pubmed(query, max_results=5)

            for pub_data in results:
                title = pub_data.get('title', '').lower()
                journal = pub_data.get('journal', '').lower()

                # Skip if we've seen this
                if title in seen_titles:
                    continue

                # Filter out non-bioinformatics papers
                if any(excl in title for excl in EXCLUDE_KEYWORDS):
                    continue

                # Prefer papers from bioinformatics journals
                is_bio_journal = any(j in journal for j in BIO_JOURNALS)

                # Check if it's actually a benchmark/comparison paper
                is_benchmark = any(kw in title for kw in ['benchmark', 'comparison', 'evaluation', 'performance', 'assessment', 'review', 'comprehensive'])

                if is_benchmark or is_bio_journal:
                    seen_titles.add(title)
                    benchmarks.append(Publication(
                        doi=pub_data.get('doi'),
                        pmid=pub_data.get('pmid'),
                        title=pub_data.get('title'),
                        authors=pub_data.get('authors', []),
                        journal=pub_data.get('journal'),
                        year=pub_data.get('year'),
                        citation_count=pub_data.get('citation_count'),
                        pub_type='benchmark',
                        url=pub_data.get('url')
                    ))

        # Also try Semantic Scholar for highly cited benchmarks
        ss_results = self.search_semantic_scholar(f"{tool_name} benchmark bioinformatics", max_results=3)
        for pub_data in ss_results:
            title = pub_data.get('title', '').lower()

            # Filter out non-bioinformatics
            if any(excl in title for excl in EXCLUDE_KEYWORDS):
                continue

            if title not in seen_titles and pub_data.get('citation_count', 0) > 50:
                seen_titles.add(title)
                benchmarks.append(Publication(
                    doi=pub_data.get('doi'),
                    pmid=pub_data.get('pmid'),
                    title=pub_data.get('title'),
                    authors=pub_data.get('authors', []),
                    journal=pub_data.get('journal'),
                    year=pub_data.get('year'),
                    abstract=pub_data.get('abstract'),
                    citation_count=pub_data.get('citation_count'),
                    pub_type='benchmark',
                    url=pub_data.get('url')
                ))

        return benchmarks[:5]  # Limit to top 5

    def collect_tool_knowledge(self, tool_name: str, tool_id: str = None, category: str = None) -> ToolKnowledge:
        """Collect all knowledge about a tool."""
        log.info(f"Collecting knowledge for: {tool_name}")

        knowledge = ToolKnowledge(
            tool_name=tool_name,
            tool_id=tool_id,
            category=category
        )

        # Get primary citation
        knowledge.primary_citation = self.search_tool_citation(tool_name)

        # Get benchmark papers
        knowledge.benchmark_papers = self.search_benchmarks(tool_name, category)

        # Set timestamp
        from datetime import datetime
        knowledge.last_updated = datetime.now().isoformat()

        return knowledge

    def save_knowledge(self, knowledge: ToolKnowledge):
        """Save tool knowledge to database."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        primary_citation_json = json.dumps(knowledge.primary_citation.to_dict()) if knowledge.primary_citation else None
        benchmark_json = json.dumps([p.to_dict() for p in knowledge.benchmark_papers])
        review_json = json.dumps([p.to_dict() for p in knowledge.review_papers])

        cursor.execute("""
            INSERT OR REPLACE INTO tool_knowledge
            (tool_name, tool_id, category, primary_citation, benchmark_papers, review_papers,
             recommended_parameters, use_cases, limitations, alternatives, last_updated)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            knowledge.tool_name,
            knowledge.tool_id,
            knowledge.category,
            primary_citation_json,
            benchmark_json,
            review_json,
            json.dumps(knowledge.recommended_parameters),
            json.dumps(knowledge.use_cases),
            json.dumps(knowledge.limitations),
            json.dumps(knowledge.alternatives),
            knowledge.last_updated
        ))

        conn.commit()
        conn.close()

    def collect_for_category(self, category: str, limit: int = None) -> Dict[str, int]:
        """Collect knowledge for all tools in a category."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        query = "SELECT DISTINCT name, tool_id, category FROM tools WHERE category = ?"
        if limit:
            query += f" LIMIT {limit}"

        cursor.execute(query, (category,))
        tools = cursor.fetchall()
        conn.close()

        stats = {'total': len(tools), 'with_citation': 0, 'with_benchmarks': 0}

        for name, tool_id, cat in tools:
            knowledge = self.collect_tool_knowledge(name, tool_id, cat)
            self.save_knowledge(knowledge)

            if knowledge.primary_citation:
                stats['with_citation'] += 1
            if knowledge.benchmark_papers:
                stats['with_benchmarks'] += 1

            log.info(f"  {name}: citation={knowledge.primary_citation is not None}, benchmarks={len(knowledge.benchmark_papers)}")

        return stats

    def get_key_tools(self) -> List[tuple]:
        """Get list of key bioinformatics tools to collect knowledge for."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Focus on nf-core and important analysis categories
        cursor.execute("""
            SELECT DISTINCT name, tool_id, category
            FROM tools
            WHERE category IN ('nf-core', 'Sequence Analysis', 'Metagenomics', 'Single Cell',
                              'Immunology', 'Systems Biology', 'Biochemistry')
            ORDER BY category, name
        """)

        tools = cursor.fetchall()
        conn.close()
        return tools

    def collect_all_key_tools(self, limit_per_category: int = None) -> Dict[str, Any]:
        """Collect knowledge for all key tools."""
        tools = self.get_key_tools()

        stats = {
            'total_tools': len(tools),
            'processed': 0,
            'with_citation': 0,
            'with_benchmarks': 0,
            'by_category': {}
        }

        log.info(f"Collecting knowledge for {len(tools)} tools...")

        category_counts = {}
        for name, tool_id, category in tools:
            # Limit per category if specified
            if limit_per_category:
                category_counts[category] = category_counts.get(category, 0) + 1
                if category_counts[category] > limit_per_category:
                    continue

            try:
                knowledge = self.collect_tool_knowledge(name, tool_id, category)
                self.save_knowledge(knowledge)

                stats['processed'] += 1
                if knowledge.primary_citation:
                    stats['with_citation'] += 1
                if knowledge.benchmark_papers:
                    stats['with_benchmarks'] += 1

                # Track by category
                if category not in stats['by_category']:
                    stats['by_category'][category] = {'total': 0, 'with_citation': 0}
                stats['by_category'][category]['total'] += 1
                if knowledge.primary_citation:
                    stats['by_category'][category]['with_citation'] += 1

            except Exception as e:
                log.error(f"Error processing {name}: {e}")

            if stats['processed'] % 20 == 0:
                log.info(f"Progress: {stats['processed']}/{len(tools)}")

        return stats

    def get_stats(self) -> Dict[str, int]:
        """Get knowledge base statistics."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        stats = {}

        cursor.execute("SELECT COUNT(*) FROM tool_knowledge")
        stats['total_tools'] = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM tool_knowledge WHERE primary_citation IS NOT NULL")
        stats['with_citations'] = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM tool_knowledge WHERE benchmark_papers IS NOT NULL AND benchmark_papers != '[]'")
        stats['with_benchmarks'] = cursor.fetchone()[0]

        cursor.execute("SELECT category, COUNT(*) FROM tool_knowledge GROUP BY category")
        stats['by_category'] = dict(cursor.fetchall())

        conn.close()
        return stats


def main():
    """CLI for knowledge collection."""
    import argparse

    logging.basicConfig(level=logging.INFO, format='%(message)s')

    parser = argparse.ArgumentParser(description='Collect tool knowledge')
    parser.add_argument('--db', default='database/galaxy_ai_tools.db', help='Database path')
    parser.add_argument('--category', help='Collect for specific category')
    parser.add_argument('--tool', help='Collect for specific tool')
    parser.add_argument('--limit', type=int, help='Limit per category')
    parser.add_argument('--stats', action='store_true', help='Show statistics')

    args = parser.parse_args()

    collector = ToolKnowledgeCollector(args.db)

    if args.stats:
        stats = collector.get_stats()
        print("\nKnowledge Base Statistics:")
        for k, v in stats.items():
            print(f"  {k}: {v}")
    elif args.tool:
        knowledge = collector.collect_tool_knowledge(args.tool)
        collector.save_knowledge(knowledge)
        print(f"\nCollected knowledge for {args.tool}")
        if knowledge.primary_citation:
            print(f"  Citation: {knowledge.primary_citation.title}")
        print(f"  Benchmarks: {len(knowledge.benchmark_papers)}")
    elif args.category:
        stats = collector.collect_for_category(args.category, args.limit)
        print(f"\nCollected for {args.category}: {stats}")
    else:
        stats = collector.collect_all_key_tools(args.limit)
        print(f"\nCollection complete: {stats}")


if __name__ == '__main__':
    main()
