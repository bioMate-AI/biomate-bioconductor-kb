"""
SkillLoader - Dynamic loader for claude-scientific-skills

Loads skill prompts from the claude-scientific-skills repository to guide
Claude's responses for different task types.

Skills are structured markdown documents that provide:
- Workflow steps
- Reference materials
- Templates and examples
- Best practices
"""

import os
import logging
from pathlib import Path
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field
from functools import lru_cache
import yaml

log = logging.getLogger(__name__)


@dataclass
class SkillMetadata:
    """Metadata parsed from skill YAML frontmatter."""
    name: str
    description: str
    path: str


@dataclass
class LoadedSkill:
    """A loaded skill with content and metadata."""
    name: str
    description: str
    content: str
    path: str
    references: List[str] = field(default_factory=list)


class SkillLoader:
    """
    Loads claude-scientific-skills dynamically based on task type.

    Skills are prompt documents that guide Claude's responses.
    This loader manages loading, caching, and combining skills.
    """

    # Default path to skills repository
    DEFAULT_SKILLS_PATH = "/home/yzhang/biomate/research_repos/claude-scientific-skills-biomate"

    # Map intent types to relevant skills
    INTENT_TO_SKILLS: Dict[str, List[str]] = {
        "research_question": [
            "scientific-thinking/hypothesis-generation",
            "scientific-databases/pubmed-database"
        ],
        "result_comparison": [
            "scientific-thinking/peer-review",
            "scientific-databases/pubmed-database"
        ],
        "conclusion_drawing": [
            "scientific-thinking/exploratory-data-analysis",
            "scientific-thinking/scientific-critical-thinking"
        ],
        "literature_survey": [
            "scientific-databases/pubmed-database",
            "scientific-thinking/scientific-writing"
        ],
        "hypothesis_generation": [
            "scientific-thinking/hypothesis-generation",
            "scientific-thinking/scientific-brainstorming"
        ],
        "statistical_analysis": [
            "scientific-thinking/statistical-analysis",
            "scientific-thinking/exploratory-data-analysis"
        ],
        "visualization": [
            "scientific-thinking/scientific-visualization"
        ],
        "data_analysis": [
            "scientific-thinking/exploratory-data-analysis",
            "scientific-thinking/statistical-analysis"
        ]
    }

    # Domain-specific skill mappings
    DOMAIN_TO_SKILLS: Dict[str, List[str]] = {
        "genomics": [
            "scientific-databases/ensembl-database",
            "scientific-databases/gene-database",
            "scientific-packages/biopython"
        ],
        "transcriptomics": [
            "scientific-databases/geo-database",
            "scientific-packages/scanpy",
            "scientific-packages/pydeseq2"
        ],
        "proteomics": [
            "scientific-databases/uniprot-database",
            "scientific-databases/pdb-database",
            "scientific-databases/alphafold-database"
        ],
        "pharmacology": [
            "scientific-databases/chembl-database",
            "scientific-databases/pubchem-database",
            "scientific-databases/fda-database"
        ],
        "clinical": [
            "scientific-databases/clinvar-database",
            "scientific-databases/clinicaltrials-database",
            "scientific-databases/opentargets-database"
        ],
        "metabolomics": [
            "scientific-databases/hmdb-database",
            "scientific-databases/kegg-database",
            "scientific-databases/metabolomics-workbench-database"
        ],
        "structural_biology": [
            "scientific-databases/pdb-database",
            "scientific-databases/alphafold-database",
            "scientific-packages/rdkit"
        ]
    }

    def __init__(self, skills_path: Optional[str] = None):
        """
        Initialize SkillLoader.

        Args:
            skills_path: Path to claude-scientific-skills repository.
                        Defaults to DEFAULT_SKILLS_PATH.
        """
        self.skills_path = Path(skills_path or self.DEFAULT_SKILLS_PATH)
        self._skill_cache: Dict[str, LoadedSkill] = {}

        if not self.skills_path.exists():
            log.warning(f"Skills path does not exist: {self.skills_path}")

    def _parse_frontmatter(self, content: str) -> tuple[Dict[str, Any], str]:
        """Parse YAML frontmatter from skill content."""
        if not content.startswith('---'):
            return {}, content

        try:
            # Find end of frontmatter
            end_idx = content.find('---', 3)
            if end_idx == -1:
                return {}, content

            frontmatter_str = content[3:end_idx].strip()
            body = content[end_idx + 3:].strip()

            frontmatter = yaml.safe_load(frontmatter_str) or {}
            return frontmatter, body
        except yaml.YAMLError as e:
            log.warning(f"Failed to parse frontmatter: {e}")
            return {}, content

    def _load_skill_file(self, skill_path: str) -> Optional[LoadedSkill]:
        """Load a single skill file."""
        if skill_path in self._skill_cache:
            return self._skill_cache[skill_path]

        full_path = self.skills_path / skill_path / "SKILL.md"

        if not full_path.exists():
            log.warning(f"Skill file not found: {full_path}")
            return None

        try:
            content = full_path.read_text(encoding='utf-8')
            frontmatter, body = self._parse_frontmatter(content)

            # Load references if they exist
            references = []
            refs_path = self.skills_path / skill_path / "references"
            if refs_path.exists():
                for ref_file in refs_path.glob("*.md"):
                    try:
                        ref_content = ref_file.read_text(encoding='utf-8')
                        references.append(f"## Reference: {ref_file.stem}\n{ref_content}")
                    except Exception as e:
                        log.warning(f"Failed to load reference {ref_file}: {e}")

            skill = LoadedSkill(
                name=frontmatter.get('name', skill_path.split('/')[-1]),
                description=frontmatter.get('description', ''),
                content=body,
                path=skill_path,
                references=references
            )

            self._skill_cache[skill_path] = skill
            return skill

        except Exception as e:
            log.error(f"Failed to load skill {skill_path}: {e}")
            return None

    def load_skills_for_intent(
        self,
        intent: str,
        include_references: bool = False,
        max_tokens: int = 8000
    ) -> str:
        """
        Load skill prompts for the given intent type.

        Args:
            intent: Intent type (research_question, result_comparison, etc.)
            include_references: Whether to include reference materials
            max_tokens: Approximate max tokens to include

        Returns:
            Combined skill prompt text
        """
        skill_paths = self.INTENT_TO_SKILLS.get(intent, [])

        if not skill_paths:
            log.warning(f"No skills mapped for intent: {intent}")
            return ""

        return self._combine_skills(skill_paths, include_references, max_tokens)

    def load_skills_for_domain(
        self,
        domain: str,
        include_references: bool = False,
        max_tokens: int = 8000
    ) -> str:
        """
        Load skill prompts for a specific domain.

        Args:
            domain: Domain name (genomics, proteomics, etc.)
            include_references: Whether to include reference materials
            max_tokens: Approximate max tokens to include

        Returns:
            Combined skill prompt text
        """
        skill_paths = self.DOMAIN_TO_SKILLS.get(domain, [])

        if not skill_paths:
            log.warning(f"No skills mapped for domain: {domain}")
            return ""

        return self._combine_skills(skill_paths, include_references, max_tokens)

    def load_specific_skills(
        self,
        skill_paths: List[str],
        include_references: bool = False,
        max_tokens: int = 8000
    ) -> str:
        """
        Load specific skills by path.

        Args:
            skill_paths: List of skill paths (e.g., ["scientific-thinking/hypothesis-generation"])
            include_references: Whether to include reference materials
            max_tokens: Approximate max tokens to include

        Returns:
            Combined skill prompt text
        """
        return self._combine_skills(skill_paths, include_references, max_tokens)

    def _combine_skills(
        self,
        skill_paths: List[str],
        include_references: bool,
        max_tokens: int
    ) -> str:
        """Combine multiple skills into a single prompt."""
        combined_prompt = ""
        approx_tokens = 0

        for skill_path in skill_paths:
            skill = self._load_skill_file(skill_path)
            if not skill:
                continue

            # Add skill content
            skill_text = f"\n## {skill.name.upper()} SKILL\n\n{skill.content}\n"

            # Estimate tokens (rough: 1 token ≈ 4 chars)
            skill_tokens = len(skill_text) // 4

            if approx_tokens + skill_tokens > max_tokens:
                log.warning(f"Skipping skill {skill_path} due to token limit")
                break

            combined_prompt += skill_text
            approx_tokens += skill_tokens

            # Add references if requested
            if include_references and skill.references:
                for ref in skill.references:
                    ref_tokens = len(ref) // 4
                    if approx_tokens + ref_tokens > max_tokens:
                        break
                    combined_prompt += f"\n{ref}\n"
                    approx_tokens += ref_tokens

        return combined_prompt

    def get_available_skills(self) -> List[SkillMetadata]:
        """Get list of all available skills."""
        skills = []

        # Search all SKILL.md files
        for skill_file in self.skills_path.rglob("SKILL.md"):
            try:
                content = skill_file.read_text(encoding='utf-8')
                frontmatter, _ = self._parse_frontmatter(content)

                # Get relative path
                rel_path = skill_file.parent.relative_to(self.skills_path)

                skills.append(SkillMetadata(
                    name=frontmatter.get('name', skill_file.parent.name),
                    description=frontmatter.get('description', ''),
                    path=str(rel_path)
                ))
            except Exception as e:
                log.warning(f"Failed to read skill metadata from {skill_file}: {e}")

        return skills

    def get_skill_categories(self) -> Dict[str, List[str]]:
        """Get skills organized by category."""
        categories: Dict[str, List[str]] = {}

        for skill in self.get_available_skills():
            parts = skill.path.split('/')
            if len(parts) >= 2:
                category = parts[0]
                if category not in categories:
                    categories[category] = []
                categories[category].append(skill.path)

        return categories


# Factory function
def create_skill_loader(skills_path: Optional[str] = None) -> SkillLoader:
    """Create a SkillLoader instance."""
    return SkillLoader(skills_path)
