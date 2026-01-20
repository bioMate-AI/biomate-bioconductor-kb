#!/usr/bin/env python3
"""
New Tool Knowledge Collector

Collects comprehensive knowledge for new bioinformatics tools:
- Publications (DOI, PubMed)
- GitHub documentation
- Examples and tutorials
- Best practices

Usage:
    python collect_new_tool_knowledge.py
    python collect_new_tool_knowledge.py --tool evo2
"""

import argparse
import json
import logging
import os
import re
import sqlite3
import sys
import time
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
import requests

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Tool definitions with all metadata
NEW_TOOLS = {
    "state": {
        "name": "State",
        "full_name": "Arc Institute State Virtual Cell Model",
        "github": "ArcInstitute/state",
        "doi": None,  # bioRxiv - will fetch
        "biorxiv": "2025.06.26.661135",
        "description": "Virtual cell model predicting cellular perturbation responses using State Embedding (SE) and State Transition (ST) modules. Trained on 270M+ cells.",
        "category": "single-cell",
        "install": "uv tool install arc-state",
        "language": "Python",
        "topics": ["single-cell", "perturbation", "virtual-cell", "drug-response"]
    },
    "chai1": {
        "name": "Chai-1",
        "full_name": "Chai Discovery Chai-1",
        "github": "chaidiscovery/chai-lab",
        "doi": None,  # Technical report
        "description": "Multi-modal foundation model for molecular structure prediction. Predicts proteins, small molecules, DNA, RNA, glycosylations, and ligand complexes.",
        "category": "structure-prediction",
        "install": "pip install chai_lab",
        "language": "Python",
        "topics": ["protein-structure", "structure-prediction", "deep-learning", "alphafold-alternative"],
        "has_mcp": True
    },
    "boltz2": {
        "name": "Boltz-2",
        "full_name": "Boltz-2 Structure and Affinity Prediction",
        "github": "jwohlwend/boltz",
        "doi": None,
        "description": "Biomolecular foundation model for predicting structures of proteins, RNA, DNA, ligands, and binding affinities. MIT licensed, 1000x faster than FEP methods.",
        "category": "structure-prediction",
        "install": "pip install boltz",
        "language": "Python",
        "topics": ["protein-structure", "binding-affinity", "drug-discovery", "molecular-docking"],
        "has_mcp": True
    },
    "evo2": {
        "name": "Evo 2",
        "full_name": "Arc Institute Evo 2 DNA Foundation Model",
        "github": "ArcInstitute/evo2",
        "doi": None,
        "description": "40B parameter DNA foundation model trained on 9T nucleotides from 100K+ species. Supports 1M base pair context for genome-scale predictions.",
        "category": "genomics",
        "install": "pip install evo2",
        "language": "Python",
        "topics": ["genomics", "dna", "foundation-model", "mutation-prediction"],
        "api": "NVIDIA NIM"
    },
    "drugclip": {
        "name": "DrugCLIP",
        "full_name": "DrugCLIP Virtual Screening",
        "github": "bowen-gao/DrugCLIP",
        "doi": "10.1126/science.ads9530",
        "description": "Contrastive learning framework for virtual screening. 10 million times faster than traditional methods. Screened 10K proteins × 500M compounds.",
        "category": "drug-discovery",
        "install": "git clone + RDKit",
        "language": "Python",
        "topics": ["drug-discovery", "virtual-screening", "contrastive-learning", "deep-learning"]
    },
    "scfv_pmpnn_af2": {
        "name": "scFv_Pmpnn_AF2",
        "full_name": "AI-Assisted Intrabody Design Pipeline",
        "github": "jbderoo/scFv_Pmpnn_AF2",
        "doi": "10.1126/sciadv.adx8352",
        "description": "AI pipeline integrating AlphaFold2 and ProteinMPNN for converting antibodies to functional scFv intrabodies. 73% success rate vs 31% standard methods.",
        "category": "protein-design",
        "install": "git clone + dependencies",
        "language": "Python",
        "topics": ["protein-design", "antibody", "intrabody", "alphafold", "proteinmpnn"]
    },
    "protrek": {
        "name": "ProTrek",
        "full_name": "ProTrek Trimodal Protein Language Model",
        "github": "westlake-repl/ProTrek",
        "doi": "10.1038/s41587-025-02836-0",
        "description": "Trimodal protein language model unifying sequence, structure, and function. Enables advanced protein searches across 5B+ proteins.",
        "category": "protein-analysis",
        "install": "conda + HuggingFace",
        "language": "Python",
        "topics": ["protein-language-model", "protein-search", "embeddings", "trimodal"],
        "api": "search-protrek.com"
    },
    "profam1": {
        "name": "ProFam-1",
        "full_name": "ProFam-1 Protein Family Language Model",
        "github": "alex-hh/profam",
        "biorxiv": "2025.12.19.695431",
        "description": "251M parameter autoregressive protein family language model. State-of-the-art zero-shot fitness prediction on ProteinGym benchmark.",
        "category": "protein-analysis",
        "install": "git clone",
        "language": "Python",
        "topics": ["protein-language-model", "fitness-prediction", "protein-family", "autoregressive"]
    },
    "syncraft": {
        "name": "SynCraft",
        "full_name": "SynCraft Synthesizability Optimization",
        "github": "catalystforyou/SynCraft-Core",
        "arxiv": "2512.20333",
        "description": "LLM-guided framework for molecular synthesizability optimization. Uses Chain-of-Thought prompting with Gemini-2.5-Pro for atom-level edits.",
        "category": "drug-discovery",
        "install": "git clone",
        "language": "Python",
        "topics": ["drug-discovery", "synthesizability", "llm", "molecule-optimization"]
    },
    "alphafold3": {
        "name": "AlphaFold 3",
        "full_name": "Google DeepMind AlphaFold 3",
        "github": "google-deepmind/alphafold3",
        "doi": "10.1038/s41586-024-07487-w",
        "description": "Predicts structure of biomolecular complexes with proteins, DNA, RNA, ligands, ions. 50%+ improvement over AlphaFold 2.",
        "category": "structure-prediction",
        "install": "Docker",
        "language": "Python",
        "topics": ["protein-structure", "structure-prediction", "alphafold", "deep-learning"],
        "has_mcp": True,
        "license": "CC-BY-NC-SA 4.0"
    }
}


