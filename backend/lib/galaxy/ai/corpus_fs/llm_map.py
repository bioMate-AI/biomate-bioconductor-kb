"""LLM per-document reading over a corpus_fs index, with a grounding check and a reviewer gate.

The technique behind Paperclip's ``map``/``reduce`` and the Virtual Biotech's trialist agents, self-hosted:
  worker   one LLM call per document: reads the stored sections, returns {answerable, answer, evidence[{section, quote}], confidence}
  verify   EVERY quote must be a (whitespace/case-normalised) substring of the stored section it cites; evidence that is not in the
           store is dropped, and an answer left with no verified quote becomes ``unsupported`` (never reported as an answer)
  review   optional second LLM call (the "scientific reviewer" gate) that accepts or rejects an answer given only its verified quotes
  reduce   deterministic aggregation (counts, answers with verified evidence); optional synthesis restricted to verified items, with
           any document id it mentions that is not among the inputs removed and reported.

``llm_client`` is duck-typed: ``llm_client.generate(prompt, **kw) -> str`` (the same contract as the target-ID LLM channel).
Python 3.9-safe, stdlib only. No network except through the injected client.
"""
from __future__ import annotations

import json
import re
from typing import Any, Callable, Dict, List, Optional

try:
    from .index import section_path
    from ..map_reduce import map_reduce
except ImportError:  # pragma: no cover
    from index import section_path  # type: ignore
    from map_reduce import map_reduce  # type: ignore

_WS = re.compile(r"\s+")
ID_RE = re.compile(r"\bNCT\d{8}\b|\bPMC\d{5,9}\b|\bPMID[: ]?\d{5,9}\b")


def _norm(s: str) -> str:
    return _WS.sub(" ", (s or "").lower()).strip()


def extract_json(text: str) -> Optional[Dict[str, Any]]:
    if not isinstance(text, str):
        return None
    start = text.find("{")
    while start != -1:
        depth = 0
        for i in range(start, len(text)):
            depth += (text[i] == "{") - (text[i] == "}")
            if depth == 0:
                try:
                    obj = json.loads(text[start:i + 1])
                    return obj if isinstance(obj, dict) else None
                except ValueError:
                    break
        start = text.find("{", start + 1)
    return None


def verify_evidence(index: Any, doc_id: str, evidence: Any) -> Dict[str, List[Dict[str, Any]]]:
    """Split claimed evidence into verified (quote found in the stored section) and rejected."""
    ok: List[Dict[str, Any]] = []
    bad: List[Dict[str, Any]] = []
    cache: Dict[str, str] = {}
    for ev in evidence if isinstance(evidence, list) else []:
        if not isinstance(ev, dict) or not isinstance(ev.get("quote"), str) or not isinstance(ev.get("section"), str):
            bad.append({"reason": "malformed", "evidence": ev})
            continue
        sec = ev["section"].strip()
        if sec not in cache:
            try:
                cache[sec] = _norm(index.cat(doc_id, section_path(doc_id, sec)))
            except Exception:
                cache[sec] = ""
        q = _norm(ev["quote"])
        if len(q) >= 8 and q in cache[sec]:
            ok.append({"section": sec, "quote": ev["quote"].strip(), "path": section_path(doc_id, sec)})
        else:
            bad.append({"reason": "quote_not_in_section", "section": sec, "quote": ev["quote"][:200]})
    return {"verified": ok, "rejected": bad}


def _prompt(question: str, doc_id: str, title: str, sections: Dict[str, str], max_chars: int) -> str:
    body, used = [], 0
    for name, text in sections.items():
        chunk = "### %s\n%s\n" % (name, text)
        if used + len(chunk) > max_chars:
            chunk = chunk[: max(0, max_chars - used)]
        body.append(chunk); used += len(chunk)
        if used >= max_chars:
            break
    return (
        "You read ONE document and answer a question using only its text.\n"
        "Question: %s\nDocument: %s  Title: %s\n\n%s\n"
        "Reply with ONE JSON object: {\"answerable\": true|false, \"answer\": \"short answer\", "
        "\"evidence\": [{\"section\": \"<section name above>\", \"quote\": \"<exact verbatim text from that section, 8+ chars>\"}], "
        "\"confidence\": 0..1}. If the document does not contain the answer set answerable=false and evidence=[]. "
        "Quotes must be copied exactly; do not paraphrase them." % (question, doc_id, title, "".join(body)))


