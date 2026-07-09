"""
skill_manager.py — Expert role Skills system for BioMate.

Skills are Markdown files with YAML frontmatter that inject deep domain expertise
into the AI assistant's system prompt. They are:
  - User-selectable (explicit activation per session or project)
  - Auto-detected from query triggers when not explicitly set
  - Composable (multiple active skills stack)
  - Shareable (plain .md files, committable to lab repos)

Usage:
    mgr = SkillManager()
    # Auto-detect from user message
    skills = mgr.detect_skills("run GWAS on UK Biobank data")
    # Or explicit
    skills = mgr.get_skills(["gwas-statistician", "ml-bioinformatics"])
    # Inject into system prompt
    block = mgr.build_system_block(skills)
"""

from __future__ import annotations

import json
import re
import logging
from pathlib import Path
from typing import Dict, List, Optional

log = logging.getLogger(__name__)

SKILLS_DIR = Path(__file__).parent / "skills"
BIOC_ROOT = Path(__file__).parents[4] / "bioconductor_skill"

# ── Frontmatter parsing ────────────────────────────────────────────────────────

def _parse_frontmatter(text: str) -> tuple[Dict, str]:
    """Split YAML frontmatter and body from a markdown skill file."""
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    fm_text = text[3:end].strip()
    body = text[end + 4:].strip()

    meta: Dict = {}
    for line in fm_text.splitlines():
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        key = key.strip()
        val = val.strip()
        # Parse list values: [a, b, c] or inline yaml list
        if val.startswith("[") and val.endswith("]"):
            items = [v.strip().strip("'\"") for v in val[1:-1].split(",")]
            meta[key] = [i for i in items if i]
        else:
            meta[key] = val.strip("'\"")
    return meta, body


# ── Skill data class ────────────────────────────────────────────────────────

class Skill:
    def __init__(self, path: Path):
        raw = path.read_text(encoding="utf-8")
        meta, body = _parse_frontmatter(raw)
        self.id: str = meta.get("name", path.stem)
        self.title: str = meta.get("title", self.id)
        self.triggers: List[str] = meta.get("triggers", [])
        self.domains: List[str] = meta.get("domains", [])
        self.version: str = meta.get("version", "1.0")
        self.body: str = body
        # Pre-compile trigger pattern for fast matching
        if self.triggers:
            pattern = "|".join(re.escape(t) for t in self.triggers)
            self._trigger_re = re.compile(pattern, re.IGNORECASE)
        else:
            self._trigger_re = None

    def matches_query(self, query: str) -> bool:
        if not self._trigger_re:
            return False
        return bool(self._trigger_re.search(query))

    def matches_domain(self, domains: List[str]) -> bool:
        return bool(set(self.domains) & set(domains))

    def to_dict(self) -> Dict:
        return {
            "id": self.id,
            "title": self.title,
            "triggers": self.triggers,
            "domains": self.domains,
            "domain": self.domains[0] if self.domains else "general",
            "version": self.version,
            "source": "expert",
            "description": "",
        }

    def system_block(self) -> str:
        return f"<skill id=\"{self.id}\" title=\"{self.title}\">\n{self.body}\n</skill>"


# ── Bioconductor skill ────────────────────────────────────────────────────────

class BiocSkill:
    """
    Wraps a Bioconductor package SKILL.md with the same interface as Skill.
    Bioconductor frontmatter uses: name, description, when_to_use, user-invocable.
    The package name (from MANIFEST) becomes the primary trigger.
    """

    def __init__(self, pkg_name: str, domain: str, path: Path, score: int = 0):
        self.id: str = f"bioconductor-{pkg_name.lower().replace(' ', '-')}"
        self.title: str = pkg_name
        self.domain: str = domain          # singular domain from MANIFEST
        self.domains: List[str] = [domain] # list form for compat with Skill
        self.version: str = "bioconductor"
        self.source: str = "bioconductor"
        self.score: int = score
        self.description: str = ""
        self.when_to_use: str = ""
        self.body: str = ""

        # Triggers: package name exact + lowercased
        base_trigger = pkg_name.lower()
        self.triggers: List[str] = list({base_trigger, pkg_name})

        if path.exists():
            raw = path.read_text(encoding="utf-8")
            meta, self.body = _parse_frontmatter(raw)
            self.description = meta.get("description", "")
            self.when_to_use = meta.get("when_to_use", "")
            # Add when_to_use keywords as additional soft triggers
            if self.when_to_use:
                self.triggers = list(set(self.triggers))

        # Compile trigger regex
        if self.triggers:
            pattern = "|".join(re.escape(t) for t in self.triggers)
            self._trigger_re = re.compile(pattern, re.IGNORECASE)
        else:
            self._trigger_re = None

    def matches_query(self, query: str) -> bool:
        if not self._trigger_re:
            return False
        return bool(self._trigger_re.search(query))

    def matches_domain(self, domains: List[str]) -> bool:
        return self.domain in domains

    def to_dict(self) -> Dict:
        return {
            "id": self.id,
            "title": self.title,
            "triggers": self.triggers[:3],  # keep compact for API
            "domains": self.domains,
            "domain": self.domain,
            "version": self.version,
            "source": self.source,
            "description": self.description[:200] if self.description else "",
            "when_to_use": self.when_to_use[:300] if self.when_to_use else "",
            "score": self.score,
        }

    def system_block(self) -> str:
        return f"<skill id=\"{self.id}\" title=\"{self.title}\">\n{self.body}\n</skill>"


