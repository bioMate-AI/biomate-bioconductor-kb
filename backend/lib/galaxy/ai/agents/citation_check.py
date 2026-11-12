"""Citation existence check (gap T8).

Verifies that a cited PMID (NCBI E-utilities esummary) or DOI (Crossref)
exists and that the registry title matches the cited title.  Existence is NOT
support: a real paper that does not back the claim still passes here.

Statuses per citation
  verified               id exists and (if a title was cited) title matches
  not_found              id does not exist in the registry (fabricated/typo)
  title_mismatch         id exists but registry title differs from cited title
  unverified             network/registry error - could not check (never "verified")
  not_checked_offline    TARGET_ID_OFFLINE=1 or BIOMATE_OFFLINE=1
  no_identifier          citation carries neither PMID nor DOI

evidence_status over a set of citations
  grounded            >=1 usable citation and all of them verified
  partially_grounded  >=1 usable citation but some are not verified
  insufficient        no usable citation (none given, or all rejected)
"""
import difflib
import json
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Callable, Dict, List, Optional

TITLE_MATCH_THRESHOLD = 0.75  # max(difflib ratio, token Jaccard) on normalised titles
HTTP_TIMEOUT_S = 8.0
NCBI_MIN_INTERVAL_S = 0.4      # < 3 req/s without an API key
CROSSREF_MIN_INTERVAL_S = 0.15
USER_AGENT = "BioMate-citation-check/1.0 (mailto:support@biomate.ai)"

VERIFIED = "verified"
NOT_FOUND = "not_found"
TITLE_MISMATCH = "title_mismatch"
UNVERIFIED = "unverified"
NOT_CHECKED_OFFLINE = "not_checked_offline"
NO_IDENTIFIER = "no_identifier"
REJECTED = (NOT_FOUND, TITLE_MISMATCH)

LABELS = {
    VERIFIED: "verified",
    NOT_FOUND: "not found in registry",
    TITLE_MISMATCH: "exists but title does not match",
    UNVERIFIED: "unverified (could not check)",
    NOT_CHECKED_OFFLINE: "not checked (offline)",
    NO_IDENTIFIER: "no PMID/DOI to check",
}

# http_get(url, timeout) -> (status_code, parsed_json_or_None); raises on network failure.
HttpGet = Callable[[str, float], Any]

_cache: Dict[str, Dict[str, Any]] = {}
_lock = threading.Lock()
_last_call: Dict[str, float] = {}


def clear_cache() -> None:
    with _lock:
        _cache.clear()


def is_offline() -> bool:
    return any(os.environ.get(k, "").strip().lower() in ("1", "true", "yes")
               for k in ("TARGET_ID_OFFLINE", "BIOMATE_OFFLINE"))


def default_http_get(url: str, timeout: float = HTTP_TIMEOUT_S):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return 404, None
        raise


def _throttle(host: str, interval: float) -> None:
    with _lock:
        now = time.monotonic()
        wait = _last_call.get(host, 0.0) + interval - now
        _last_call[host] = now + max(wait, 0.0)
    if wait > 0:
        time.sleep(wait)


def _norm(t: str) -> List[str]:
    t = re.sub(r"<[^>]+>", " ", t or "").lower()
    return re.findall(r"[a-z0-9]+", t)


def title_similarity(a: str, b: str) -> float:
    ta, tb = _norm(a), _norm(b)
    if not ta or not tb:
        return 0.0
    ratio = difflib.SequenceMatcher(None, " ".join(ta), " ".join(tb)).ratio()
    sa, sb = set(ta), set(tb)
    return max(ratio, len(sa & sb) / float(len(sa | sb)))


def normalize_doi(doi: Optional[str]) -> str:
    d = (doi or "").strip()
    d = re.sub(r"^(https?://(dx\.)?doi\.org/|doi:\s*)", "", d, flags=re.I)
    return d.strip().rstrip(".,;)")


def normalize_pmid(pmid: Any) -> str:
    return re.sub(r"^pmid:?\s*", "", str(pmid or "").strip(), flags=re.I)


def _compare(cited_title: str, registry_title: str, threshold: float) -> Dict[str, Any]:
    if not (cited_title or "").strip():
        return {"status": VERIFIED, "registry_title": registry_title, "similarity": None,
                "note": "exists; no title supplied to compare"}
    sim = title_similarity(cited_title, registry_title)
    return {"status": VERIFIED if sim >= threshold else TITLE_MISMATCH,
            "registry_title": registry_title, "similarity": round(sim, 3)}