@dataclass
class Citation:
    """Structured citation data"""
    doi: Optional[str] = None
    pmid: Optional[str] = None
    title: Optional[str] = None
    authors: Optional[List[str]] = None
    journal: Optional[str] = None
    year: Optional[int] = None
    url: Optional[str] = None


@dataclass
class ToolKnowledge:
    """Complete tool knowledge structure"""
    tool_id: str
    name: str
    description: str
    category: str
    github_url: str
    primary_citation: Optional[Dict] = None
    benchmark_papers: Optional[List[Dict]] = None
    review_papers: Optional[List[Dict]] = None
    readme_content: Optional[str] = None
    help_text: Optional[str] = None
    usage_guide: Optional[str] = None
    examples: Optional[str] = None
    scientific_context: Optional[str] = None
    recommended_parameters: Optional[Dict] = None
    use_cases: Optional[List[str]] = None
    limitations: Optional[List[str]] = None
    alternatives: Optional[List[str]] = None
    install_instructions: Optional[str] = None
    dependencies: Optional[List[str]] = None
    hardware_requirements: Optional[str] = None
    topics: Optional[List[str]] = None
    language: Optional[str] = None
    has_mcp: bool = False
    api_available: Optional[str] = None
    license: Optional[str] = None
    last_updated: Optional[str] = None