def _load_bioconductor_skills(bioc_root: Path = BIOC_ROOT) -> List[BiocSkill]:
    """Load all Bioconductor skills from the MANIFEST.json index."""
    manifest_path = bioc_root / "MANIFEST.json"
    if not manifest_path.exists():
        log.warning("[BiocSkills] MANIFEST.json not found at %s", manifest_path)
        return []

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except Exception as e:
        log.warning("[BiocSkills] Failed to parse MANIFEST.json: %s", e)
        return []

    skills: List[BiocSkill] = []
    for pkg in manifest.get("packages", []):
        try:
            name = pkg["name"]
            domain = pkg.get("domain", "general")
            score = pkg.get("score", 0)
            rel_path = pkg.get("path", "")
            abs_path = bioc_root / rel_path
            skill = BiocSkill(name, domain, abs_path, score)
            skills.append(skill)
        except Exception as e:
            log.debug("[BiocSkills] Skipped %s: %s", pkg.get("name", "?"), e)

    log.info("[BiocSkills] Loaded %d Bioconductor skills", len(skills))
    return skills


# ── Manager ─────────────────────────────────────────────────────────────────

class SkillManager:
    """Loads expert skills (.md) and Bioconductor skills (MANIFEST.json)."""

    def __init__(self, skills_dir: Path = SKILLS_DIR, bioc_root: Path = BIOC_ROOT):
        self._skills: Dict[str, Skill] = {}       # expert hand-written skills
        self._bioc: Dict[str, BiocSkill] = {}      # Bioconductor package skills
        self._load(skills_dir)
        self._load_bioc(bioc_root)

    def _load(self, directory: Path) -> None:
        if not directory.exists():
            log.warning("[SkillManager] skills dir not found: %s", directory)
            return
        for path in sorted(directory.glob("*.md")):
            try:
                skill = Skill(path)
                self._skills[skill.id] = skill
                log.debug("[SkillManager] loaded skill: %s (%d triggers)", skill.id, len(skill.triggers))
            except Exception as e:
                log.warning("[SkillManager] failed to load %s: %s", path.name, e)
        log.info("[SkillManager] loaded %d expert skills", len(self._skills))

    def _load_bioc(self, bioc_root: Path) -> None:
        for skill in _load_bioconductor_skills(bioc_root):
            self._bioc[skill.id] = skill

    def _all_skills(self):
        """Unified view: expert skills first, then Bioconductor."""
        return {**self._skills, **self._bioc}

    def list_skills(self) -> List[Dict]:
        """Return metadata for all available skills (for API listing)."""
        return [s.to_dict() for s in self._skills.values()] + \
               [s.to_dict() for s in self._bioc.values()]

    def list_expert_skills(self) -> List[Dict]:
        return [s.to_dict() for s in self._skills.values()]

    def list_bioc_skills(self, domain: Optional[str] = None) -> List[Dict]:
        skills = self._bioc.values()
        if domain:
            skills = [s for s in skills if s.domain == domain]
        return [s.to_dict() for s in sorted(skills, key=lambda s: -s.score)]

    def list_bioc_domains(self) -> List[str]:
        return sorted(set(s.domain for s in self._bioc.values()))

    def get_skill(self, skill_id: str):
        return self._all_skills().get(skill_id)

    def get_skills(self, skill_ids: List[str]) -> list:
        all_s = self._all_skills()
        return [all_s[sid] for sid in skill_ids if sid in all_s]

    def detect_skills(
        self,
        query: str,
        preferred_domains: Optional[List[str]] = None,
        max_skills: int = 3,
    ) -> list:
        """
        Auto-detect relevant skills from a user query and/or preferred domains.
        Expert skills rank higher than Bioconductor skills (2× weight multiplier).
        Returns up to max_skills skills, ranked by trigger match count.
        """
        scores: Dict[str, int] = {}

        # Expert skills — higher weight
        for skill in self._skills.values():
            score = 0
            if skill.matches_query(query):
                if skill._trigger_re:
                    score += len(skill._trigger_re.findall(query)) * 4
            if preferred_domains and skill.matches_domain(preferred_domains):
                score += 2
            if score > 0:
                scores[skill.id] = score

        # Bioconductor skills — exact package name match
        for skill in self._bioc.values():
            if skill.matches_query(query):
                score = 2  # flat score for exact package name hit
                if preferred_domains and skill.matches_domain(preferred_domains):
                    score += 1
                scores[skill.id] = score

        all_s = self._all_skills()
        ranked = sorted(scores, key=lambda k: scores[k], reverse=True)
        return [all_s[sid] for sid in ranked[:max_skills]]

    def build_system_block(self, skills: list) -> str:
        if not skills:
            return ""
        blocks = "\n\n".join(s.system_block() for s in skills)
        return f"<active_skills>\n{blocks}\n</active_skills>\n"

    def build_system_block_by_ids(self, skill_ids: List[str]) -> str:
        return self.build_system_block(self.get_skills(skill_ids))

    def build_system_block_auto(
        self,
        query: str,
        preferred_domains: Optional[List[str]] = None,
    ) -> str:
        detected = self.detect_skills(query, preferred_domains)
        if detected:
            log.info("[SkillManager] auto-detected skills: %s", [s.id for s in detected])
        return self.build_system_block(detected)


# ── Module-level singleton ────────────────────────────────────────────────────

_manager: Optional[SkillManager] = None

def get_skill_manager() -> SkillManager:
    global _manager
    if _manager is None:
        _manager = SkillManager()
    return _manager