def make_llm_doc_worker(index: Any, question: str, llm_client: Any, sections: Optional[List[str]] = None,
                        max_chars: int = 12000, review_fn: Optional[Callable[[str, Dict[str, Any]], Dict[str, Any]]] = None,
                        **gen_kwargs: Any) -> Callable[[str], Dict[str, Any]]:
    def worker(doc_id: str) -> Dict[str, Any]:
        names = sections or [p.split("/sections/")[1][:-len(".lines")] for p in index.ls(doc_id)]
        texts = {n: index.cat(doc_id, section_path(doc_id, n)) for n in names}
        texts = {n: t for n, t in texts.items() if t}
        meta = index.doc_meta(doc_id) or {}
        raw = llm_client.generate(_prompt(question, doc_id, meta.get("title") or "", texts, max_chars), **gen_kwargs)
        obj = extract_json(raw)
        if obj is None:
            return {"doc_id": doc_id, "status": "unparseable", "answer": None, "verified_evidence": [], "rejected_evidence": []}
        ev = verify_evidence(index, doc_id, obj.get("evidence"))
        answerable = bool(obj.get("answerable"))
        if not answerable:
            status = "not_answerable"
        elif ev["verified"]:
            status = "answered"
        else:
            status = "unsupported"       # the model claimed an answer but nothing it quoted exists in the document
        out = {"doc_id": doc_id, "status": status, "answer": obj.get("answer") if status == "answered" else None,
               "claimed_answer": obj.get("answer") if status == "unsupported" else None,
               "confidence": obj.get("confidence"), "verified_evidence": ev["verified"], "rejected_evidence": ev["rejected"]}
        if status == "answered" and review_fn is not None:
            verdict = review_fn(question, out) or {}
            out["review"] = verdict
            if verdict.get("verdict") == "reject":
                out["status"] = "rejected_by_reviewer"; out["answer"] = None
        return out
    return worker


def make_llm_reviewer(llm_client: Any, **gen_kwargs: Any) -> Callable[[str, Dict[str, Any]], Dict[str, Any]]:
    def review(question: str, result: Dict[str, Any]) -> Dict[str, Any]:
        quotes = "\n".join("- (%s) %s" % (e["section"], e["quote"]) for e in result["verified_evidence"])
        raw = llm_client.generate(
            "You are an independent scientific reviewer. Question: %s\nProposed answer: %s\nVerbatim evidence:\n%s\n"
            "Does the evidence, taken literally, support the answer? Reply ONE JSON object "
            "{\"verdict\": \"accept\"|\"reject\", \"reason\": \"one sentence\"}." % (question, result.get("answer"), quotes), **gen_kwargs)
        obj = extract_json(raw) or {}
        return {"verdict": "reject" if obj.get("verdict") == "reject" else "accept", "reason": obj.get("reason")}
    return review


def reduce_results(results: List[Dict[str, Any]]) -> Dict[str, Any]:
    by: Dict[str, int] = {}
    for r in results:
        by[r.get("status", "?")] = by.get(r.get("status", "?"), 0) + 1
    return {"n_docs": len(results), "by_status": by,
            "answers": [{"doc_id": r["doc_id"], "answer": r["answer"], "confidence": r.get("confidence"),
                         "evidence": r["verified_evidence"]} for r in results if r.get("status") == "answered"]}


def synthesize(question: str, reduced: Dict[str, Any], llm_client: Any, **gen_kwargs: Any) -> Dict[str, Any]:
    """Optional prose synthesis over verified answers only; ids it cites that are not among the inputs are removed and reported."""
    allowed = {a["doc_id"] for a in reduced.get("answers", [])}
    lines = "\n".join("[%s] %s | evidence: %s" % (a["doc_id"], a["answer"], " / ".join(e["quote"] for e in a["evidence"][:2]))
                      for a in reduced.get("answers", [])[:200])
    if not allowed:
        return {"text": "No document in the set contained a verified answer.", "unknown_ids_removed": []}
    text = llm_client.generate("Question: %s\nVerified per-document answers:\n%s\n\nWrite a concise synthesis. Cite document ids in "
                               "brackets exactly as given. Use only the answers above; add no outside facts." % (question, lines), **gen_kwargs)
    unknown = sorted({m for m in ID_RE.findall(text) if m not in allowed})
    for u in unknown:
        text = text.replace(u, "[unverified id removed]")
    return {"text": text, "unknown_ids_removed": unknown}


def llm_corpus_map(index: Any, question: str, doc_ids: List[str], llm_client: Any, with_reviewer: bool = True,
                   max_concurrent: int = 8, sections: Optional[List[str]] = None, **gen_kwargs: Any) -> Dict[str, Any]:
    worker = make_llm_doc_worker(index, question, llm_client, sections=sections,
                                 review_fn=make_llm_reviewer(llm_client, **gen_kwargs) if with_reviewer else None, **gen_kwargs)
    out = map_reduce(list(doc_ids), worker, reduce_fn=reduce_results, max_concurrent=max_concurrent)
    return out