class KnowledgeCollector:
    """Collects comprehensive knowledge for bioinformatics tools"""

    def __init__(self, github_token: Optional[str] = None):
        self.github_token = github_token or os.environ.get("GITHUB_TOKEN")
        self.session = requests.Session()
        if self.github_token:
            self.session.headers["Authorization"] = f"token {self.github_token}"
        self.session.headers["Accept"] = "application/vnd.github.v3+json"

    def fetch_github_readme(self, repo: str) -> Optional[str]:
        """Fetch README content from GitHub"""
        url = f"https://api.github.com/repos/{repo}/readme"
        try:
            response = self.session.get(url)
            if response.status_code == 200:
                data = response.json()
                import base64
                content = base64.b64decode(data["content"]).decode("utf-8")
                logger.info(f"Fetched README for {repo}")
                return content
            else:
                logger.warning(f"Failed to fetch README for {repo}: {response.status_code}")
        except Exception as e:
            logger.error(f"Error fetching README for {repo}: {e}")
        return None

    def fetch_github_repo_info(self, repo: str) -> Optional[Dict]:
        """Fetch repository metadata from GitHub"""
        url = f"https://api.github.com/repos/{repo}"
        try:
            response = self.session.get(url)
            if response.status_code == 200:
                data = response.json()
                return {
                    "stars": data.get("stargazers_count"),
                    "forks": data.get("forks_count"),
                    "description": data.get("description"),
                    "topics": data.get("topics", []),
                    "language": data.get("language"),
                    "license": data.get("license", {}).get("spdx_id") if data.get("license") else None,
                    "updated_at": data.get("updated_at"),
                    "homepage": data.get("homepage")
                }
        except Exception as e:
            logger.error(f"Error fetching repo info for {repo}: {e}")
        return None

    def fetch_doi_metadata(self, doi: str) -> Optional[Dict]:
        """Fetch publication metadata from CrossRef API"""
        url = f"https://api.crossref.org/works/{doi}"
        try:
            response = requests.get(url, timeout=10)
            if response.status_code == 200:
                data = response.json()["message"]
                authors = []
                for author in data.get("author", []):
                    name = f"{author.get('given', '')} {author.get('family', '')}".strip()
                    if name:
                        authors.append(name)
                return {
                    "doi": doi,
                    "title": data.get("title", [None])[0],
                    "authors": authors,
                    "journal": data.get("container-title", [None])[0],
                    "year": data.get("published", {}).get("date-parts", [[None]])[0][0],
                    "url": f"https://doi.org/{doi}"
                }
        except Exception as e:
            logger.error(f"Error fetching DOI metadata for {doi}: {e}")
        return None

    def fetch_pubmed_metadata(self, pmid: str) -> Optional[Dict]:
        """Fetch publication metadata from PubMed"""
        url = f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi"
        params = {
            "db": "pubmed",
            "id": pmid,
            "retmode": "json"
        }
        try:
            response = requests.get(url, params=params, timeout=10)
            if response.status_code == 200:
                data = response.json()
                result = data.get("result", {}).get(pmid, {})
                if result:
                    return {
                        "pmid": pmid,
                        "title": result.get("title"),
                        "authors": [a.get("name") for a in result.get("authors", [])],
                        "journal": result.get("fulljournalname"),
                        "year": int(result.get("pubdate", "0")[:4]) if result.get("pubdate") else None,
                        "doi": result.get("elocationid", "").replace("doi: ", "") if "doi:" in result.get("elocationid", "") else None
                    }
        except Exception as e:
            logger.error(f"Error fetching PubMed metadata for {pmid}: {e}")
        return None

    def extract_examples_from_readme(self, readme: str) -> Optional[str]:
        """Extract code examples from README"""
        examples = []
        # Find code blocks
        code_blocks = re.findall(r'```(?:python|bash|shell)?\n(.*?)```', readme, re.DOTALL)
        for block in code_blocks[:5]:  # Limit to first 5 examples
            if len(block.strip()) > 10:  # Skip trivial blocks
                examples.append(block.strip())
        return "\n\n---\n\n".join(examples) if examples else None

    def extract_installation_from_readme(self, readme: str) -> Optional[str]:
        """Extract installation instructions from README"""
        # Look for installation section
        install_patterns = [
            r'## Installation\n(.*?)(?=\n## |\Z)',
            r'### Installation\n(.*?)(?=\n### |\n## |\Z)',
            r'# Installation\n(.*?)(?=\n# |\Z)',
            r'## Setup\n(.*?)(?=\n## |\Z)',
            r'## Getting Started\n(.*?)(?=\n## |\Z)'
        ]
        for pattern in install_patterns:
            match = re.search(pattern, readme, re.DOTALL | re.IGNORECASE)
            if match:
                return match.group(1).strip()[:2000]  # Limit length
        return None

    def collect_tool_knowledge(self, tool_id: str, tool_config: Dict) -> ToolKnowledge:
        """Collect all knowledge for a single tool"""
        logger.info(f"Collecting knowledge for {tool_id}...")

        # Initialize knowledge
        knowledge = ToolKnowledge(
            tool_id=tool_id,
            name=tool_config["name"],
            description=tool_config["description"],
            category=tool_config["category"],
            github_url=f"https://github.com/{tool_config['github']}",
            topics=tool_config.get("topics", []),
            language=tool_config.get("language"),
            has_mcp=tool_config.get("has_mcp", False),
            api_available=tool_config.get("api"),
            license=tool_config.get("license"),
            last_updated=datetime.now().isoformat()
        )

        # Fetch GitHub README
        readme = self.fetch_github_readme(tool_config["github"])
        if readme:
            knowledge.readme_content = readme
            knowledge.examples = self.extract_examples_from_readme(readme)
            knowledge.install_instructions = self.extract_installation_from_readme(readme)

        # Fetch GitHub repo info
        repo_info = self.fetch_github_repo_info(tool_config["github"])
        if repo_info:
            if not knowledge.topics:
                knowledge.topics = repo_info.get("topics", [])
            if not knowledge.license:
                knowledge.license = repo_info.get("license")

        # Fetch publication metadata
        if tool_config.get("doi"):
            citation = self.fetch_doi_metadata(tool_config["doi"])
            if citation:
                knowledge.primary_citation = citation
                time.sleep(0.5)  # Rate limiting

        # Add manual scientific context
        knowledge.scientific_context = self._get_scientific_context(tool_id)
        knowledge.use_cases = self._get_use_cases(tool_id)
        knowledge.limitations = self._get_limitations(tool_id)
        knowledge.alternatives = self._get_alternatives(tool_id)

        return knowledge

    def _get_scientific_context(self, tool_id: str) -> str:
        """Get curated scientific context for each tool"""
        contexts = {
            "state": "State is Arc Institute's first virtual cell model designed for predicting cellular responses to perturbations. It uses two modules: State Embedding (SE) for converting transcriptomes to vector space, and State Transition (ST) for predicting responses. Trained on Tahoe-100M dataset with 100M perturbed cells.",
            "chai1": "Chai-1 is a multi-modal foundation model achieving state-of-the-art accuracy on protein structure prediction benchmarks. It unifies prediction of proteins, DNA, RNA, small molecules, and glycosylations in a single model.",
            "boltz2": "Boltz-2 jointly models biomolecular structures and binding affinities, approaching the accuracy of physics-based FEP methods while running 1000x faster. Fully open-source under MIT license, making it ideal for commercial drug discovery.",
            "evo2": "Evo 2 is a 40 billion parameter DNA foundation model capable of genome-scale predictions with single-nucleotide resolution. It can identify disease-causing mutations, design novel genomes, and analyze sequences across all domains of life.",
            "drugclip": "DrugCLIP reformulates virtual screening as a dense retrieval task using contrastive learning. It can screen millions of compounds against thousands of targets simultaneously, enabling genome-wide drug discovery.",
            "scfv_pmpnn_af2": "This pipeline integrates AI-driven protein design tools to convert antibody sequences into functional intrabodies. It achieved 73% success rate compared to 31% with standard methods, enabling creation of tools for studying chromatin dynamics.",
            "protrek": "ProTrek unifies protein sequence, structure, and function through contrastive learning, enabling searches between any two modalities. The web server provides access to 5B+ proteins from multiple databases.",
            "profam1": "ProFam-1 is trained on concatenated protein family sequences for next-token prediction. It achieves state-of-the-art fitness prediction without requiring multiple sequence alignments at inference time.",
            "syncraft": "SynCraft uses Chain-of-Thought prompting to guide LLMs in predicting atom-level molecular edits for synthesizability optimization. It navigates the 'synthesis cliff' where small modifications yield significant improvements.",
            "alphafold3": "AlphaFold 3 extends beyond proteins to predict structures of complexes containing DNA, RNA, ligands, and ions. The 2024 Nobel Prize in Chemistry recognized the foundational AlphaFold work."
        }
        return contexts.get(tool_id, "")

    def _get_use_cases(self, tool_id: str) -> List[str]:
        """Get curated use cases for each tool"""
        use_cases = {
            "state": ["Drug response prediction", "Perturbation analysis", "Cell state modeling", "Cancer drug screening"],
            "chai1": ["Protein structure prediction", "Protein-ligand complexes", "RNA structure", "Drug binding sites"],
            "boltz2": ["Protein-ligand docking", "Binding affinity prediction", "Drug discovery", "Lead optimization"],
            "evo2": ["Mutation effect prediction", "Genome design", "Cross-species analysis", "Variant pathogenicity"],
            "drugclip": ["Virtual screening", "Hit identification", "Target fishing", "Polypharmacology analysis"],
            "scfv_pmpnn_af2": ["Intrabody design", "scFv engineering", "Antibody humanization", "Chromatin imaging tools"],
            "protrek": ["Protein function search", "Structure similarity search", "Functional annotation", "Database mining"],
            "profam1": ["Fitness prediction", "Protein design", "Variant effect prediction", "Directed evolution"],
            "syncraft": ["Lead optimization", "Synthesizability improvement", "Retrosynthesis planning", "Drug-like property optimization"],
            "alphafold3": ["Complex structure prediction", "Protein-DNA interactions", "Drug binding", "Molecular mechanism studies"]
        }
        return use_cases.get(tool_id, [])

    def _get_limitations(self, tool_id: str) -> List[str]:
        """Get curated limitations for each tool"""
        limitations = {
            "state": ["Requires single-cell data format", "Cell context dependent", "Not for all cell types"],
            "chai1": ["Requires GPU (A100/H100 recommended)", "Limited to 1024 residues for proteins", "MSA generation optional but improves accuracy"],
            "boltz2": ["Requires GPU for inference", "Best for protein-small molecule complexes"],
            "evo2": ["40B parameters requires significant compute", "Best for DNA, not protein sequences"],
            "drugclip": ["Requires RDKit and UniMol", "Best for small molecule screening"],
            "scfv_pmpnn_af2": ["Requires ProteinMPNN and ColabFold", "Specific to antibody/scFv conversion"],
            "protrek": ["Web API for search, local for embeddings", "Structure search requires Foldseek format"],
            "profam1": ["Best for fitness prediction within families", "Requires family context"],
            "syncraft": ["Requires Gemini API access", "Focused on synthesizability, not activity"],
            "alphafold3": ["Non-commercial license", "No programmatic API (web only)", "Use Boltz-2 for commercial applications"]
        }
        return limitations.get(tool_id, [])

    def _get_alternatives(self, tool_id: str) -> List[str]:
        """Get alternative tools"""
        alternatives = {
            "state": ["scGPT", "Geneformer", "scFoundation"],
            "chai1": ["AlphaFold 3", "Boltz-2", "ESMFold", "RoseTTAFold"],
            "boltz2": ["AlphaFold 3", "Chai-1", "DiffDock"],
            "evo2": ["Nucleotide Transformer", "DNABERT-2", "HyenaDNA"],
            "drugclip": ["Glide", "AutoDock Vina", "GNINA"],
            "scfv_pmpnn_af2": ["RFdiffusion", "ProteinMPNN alone"],
            "protrek": ["ESM-2", "Foldseek", "MMseqs2"],
            "profam1": ["ESM-2", "ProtTrans", "Tranception"],
            "syncraft": ["REINVENT", "GuacaMol", "MOSES"],
            "alphafold3": ["Boltz-2 (MIT)", "Chai-1", "OpenFold"]
        }
        return alternatives.get(tool_id, [])

    def collect_all(self) -> Dict[str, ToolKnowledge]:
        """Collect knowledge for all tools"""
        results = {}
        for tool_id, tool_config in NEW_TOOLS.items():
            try:
                knowledge = self.collect_tool_knowledge(tool_id, tool_config)
                results[tool_id] = knowledge
                time.sleep(1)  # Rate limiting
            except Exception as e:
                logger.error(f"Error collecting knowledge for {tool_id}: {e}")
        return results

    def save_to_json(self, results: Dict[str, ToolKnowledge], output_path: Path):
        """Save results to JSON file"""
        output = {}
        for tool_id, knowledge in results.items():
            output[tool_id] = asdict(knowledge)

        with open(output_path, 'w') as f:
            json.dump(output, f, indent=2, default=str)
        logger.info(f"Saved knowledge to {output_path}")

    def save_to_database(self, results: Dict[str, ToolKnowledge], db_path: Path):
        """Save results to tool_knowledge table"""
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        for tool_id, knowledge in results.items():
            try:
                cursor.execute("""
                    INSERT OR REPLACE INTO tool_knowledge
                    (tool_name, tool_id, category, primary_citation, benchmark_papers,
                     review_papers, recommended_parameters, use_cases, limitations,
                     alternatives, last_updated)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    knowledge.name,
                    tool_id,
                    knowledge.category,
                    json.dumps(knowledge.primary_citation) if knowledge.primary_citation else None,
                    json.dumps(knowledge.benchmark_papers) if knowledge.benchmark_papers else None,
                    json.dumps(knowledge.review_papers) if knowledge.review_papers else None,
                    json.dumps(knowledge.recommended_parameters) if knowledge.recommended_parameters else None,
                    json.dumps(knowledge.use_cases) if knowledge.use_cases else None,
                    json.dumps(knowledge.limitations) if knowledge.limitations else None,
                    json.dumps(knowledge.alternatives) if knowledge.alternatives else None,
                    knowledge.last_updated
                ))
                logger.info(f"Saved {tool_id} to database")
            except Exception as e:
                logger.error(f"Error saving {tool_id} to database: {e}")

        conn.commit()
        conn.close()


def main():
    parser = argparse.ArgumentParser(description="Collect knowledge for new bioinformatics tools")
    parser.add_argument("--tool", type=str, help="Collect for specific tool only")
    parser.add_argument("--output", type=str, default="data/new_tools_knowledge.json", help="Output JSON path")
    parser.add_argument("--db", type=str, help="Path to galaxy_ai_tools.db for database storage")
    args = parser.parse_args()

    collector = KnowledgeCollector()

    if args.tool:
        if args.tool not in NEW_TOOLS:
            logger.error(f"Unknown tool: {args.tool}. Available: {list(NEW_TOOLS.keys())}")
            sys.exit(1)
        knowledge = collector.collect_tool_knowledge(args.tool, NEW_TOOLS[args.tool])
        results = {args.tool: knowledge}
    else:
        results = collector.collect_all()

    # Save to JSON
    script_dir = Path(__file__).parent.parent
    output_path = script_dir / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    collector.save_to_json(results, output_path)

    # Save to database if specified
    if args.db:
        collector.save_to_database(results, Path(args.db))

    # Print summary
    print(f"\n{'='*60}")
    print("Knowledge Collection Summary")
    print(f"{'='*60}")
    for tool_id, knowledge in results.items():
        has_citation = "✓" if knowledge.primary_citation else "✗"
        has_readme = "✓" if knowledge.readme_content else "✗"
        has_examples = "✓" if knowledge.examples else "✗"
        print(f"{tool_id:20} Citation: {has_citation}  README: {has_readme}  Examples: {has_examples}")
    print(f"\nOutput saved to: {output_path}")


if __name__ == "__main__":
    main()
