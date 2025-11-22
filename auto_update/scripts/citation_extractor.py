#!/usr/bin/env python3
"""
Enhanced Citation Extractor - Extract DOIs, papers, and citations from repositories

Extracts citations from multiple sources:
1. CITATION.cff files (Citation File Format)
2. README files (DOI patterns, paper references)
3. GitHub repository metadata (papers with code links)
4. codemeta.json files
5. CrossRef API for validation and enrichment

Usage:
    from citation_extractor import CitationExtractor
    extractor = CitationExtractor()
    citations = extractor.extract_citations(repo_full_name="owner/repo", readme_text="...")
"""

import json
import re
import requests
import yaml
from pathlib import Path
from typing import Dict, List, Optional
from github import Github, Auth

class CitationExtractor:
    """
    Extracts citations from multiple sources and formats them consistently.
    """

    def __init__(self, github_token: Optional[str] = None):
        """
        Initialize citation extractor.

        Args:
            github_token: GitHub API token (optional, for fetching repository files)
        """
        if github_token:
            auth = Auth.Token(github_token)
            self.github = Github(auth=auth)
        else:
            self.github = None
        self.crossref_api = "https://api.crossref.org/works/"

    def extract_citations(
        self,
        repo_full_name: str,
        readme_text: str,
        github_metadata: Optional[Dict] = None
    ) -> List[Dict]:
        """
        Extract all citations from a repository.

        Args:
            repo_full_name: Full repository name (owner/repo)
            readme_text: README content
            github_metadata: Optional GitHub repository metadata

        Returns:
            List of citation dictionaries:
            [
                {
                    "type": "doi" | "paper" | "arxiv" | "bibtex",
                    "value": "citation identifier",
                    "title": "Paper title",
                    "authors": ["Author 1", "Author 2"],
                    "year": 2024,
                    "url": "https://...",
                    "journal": "Journal Name",
                    "source": "CITATION.cff" | "README" | "codemeta.json"
                }
            ]
        """
        citations = []

        # 1. Extract from CITATION.cff
        if self.github:
            citation_cff = self._fetch_citation_cff(repo_full_name)
            if citation_cff:
                citations.extend(self._parse_citation_cff(citation_cff))

        # 2. Extract from codemeta.json
        if self.github:
            codemeta = self._fetch_codemeta(repo_full_name)
            if codemeta:
                citations.extend(self._parse_codemeta(codemeta))

        # 3. Extract DOIs from README
        readme_citations = self._extract_dois_from_text(readme_text, source="README")
        citations.extend(readme_citations)

        # 4. Extract arXiv references
        arxiv_citations = self._extract_arxiv_from_text(readme_text, source="README")
        citations.extend(arxiv_citations)

        # 5. Extract PubMed references
        pubmed_citations = self._extract_pubmed_from_text(readme_text, source="README")
        citations.extend(pubmed_citations)

        # 6. Extract from GitHub metadata
        if github_metadata:
            if github_metadata.get('has_paper'):
                # Add placeholder for paper detection
                citations.append({
                    'type': 'paper',
                    'value': 'Paper detected in repository',
                    'source': 'GitHub metadata',
                    'url': github_metadata.get('url', '')
                })

        # Deduplicate and enrich
        citations = self._deduplicate_citations(citations)
        citations = self._enrich_citations(citations)

        return citations

    def _fetch_citation_cff(self, repo_full_name: str) -> Optional[str]:
        """Fetch CITATION.cff file from repository."""
        try:
            repo = self.github.get_repo(repo_full_name)

            # Try different locations
            for path in ['CITATION.cff', 'citation.cff', '.github/CITATION.cff']:
                try:
                    content_file = repo.get_contents(path)
                    return content_file.decoded_content.decode('utf-8')
                except:
                    continue

            return None
        except Exception:
            return None

    def _parse_citation_cff(self, cff_content: str) -> List[Dict]:
        """Parse CITATION.cff file."""
        citations = []

        try:
            data = yaml.safe_load(cff_content)

            # Main citation
            citation = {
                'type': 'citation_cff',
                'source': 'CITATION.cff'
            }

            if 'title' in data:
                citation['title'] = data['title']

            if 'authors' in data:
                authors = []
                for author in data['authors']:
                    if isinstance(author, dict):
                        name_parts = []
                        if 'given-names' in author:
                            name_parts.append(author['given-names'])
                        if 'family-names' in author:
                            name_parts.append(author['family-names'])
                        if name_parts:
                            authors.append(' '.join(name_parts))
                citation['authors'] = authors

            if 'doi' in data:
                citation['type'] = 'doi'
                citation['value'] = data['doi']
                citation['url'] = f"https://doi.org/{data['doi']}"

            if 'url' in data:
                citation['url'] = data['url']

            if 'date-released' in data:
                try:
                    citation['year'] = int(str(data['date-released'])[:4])
                except:
                    pass

            if 'journal' in data:
                citation['journal'] = data['journal']

            if citation.get('value') or citation.get('title'):
                citations.append(citation)

            # References section
            if 'references' in data:
                for ref in data['references']:
                    ref_citation = {'source': 'CITATION.cff (references)'}

                    if 'doi' in ref:
                        ref_citation['type'] = 'doi'
                        ref_citation['value'] = ref['doi']
                        ref_citation['url'] = f"https://doi.org/{ref['doi']}"

                    if 'title' in ref:
                        ref_citation['title'] = ref['title']

                    if ref_citation.get('value') or ref_citation.get('title'):
                        citations.append(ref_citation)

        except Exception as e:
            # Failed to parse, return empty
            pass

        return citations

    def _fetch_codemeta(self, repo_full_name: str) -> Optional[Dict]:
        """Fetch codemeta.json file from repository."""
        try:
            repo = self.github.get_repo(repo_full_name)
            content_file = repo.get_contents('codemeta.json')
            content = content_file.decoded_content.decode('utf-8')
            return json.loads(content)
        except Exception:
            return None

    def _parse_codemeta(self, codemeta: Dict) -> List[Dict]:
        """Parse codemeta.json for citations."""
        citations = []

        if 'citation' in codemeta:
            citation_data = codemeta['citation']
            if isinstance(citation_data, str):
                # Try to extract DOI from string
                doi_match = re.search(r'10\.\d{4,}/[^\s\)]+', citation_data)
                if doi_match:
                    citations.append({
                        'type': 'doi',
                        'value': doi_match.group(0),
                        'url': f"https://doi.org/{doi_match.group(0)}",
                        'source': 'codemeta.json'
                    })
            elif isinstance(citation_data, dict):
                citation = {'source': 'codemeta.json'}
                if '@id' in citation_data and citation_data['@id'].startswith('https://doi.org/'):
                    citation['type'] = 'doi'
                    citation['value'] = citation_data['@id'].replace('https://doi.org/', '')
                    citation['url'] = citation_data['@id']
                if 'name' in citation_data:
                    citation['title'] = citation_data['name']
                if citation.get('value'):
                    citations.append(citation)

        return citations

    def _extract_dois_from_text(self, text: str, source: str = "text") -> List[Dict]:
        """Extract DOI references from text."""
        citations = []

        # DOI pattern: 10.xxxx/xxxxx
        doi_pattern = r'(?:doi:?\s*|https?://(?:dx\.)?doi\.org/)?(10\.\d{4,}/[^\s\)\],]+)'

        matches = re.finditer(doi_pattern, text, re.IGNORECASE)
        for match in matches:
            doi = match.group(1)
            # Clean up DOI (remove trailing punctuation)
            doi = re.sub(r'[\.,;:\)\]]$', '', doi)

            citations.append({
                'type': 'doi',
                'value': doi,
                'url': f'https://doi.org/{doi}',
                'source': source
            })

        return citations

    def _extract_arxiv_from_text(self, text: str, source: str = "text") -> List[Dict]:
        """Extract arXiv references from text."""
        citations = []

        # arXiv pattern: arXiv:YYMM.NNNNN or arXiv:YYMM.NNNNNvX
        arxiv_pattern = r'arXiv:(\d{4}\.\d{4,5}(?:v\d+)?)'

        matches = re.finditer(arxiv_pattern, text, re.IGNORECASE)
        for match in matches:
            arxiv_id = match.group(1)

            citations.append({
                'type': 'arxiv',
                'value': arxiv_id,
                'url': f'https://arxiv.org/abs/{arxiv_id}',
                'source': source
            })

        return citations

    def _extract_pubmed_from_text(self, text: str, source: str = "text") -> List[Dict]:
        """Extract PubMed references from text."""
        citations = []

        # PubMed pattern: PMID: 12345678 or pubmed.ncbi.nlm.nih.gov/12345678
        pubmed_pattern = r'(?:PMID:?\s*|pubmed\.ncbi\.nlm\.nih\.gov/)(\d{7,8})'

        matches = re.finditer(pubmed_pattern, text, re.IGNORECASE)
        for match in matches:
            pmid = match.group(1)

            citations.append({
                'type': 'pubmed',
                'value': pmid,
                'url': f'https://pubmed.ncbi.nlm.nih.gov/{pmid}/',
                'source': source
            })

        return citations

    def _deduplicate_citations(self, citations: List[Dict]) -> List[Dict]:
        """Remove duplicate citations."""
        seen = set()
        unique = []

        for citation in citations:
            # Create key based on type and value
            key = f"{citation.get('type', 'unknown')}:{citation.get('value', '')}"
            if key not in seen:
                seen.add(key)
                unique.append(citation)

        return unique

    def _enrich_citations(self, citations: List[Dict]) -> List[Dict]:
        """Enrich citations with metadata from CrossRef API."""
        enriched = []

        for citation in citations:
            # Only enrich DOI citations
            if citation.get('type') == 'doi' and citation.get('value'):
                enriched_citation = self._enrich_doi_citation(citation)
                enriched.append(enriched_citation)
            else:
                enriched.append(citation)

        return enriched

    def _enrich_doi_citation(self, citation: Dict) -> Dict:
        """Enrich DOI citation with CrossRef metadata."""
        doi = citation.get('value', '')
        if not doi:
            return citation

        try:
            # Query CrossRef API (rate limit: 50 requests/second with polite pool)
            response = requests.get(
                f"{self.crossref_api}{doi}",
                headers={'User-Agent': 'GalaxyAutoUpdate/1.0 (mailto:biomate@example.com)'},
                timeout=5
            )

            if response.status_code == 200:
                data = response.json()
                message = data.get('message', {})

                # Add title
                if 'title' in message and message['title']:
                    citation['title'] = message['title'][0]

                # Add authors
                if 'author' in message:
                    authors = []
                    for author in message['author'][:3]:  # Limit to first 3
                        name_parts = []
                        if 'given' in author:
                            name_parts.append(author['given'])
                        if 'family' in author:
                            name_parts.append(author['family'])
                        if name_parts:
                            authors.append(' '.join(name_parts))
                    if authors:
                        citation['authors'] = authors

                # Add year
                if 'published' in message:
                    date_parts = message['published'].get('date-parts', [[]])
                    if date_parts and date_parts[0]:
                        citation['year'] = date_parts[0][0]

                # Add journal
                if 'container-title' in message and message['container-title']:
                    citation['journal'] = message['container-title'][0]

        except Exception:
            # Enrichment failed, return original citation
            pass

        return citation


