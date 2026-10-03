"""Filter pmc_fulltext_bulk -> modern biomedical concept VOLUME for background CPT.
Reads jsonl on stdin (stream from S3), writes filtered jsonl to stdout. Keeps: year >= MINYEAR,
article-type in {research/review/original/systematic}, licence in {CC-BY, public-domain} (commercial-
clean; --allow-nc to include NC for on-prem). Strips the repeated JOURNAL/ARTICLE metadata boilerplate
(keep from 'Abstract'/body). Tags reviews as pmc_review (for up-weighting). Stats to stderr.

  aws s3 cp s3://.../pmc_fulltext_bulk.jsonl - | python3 pmc_filter.py --min-year 2000 > pmc_concept.jsonl
"""
import sys, json, re, argparse, collections

YEAR = re.compile(r"publication date:\s*(\d{4})")
SUBJ = re.compile(r"Subjects?:\s*([^\n]{0,80})", re.I)
LIC = re.compile(r"creativecommons\.org/licenses/([a-z-]+)")
PD = re.compile(r"publicdomain", re.I)
EQRUN = re.compile(r"={10,}")
DROP_TYPES = ("editorial", "news", "correction", "erratum", "retraction", "letter", "comment",
              "miscellaneous", "journal matter", "obituary", "index", "abstract only", "meeting")
KEEP_TYPES = ("research", "review", "original", "systematic", "case report", "article")
CRUFT = re.compile(r"(source-schema-version|details-of-publishers-convertor|cover-date|Figure count|"
                   r"Table count|Page count|Converter:|mode:remove)", re.I)


def body_of(t):
    i = t.find("Abstract")
    if 0 <= i < 6000:
        return t[i:]
    m = list(EQRUN.finditer(t[:5000]))
    return t[m[-1].end():] if m else t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-year", type=int, default=2000)
    ap.add_argument("--min-chars", type=int, default=1500)
    ap.add_argument("--allow-nc", action="store_true")
    ap.add_argument("--sample", type=int, default=0, help="stop after N input rows (validation)")
    a = ap.parse_args()
    kept = 0; drop = collections.Counter(); src = collections.Counter(); toks = 0; n = 0
    for line in sys.stdin:
        n += 1
        if a.sample and n > a.sample:
            break
        try:
            r = json.loads(line); t = r.get("text", "") or ""
        except Exception:
            drop["parse"] += 1; continue
        ym = YEAR.search(t); year = int(ym.group(1)) if ym else 0
        if year and year < a.min_year:
            drop["old"] += 1; continue
        sm = SUBJ.search(t); subj = (sm.group(1).lower() if sm else "")
        if any(d in subj for d in DROP_TYPES):
            drop["bad_type"] += 1; continue
        lm = LIC.search(t); lic = lm.group(1) if lm else ("publicdomain" if PD.search(t[:3000]) else "")
        ok_lic = lic in ("by", "by-sa") or lic == "publicdomain" or (a.allow_nc and lic.startswith("by-nc"))
        if not ok_lic:
            drop["licence:" + (lic or "none")] += 1; continue
        body = body_of(t)
        body = "\n".join(ln for ln in body.splitlines() if not CRUFT.search(ln))
        body = re.sub(r"\s{3,}", " ", body).strip()
        if len(body) < a.min_chars:
            drop["short"] += 1; continue
        is_rev = "review" in subj or "systematic" in subj
        source = "pmc_review" if is_rev else "pmc_fulltext"
        src[source] += 1; kept += 1; toks += len(body[:12000]) // 4
        if not a.sample:
            provenance = {k: r[k] for k in ("pmcid", "pmid", "doi", "title", "url", "source_uri",
                                           "source_family", "source_sha256") if r.get(k)}
            sys.stdout.write(json.dumps({"text": body[:12000], "source": source, "year": year,
                                         "licence": lic, **provenance,
                                         "provenance_status": "identified" if r.get("pmcid") or r.get("source_uri")
                                         else "missing_upstream_identifier"}) + "\n")
    sys.stderr.write(f"PMC FILTER: in={n} kept={kept} ~tokens={toks:,} by_source={dict(src)}\n"
                     f"  dropped={dict(drop.most_common(10))}\n")


if __name__ == "__main__":
    raise SystemExit(main())