def _check_pmid(pmid: str, title: str, http_get: HttpGet, threshold: float) -> Dict[str, Any]:
    if not re.fullmatch(r"\d{1,9}", pmid):
        return {"status": NOT_FOUND, "note": "malformed PMID"}
    url = ("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&retmode=json&id="
           + pmid)
    _throttle("ncbi", NCBI_MIN_INTERVAL_S)
    status, data = http_get(url, HTTP_TIMEOUT_S)
    if status != 200 or not isinstance(data, dict):
        return {"status": UNVERIFIED, "note": "NCBI HTTP %s" % status}
    res = (data.get("result") or {})
    rec = res.get(pmid)
    if not isinstance(rec, dict) or rec.get("error") or not rec.get("title"):
        if data.get("error"):
            return {"status": UNVERIFIED, "note": "NCBI error: %s" % data.get("error")}
        return {"status": NOT_FOUND, "note": "PMID not in PubMed"}
    return _compare(title, rec["title"], threshold)


def _check_doi(doi: str, title: str, http_get: HttpGet, threshold: float) -> Dict[str, Any]:
    url = "https://api.crossref.org/works/" + urllib.parse.quote(doi, safe="/()")
    _throttle("crossref", CROSSREF_MIN_INTERVAL_S)
    status, data = http_get(url, HTTP_TIMEOUT_S)
    if status == 404:
        return {"status": NOT_FOUND, "note": "DOI not in Crossref"}
    if status != 200 or not isinstance(data, dict):
        return {"status": UNVERIFIED, "note": "Crossref HTTP %s" % status}
    titles = ((data.get("message") or {}).get("title")) or []
    reg = titles[0] if titles else ""
    if not reg:
        return {"status": VERIFIED, "registry_title": "", "similarity": None,
                "note": "DOI exists; Crossref has no title to compare"}
    return _compare(title, reg, threshold)


def _merge(parts: List[Dict[str, Any]]) -> Dict[str, Any]:
    for st in (NOT_FOUND, TITLE_MISMATCH):
        for p in parts:
            if p["status"] == st:
                return p
    for p in parts:
        if p["status"] == VERIFIED:
            return p
    return parts[0]


def verify_citation(citation: Any, http_get: Optional[HttpGet] = None,
                    threshold: float = TITLE_MATCH_THRESHOLD, offline: Optional[bool] = None) -> Dict[str, Any]:
    """Verify one citation (dict or object with pmid/doi/title). Never raises."""
    get = lambda k: (citation.get(k) if isinstance(citation, dict) else getattr(citation, k, None))
    pmid, doi, title = normalize_pmid(get("pmid")), normalize_doi(get("doi")), (get("title") or "")
    out = {"pmid": pmid or None, "doi": doi or None, "title": title}
    if not pmid and not doi:
        out.update(status=NO_IDENTIFIER)
    elif offline if offline is not None else is_offline():
        out.update(status=NOT_CHECKED_OFFLINE)
    else:
        key = "|".join([pmid, doi.lower(), " ".join(_norm(title)), str(threshold)])
        with _lock:
            hit = _cache.get(key)
        if hit is None:
            fn = http_get or default_http_get
            parts = []
            for kind, ident, chk in (("pmid", pmid, _check_pmid), ("doi", doi, _check_doi)):
                if not ident:
                    continue
                try:
                    p = chk(ident, title, fn, threshold)
                except Exception as e:  # network/parse failure -> fail soft, never "verified"
                    p = {"status": UNVERIFIED, "note": "%s check failed: %s" % (kind, type(e).__name__)}
                p["checked"] = kind
                parts.append(p)
            hit = _merge(parts)
            if hit["status"] != UNVERIFIED:  # do not cache transient failures
                with _lock:
                    _cache[key] = hit
        out.update(hit)
    out["label"] = LABELS[out["status"]]
    return out


def verify_citations(citations: List[Any], http_get: Optional[HttpGet] = None,
                     threshold: float = TITLE_MATCH_THRESHOLD, offline: Optional[bool] = None) -> List[Dict[str, Any]]:
    return [verify_citation(c, http_get, threshold, offline) for c in (citations or [])]