# For command-line testing
if __name__ == '__main__':
    import sys

    if len(sys.argv) < 2:
        print("Usage: python citation_extractor.py <repo_full_name>")
        print("Example: python citation_extractor.py plotly/dash")
        sys.exit(1)

    repo_name = sys.argv[1]
    github_token = None  # Set via environment variable GITHUB_TOKEN

    import os
    if 'GITHUB_TOKEN' in os.environ:
        github_token = os.environ['GITHUB_TOKEN']

    extractor = CitationExtractor(github_token=github_token)

    # Fetch README
    if github_token:
        from github import Github, Auth
        auth = Auth.Token(github_token)
        g = Github(auth=auth)
        repo = g.get_repo(repo_name)
        readme = repo.get_readme().decoded_content.decode('utf-8')
    else:
        readme = ""

    citations = extractor.extract_citations(repo_name, readme)

    print(f"\nFound {len(citations)} citations for {repo_name}:\n")
    for i, citation in enumerate(citations, 1):
        print(f"{i}. {citation.get('type', 'unknown').upper()}")
        if 'title' in citation:
            print(f"   Title: {citation['title']}")
        if 'authors' in citation:
            print(f"   Authors: {', '.join(citation['authors'])}")
        if 'year' in citation:
            print(f"   Year: {citation['year']}")
        if 'journal' in citation:
            print(f"   Journal: {citation['journal']}")
        print(f"   URL: {citation.get('url', 'N/A')}")
        print(f"   Source: {citation.get('source', 'N/A')}")
        print()
