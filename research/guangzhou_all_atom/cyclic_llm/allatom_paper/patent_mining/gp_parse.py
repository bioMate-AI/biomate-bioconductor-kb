"""Parse a Google Patents /patent/<number>/en HTML page into a dict (title, abstract, dates, assignee, CPC, claims, description).
Pure parsing (no network). Fields that are not found are None / []; the caller records parse coverage."""
import re
from html import unescape

def _t(html):
    return re.sub(r"\s+", " ", unescape(re.sub(r"<[^>]+>", " ", html))).strip()

def parse(html: str) -> dict:
    out = {"title": None, "abstract": None, "pub_date": None, "filing_date": None, "assignee": None, "inventors": [],
           "cpc": [], "claims": None, "description": None, "kind": None}
    m = re.search(r'<meta name="DC.title" content="([^"]*)"', html)
    out["title"] = _t(m.group(1)) if m else None
    if out["title"] is None:
        m = re.search(r"<title>(.*?)</title>", html, re.S)
        out["title"] = _t(m.group(1)) if m else None
    m = re.search(r'<meta name="description" content="(.*?)">', html, re.S)
    out["abstract"] = _t(m.group(1)) if m else None
    for key, pat in (("pub_date", r'<meta name="DC.date" content="([^"]*)" scheme="issue"'),
                     ("filing_date", r'<meta name="DC.date" content="([^"]*)" scheme="dateSubmitted"')):
        m = re.search(pat, html)
        out[key] = m.group(1) if m else None
    out["inventors"] = [unescape(x) for x in re.findall(r'<meta name="DC.contributor" content="([^"]*)" scheme="inventor"', html)]
    ma = re.search(r'itemprop="assigneeOriginal"[^>]*>(.*?)</dd>', html, re.S) or re.search(r'itemprop="assigneeCurrent"[^>]*>(.*?)</dd>', html, re.S)
    if ma:
        out["assignee"] = _t(ma.group(1))
    else:
        m = re.search(r'<meta name="DC.contributor" content="([^"]*)" scheme="assignee"', html)
        out["assignee"] = unescape(m.group(1)) if m else None
    out["cpc"] = sorted({re.sub(r"\s+", "", c) for c in re.findall(r'<span itemprop="Code">([^<]+)</span>', html)})
    mc = re.search(r'<section itemprop="claims"[^>]*>(.*?)</section>', html, re.S)
    out["claims"] = _t(mc.group(1)) if mc else None
    md = re.search(r'<section itemprop="description"[^>]*>(.*?)</section>', html, re.S)
    out["description"] = _t(md.group(1)) if md else None
    m = re.search(r"/patent/([A-Z]{2}\d+[A-Z]\d?)", html)
    out["kind"] = m.group(1)[-2:] if m else None
    return out

def coverage(d: dict) -> dict:
    return {k: bool(d.get(k)) for k in ("title", "abstract", "pub_date", "assignee", "cpc", "claims", "description")}
