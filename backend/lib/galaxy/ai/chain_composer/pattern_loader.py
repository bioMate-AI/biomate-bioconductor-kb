r"""Parse the canonical chain-pattern library markdown into structured records.

The library lives at `docs/20260608_CHAIN_PATTERN_LIBRARY_DRAFT.md`. Each
pattern is a `## N. \`pattern_name\`` heading with bolded subsection labels
(**When**, **Shape**, **Instantiations**, **Pitfall**, **Reference**).

Patterns marked `⚠️ DEPRECATED FROM MAIN LIBRARY` in the heading are excluded
by default; pass `include_deprecated=True` to keep them.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional


@dataclass
class Pattern:
    """One canonical chain shape from the library."""
    name: str
    when: str
    shape: str
    instantiations: List[str] = field(default_factory=list)
    pitfall: str = ""
    reference: str = ""
    deprecated: bool = False

    def search_text(self) -> str:
        """Concatenation used by retrieval scoring."""
        return f"{self.name} {self.when} {self.pitfall}".lower()


# Repo-relative default. Lets us run from anywhere via env override.
_DEFAULT_LIBRARY = Path(
    os.environ.get(
        "BIOMATE_PATTERN_LIBRARY",
        Path(__file__).resolve().parents[5]
        / "docs"
        / "20260608_CHAIN_PATTERN_LIBRARY_DRAFT.md",
    )
)


# Heading shape: `## 1. \`sequential_omics_pipeline\``  (optional deprecation note)
_HEADING_RE = re.compile(
    r"^##\s+\d+\.\s+`(?P<name>[a-z0-9_]+)`(?P<rest>.*)$",
    re.MULTILINE,
)

# Pull out a bolded subsection until the next `**Label**:` or end-of-entry.
def _extract_field(body: str, label: str) -> str:
    pattern = re.compile(
        rf"\*\*{re.escape(label)}\*\*:?\s*(?P<value>.+?)(?=\n\*\*[A-Z][A-Za-z ]+\*\*:|$)",
        re.DOTALL,
    )
    m = pattern.search(body)
    return m.group("value").strip() if m else ""


def _split_instantiations(raw: str) -> List[str]:
    """Bullet list under **Real instantiations** → list of strings."""
    if not raw:
        return []
    lines = [ln.strip() for ln in raw.splitlines()]
    items = []
    for ln in lines:
        if ln.startswith("- "):
            items.append(ln[2:].strip())
        elif ln.startswith("* "):
            items.append(ln[2:].strip())
    return items or ([raw] if raw else [])


def load_patterns(
    path: Optional[Path] = None,
    include_deprecated: bool = False,
) -> List[Pattern]:
    """Parse the pattern library file into Pattern records.

    Args:
        path: override the library path. Defaults to the canonical doc
              (or `$BIOMATE_PATTERN_LIBRARY`).
        include_deprecated: include patterns marked `⚠️ DEPRECATED FROM MAIN LIBRARY`.

    Returns:
        List of Pattern objects in document order. Empty if file missing.
    """
    path = Path(path) if path else _DEFAULT_LIBRARY
    if not path.exists():
        return []

    text = path.read_text(encoding="utf-8")

    # Find all heading positions; carve the body between consecutive headings.
    headings = list(_HEADING_RE.finditer(text))
    patterns: List[Pattern] = []
    for i, m in enumerate(headings):
        body_start = m.end()
        body_end = headings[i + 1].start() if i + 1 < len(headings) else len(text)
        body = text[body_start:body_end]

        name = m.group("name")
        rest = m.group("rest") or ""
        deprecated = "DEPRECATED" in rest.upper()

        when = _extract_field(body, "When")
        shape = _extract_field(body, "Shape")
        # Trim shape's code-fence wrapping if present.
        shape = re.sub(r"^```\w*\s*|\s*```$", "", shape.strip(), flags=re.MULTILINE)
        instantiations = _split_instantiations(_extract_field(body, "Instantiations"))
        pitfall = _extract_field(body, "Pitfall")
        reference = _extract_field(body, "Reference")

        p = Pattern(
            name=name,
            when=when,
            shape=shape,
            instantiations=instantiations,
            pitfall=pitfall,
            reference=reference,
            deprecated=deprecated,
        )
        if deprecated and not include_deprecated:
            continue
        patterns.append(p)

    return patterns