def evidence_status(results: List[Dict[str, Any]]) -> str:
    usable = [r for r in (results or []) if r["status"] not in REJECTED]
    if not usable:
        return "insufficient"
    return "grounded" if all(r["status"] == VERIFIED for r in usable) else "partially_grounded"


INSUFFICIENT_NOTICE = ("**Insufficient retrievable evidence:** no literature reference could be "
                       "grounded (retrieved and confirmed to exist) for this question, so no "
                       "bibliography is given. Treat any statement below as unreferenced "
                       "background, not literature-supported.")

# When no literature citations ground but the answer DOES draw on authoritative database
# records (resolved structures, variants, interactions, activities, with stable
# identifiers), the content is NOT "unreferenced background" — it is database-grounded.
DB_GROUNDED_NOTICE = ("**No literature citations could be grounded for this question, so no "
                      "bibliography is given.** The statements below are drawn from authoritative "
                      "biological databases (e.g. UniProt, PDBe, AlphaFold, ChEMBL, ClinVar, STRING, "
                      "Ensembl) — verifiable records with stable identifiers, not unreferenced claims.")

_REF_HEAD = re.compile(r"^\s*(#{1,6}\s*|\*\*)?(references?|bibliography|citations?|sources)\b.*$", re.I)
_ID_LINE = re.compile(r"(10\.\d{4,9}/\S+|\bpmid\b|\bdoi\b)", re.I)


def refuse_without_evidence(answer: str, db_grounded: bool = False) -> str:
    """Strip any invented bibliography (reference section, DOI/PMID lines, dangling [N]
    markers) and state plainly that no literature was grounded. When db_grounded, the
    answer rests on authoritative database records, so it is NOT 'unreferenced background'
    — use the database-grounded notice instead."""
    kept: List[str] = []
    for line in (answer or "").splitlines():
        if _REF_HEAD.match(line):
            break  # drop the reference section to the end
        if _ID_LINE.search(line):
            continue
        kept.append(re.sub(r"\s*\[\d+(?:\s*,\s*\d+)*\]", "", line))
    body = "\n".join(kept).strip()
    notice = DB_GROUNDED_NOTICE if db_grounded else INSUFFICIENT_NOTICE
    return notice + ("\n\n" + body if body else "")


def _renumber(answer: str, keep_old: List[int]) -> str:
    """Remap [N] markers after dropping citations: kept old numbers -> contiguous,
    dropped numbers removed from the marker."""
    remap = {old: i + 1 for i, old in enumerate(keep_old)}

    def repl(m):
        out = [str(remap[int(t)]) for t in re.split(r"\s*,\s*", m.group(1)) if t.isdigit() and int(t) in remap]
        return "[" + ", ".join(out) + "]" if out else ""

    return re.sub(r"\[(\d+(?:\s*,\s*\d+)*)\]", repl, answer)


def check_answer_citations(answer: str, citations: List[Any], http_get: Optional[HttpGet] = None,
                           threshold: float = TITLE_MATCH_THRESHOLD, offline: Optional[bool] = None,
                           n_numbered: Optional[int] = None, db_grounded: bool = False):
    """Verify citations, drop rejected ones, and derive evidence_status.

    The first n_numbered citations (default all) are the ones the answer cites
    as [1..n]; if any of them is rejected the markers are renumbered.
    Returns (answer, kept_citations, evidence_status, verification_rows).
    Dropped citations stay visible in verification_rows. When nothing usable
    remains the answer is rewritten via refuse_without_evidence.
    """
    cites = list(citations or [])
    rows = verify_citations(cites, http_get, threshold, offline)
    kept = [c for c, r in zip(cites, rows) if r["status"] not in REJECTED]
    status = evidence_status(rows)
    n = len(cites) if n_numbered is None else n_numbered
    if status == "insufficient":
        answer = refuse_without_evidence(answer, db_grounded=db_grounded)
    elif len(kept) < len(cites) and answer:
        keep_old = [i + 1 for i in range(n) if rows[i]["status"] not in REJECTED]
        dropped = sum(1 for r in rows if r["status"] in REJECTED)
        answer = _renumber(answer, keep_old).rstrip() + (
            "\n\n**Note:** %d cited reference%s removed because the PMID/DOI could not be "
            "confirmed in PubMed/Crossref." % (dropped, "" if dropped == 1 else "s"))
    return answer, kept, status, rows
