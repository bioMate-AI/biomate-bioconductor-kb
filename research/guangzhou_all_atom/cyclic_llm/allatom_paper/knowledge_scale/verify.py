"""K2 deterministic verification. A rule that fails any check is DISCARDED, never repaired."""
import hashlib, re, unicodedata
from config import (DIRECTIONS, PROPERTIES, SUBSTRUCTURES, QUOTE_MIN_WORDS, QUOTE_MAX_WORDS, TOPICS, LESSON_TYPES,
                    STRUCT_FEATURES, TARGETS)

REQUIRED = ["statement", "direction", "property", "substructure_class", "scope", "quote", "confidence"]


def norm(s: str) -> str:
    """Whitespace normalisation only (case-sensitive; no other edits)."""
    return " ".join((s or "").split())


def quote_in_text(quote: str, norm_text: str) -> bool:
    q = norm(quote)
    return bool(q) and q in norm_text


def quote_words(quote: str) -> int:
    return len(norm(quote).split())


def _num_strings(value):
    if value is None or value == "":
        return []
    s = str(value).strip().replace(",", "")
    out = {s}
    try:
        f = float(s)
        out.add(("%g" % f))
        if f == int(f):
            out.add(str(int(f)))
    except ValueError:
        pass
    return [x for x in out if x]


def number_ok(effect, quote: str, passage_norm: str) -> bool:
    """If an effect-size value is given its digits must occur in the quote or the source passage."""
    if not effect or effect.get("value") in (None, "", "null"):
        return True
    hay = (norm(quote) + " " + passage_norm).replace(",", "")
    return any(re.search(r"(?<![\d.])" + re.escape(n) + r"(?![\d])", hay) for n in _num_strings(effect.get("value")))


def schema_errors(rule: dict) -> list:
    errs = []
    for k in REQUIRED:
        if k not in rule or rule[k] in (None, ""):
            errs.append(f"missing:{k}")
    if rule.get("direction") not in DIRECTIONS:
        errs.append("bad_direction")
    if rule.get("property") not in PROPERTIES:
        errs.append("bad_property")
    if rule.get("substructure_class") not in SUBSTRUCTURES:
        errs.append("bad_substructure")
    st = rule.get("statement") or ""
    if not (5 <= len(st) <= 400):
        errs.append("statement_length")
    try:
        c = float(rule.get("confidence"))
        if not 0.0 <= c <= 1.0:
            errs.append("bad_confidence")
    except (TypeError, ValueError):
        errs.append("bad_confidence")
    return errs


def topic_errors(rule: dict, passage_norm: str) -> list:
    """Amendment A1: topic-specific required fields and deterministic grounding of residues / PDB ids in the passage."""
    errs, topic = [], rule.get("topic", "sar_rule")
    if topic not in TOPICS:
        return ["bad_topic"]
    if topic == "prior_work":
        if rule.get("lesson_type") not in LESSON_TYPES:
            errs.append("bad_lesson_type")
        if not norm(str(rule.get("designed_what") or "")):
            errs.append("missing:designed_what")
    if topic == "target_structure":
        if rule.get("target") not in TARGETS:
            errs.append("bad_target")
        if rule.get("structure_feature") not in STRUCT_FEATURES:
            errs.append("bad_structure_feature")
        for res in (rule.get("residues") or []):
            if not isinstance(res, str) or norm(res) not in passage_norm:
                errs.append("residue_not_in_passage")
                break
        pdb = norm(str(rule.get("pdb") or ""))
        if pdb and (not re.fullmatch(r"[0-9][A-Za-z0-9]{3}", pdb) or pdb not in passage_norm):
            errs.append("pdb_not_in_passage")
    return errs


def verify_rule(rule: dict, paper_norm_text: str, passage_norm: str) -> tuple:
    """Return (ok, reason). Order: schema, quote length, exact quote match, number sanity."""
    errs = schema_errors(rule)
    if errs:
        return False, "schema:" + ",".join(errs)
    nw = quote_words(rule["quote"])
    if not (QUOTE_MIN_WORDS <= nw <= QUOTE_MAX_WORDS):
        return False, f"quote_words:{nw}"
    if not quote_in_text(rule["quote"], paper_norm_text):
        return False, "quote_not_in_paper"
    if not number_ok(rule.get("effect_size"), rule["quote"], passage_norm):
        return False, "number_not_in_source"
    te = topic_errors(rule, passage_norm)
    if te:
        return False, "topic:" + ",".join(te)
    return True, "ok"


def rule_id(pmcid: str, quote: str, statement: str) -> str:
    return "K2-" + hashlib.sha1(f"{pmcid}|{norm(quote)}|{norm(statement)}".encode("utf-8")).hexdigest()[:12]


def _fold(x: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", x or "") if not unicodedata.combining(c)).lower()


def first_surname(author_string: str) -> str:
    first = (author_string or "").split(",")[0].strip()
    return _fold(first.split(" ")[0]) if first else ""


def benchmark_overlap(author_string: str, year, source_names) -> list:
    """CycPeptMPDB source strings like '2020_Townsend': match first-author surname and year (paper year or year+1)."""
    sn, hits = first_surname(author_string), []
    try:
        y = int(year)
    except (TypeError, ValueError):
        return hits
    for s in source_names:
        low = _fold(str(s))
        m = re.match(r"(\d{4})[_-]?(.*)", low) or re.match(r"(.*?)[_-]?(\d{4})$", low)
        if not m or not sn:
            continue
        digits = [g for g in m.groups() if g and g.isdigit()]
        if digits and int(digits[0]) in (y, y + 1) and sn in low:
            hits.append(s)
    return hits


STRICT_RELEVANCE_RE = re.compile(r"(cyclic|macrocycl|cyclo|cyclis|cyclis|lariat|stapl|disulfid|lactam|head-to-tail|peptid|RGD|N-methyl)", re.I)


def strict_ok(rule: dict) -> bool:
    """Amendment A5 (frozen before any precision judgement): STRICT arm = RAW verified AND all of:
    proxy_entailment == YES; confidence >= 0.7; relevance: quote+statement mentions a cyclic/peptide term;
    sar_rule must have a non-'other' property and direction in {increases, decreases, conditional}."""
    if rule.get("proxy_entailment") != "YES":
        return False
    try:
        if float(rule.get("confidence", 0)) < 0.7:
            return False
    except (TypeError, ValueError):
        return False
    if not STRICT_RELEVANCE_RE.search(norm(rule.get("quote", "")) + " " + norm(rule.get("statement", ""))):
        return False
    if rule.get("topic", "sar_rule") == "sar_rule":
        if rule.get("property") == "other" or rule.get("direction") not in ("increases", "decreases", "conditional"):
            return False
    return True
