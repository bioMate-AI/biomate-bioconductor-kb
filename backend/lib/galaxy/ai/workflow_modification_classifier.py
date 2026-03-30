"""
WorkflowModificationClassifier — parses a user's chat message into a
structured WorkflowModification using Claude Haiku.

Handles:
  value_change  — "change padj to 0.01" / "set LFC threshold to 2"
  skip_step     — "skip deduplication" / "remove trimming" / "don't run STAR"
  add_workflow  — "then run pathway enrichment" / "add GSEA after step 2"
"""

import json
import os
import re
from typing import Optional

from .workflow_session import WorkflowModification

_CLASSIFIER_SYSTEM = """\
You are a bioinformatics workflow modification parser. Given a user's message,
output a single JSON object describing the modification they want to make.

Output schema:
{
  "type": "value_change" | "skip_step" | "add_workflow" | "none",
  "step_index": <int or null>,        // null = apply to most recent step
  "param_changes": {"param": value},  // for value_change only
  "skip_flags": ["skip_trimming"],    // for skip_step — use nf-core skip flag names
  "new_workflow_name": "...",         // for add_workflow
  "reasoning": "..."                 // brief explanation
}

Rules:
- "change X to Y", "set X = Y", "use X=Y"           → value_change, param_changes: {X: Y}
- "skip X", "remove X", "don't run X", "disable X"  → skip_step, skip_flags: [skip_X]
  Common nf-core skip flags: skip_trimming, skip_markduplicates, skip_multiqc,
  skip_qc, skip_alignment, skip_deduplication, skip_umi_extraction
- "then run X", "add X", "after step N do X"        → add_workflow, new_workflow_name: X
- Questions, greetings, data queries                 → none

Examples:
User: "change padj threshold to 0.01"
→ {"type":"value_change","step_index":null,"param_changes":{"padj_threshold":0.01},"skip_flags":[],"reasoning":"numeric param change"}

User: "skip the deduplication step"
→ {"type":"skip_step","step_index":null,"param_changes":{},"skip_flags":["skip_markduplicates"],"reasoning":"dedup = markduplicates in nf-core"}

User: "then run pathway enrichment"
→ {"type":"add_workflow","step_index":null,"param_changes":{},"skip_flags":[],"new_workflow_name":"GSEA pathway enrichment","reasoning":"sequential pipeline addition"}

User: "what genome should I use?"
→ {"type":"none","step_index":null,"param_changes":{},"skip_flags":[],"reasoning":"question, not a modification"}
"""


def classify_modification(message: str, current_workflow: Optional[str] = None) -> WorkflowModification:
    """
    Classify a user message as a workflow modification.
    Falls back to regex heuristics if the LLM call fails.
    """
    try:
        result = _classify_with_llm(message, current_workflow)
        return result
    except Exception:
        return _classify_with_regex(message)


def _classify_with_llm(message: str, current_workflow: Optional[str]) -> WorkflowModification:
    import anthropic
    client = anthropic.Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY", ""))
    context = f"\nCurrent workflow: {current_workflow}" if current_workflow else ""
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=256,
        system=_CLASSIFIER_SYSTEM,
        messages=[{"role": "user", "content": f"Message: {message!r}{context}"}],
    )
    text = response.content[0].text.strip()
    # Extract JSON from response
    m = re.search(r'\{.*\}', text, re.DOTALL)
    if not m:
        raise ValueError("No JSON in response")
    data = json.loads(m.group())
    return WorkflowModification(
        type=data.get("type", "none"),
        step_index=data.get("step_index"),
        param_changes=data.get("param_changes", {}),
        skip_flags=data.get("skip_flags", []),
        new_workflow_name=data.get("new_workflow_name"),
        raw_message=message,
    )


def _classify_with_regex(message: str) -> WorkflowModification:
    """Simple regex fallback."""
    msg = message.lower()

    # value_change: "change X to Y", "set X = Y", "use X=Y"
    m = re.search(r'(?:change|set|use)\s+(\w+)\s+(?:to|=)\s+(\S+)', msg)
    if m:
        return WorkflowModification(type="value_change",
                                    param_changes={m.group(1): m.group(2)},
                                    raw_message=message)

    # skip_step: strip common filler words (the, a, an, step) before the target noun
    _FILLERS = {"the", "a", "an", "step", "this", "that"}
    m = re.search(r"(?:skip|remove|disable|don't run)\s+((?:\w+\s+)*?)(\w+)(?:\s+step)?$", msg)
    if m:
        # m.group(2) is the last meaningful word; validate it isn't a filler
        candidate = m.group(2)
        if candidate in _FILLERS:
            # Fall back to scanning all words after the keyword
            keyword_end = m.start(1)
            words = [w for w in msg[keyword_end:].split() if w not in _FILLERS]
            candidate = words[0] if words else candidate
        flag = f"skip_{candidate}"
        return WorkflowModification(type="skip_step", skip_flags=[flag], raw_message=message)

    # add_workflow
    if any(kw in msg for kw in ["then run", "add ", "after step", "followed by"]):
        return WorkflowModification(type="add_workflow", raw_message=message)

    return WorkflowModification(type="none", raw_message=message)
