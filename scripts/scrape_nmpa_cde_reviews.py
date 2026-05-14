"""
NMPA CDE (Center for Drug Evaluation) technical-review scraper — Option B
China-market enrichment, sibling to scrape_auspar_nonclinical.py and
scrape_canada_sbd.py.

The CDE publishes 技术审评报告 (Technical Review Reports) and
药品审评报告 (Drug Evaluation Reports) for approved drugs, both of which
contain a 非临床评价 (Nonclinical Evaluation) / 药理毒理学评价
(Pharmacology/Toxicology Evaluation) section. These are the Chinese
analog of FDA NDA reviews and EMA EPARs.

Why CDE: NMPA accepts ICH M4 CTD format since 2018, but NMPA-specific
requirements (ethnic-sensitivity bridging per ICH E5, Chinese GLP, CDE
technical guidelines) are absent from the v6 corpus. CDE reviews are
the highest-leverage real Chinese data source.

URL pattern (as of 2026): https://www.cde.org.cn/main/news/viewInfoCommon/<id>
Some reviews are published as PDFs; some as on-page HTML. This scraper
handles both.

Usage:
    python scripts/scrape_nmpa_cde_reviews.py --seed
    python scripts/scrape_nmpa_cde_reviews.py --urls-file <txt> --out <jsonl>
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]

# Seed list — placeholder structure. Replace with actual CDE review IDs when
# scraping from a network-connected host. The CDE search interface at
# https://www.cde.org.cn/main/xxgk/listpage/ exposes review IDs.
SEED_URLS = [
    # Format: https://www.cde.org.cn/main/news/viewInfoCommon/<hex_id>
    # Examples (verify when running):
    "https://www.cde.org.cn/main/news/viewInfoCommon/5a8e5b8b9f3e4c2a7d1f9e8c4b6a3d2e",
    "https://www.cde.org.cn/main/news/viewInfoCommon/6b9f6c9c0g4f5d3b8e2f0f9d5c7b4e3f",
]

# Section heading patterns marking start of nonclinical content in CDE reviews.
# CDE reports are typically in Simplified Chinese; English subheadings sometimes
# appear in bilingual review summaries.
NONCLINICAL_START_RE = re.compile(
    r"(?:"
    r"非临床(?:评价|研究|药理毒理学?)|"   # 非临床评价 / 非临床研究 / 非临床药理毒理
    r"药理毒理(?:学)?(?:评价|研究)?|"      # 药理毒理(学)评价
    r"Non[- ]clinical\s+(?:Evaluation|Pharmacology|Toxicology)|"
    r"Pharmacology[/ ]Toxicology"
    r")",
    re.IGNORECASE,
)
NONCLINICAL_END_RE = re.compile(
    r"(?:"
    r"临床(?:评价|研究|试验)|"             # 临床评价 / 临床研究 / 临床试验
    r"质量(?:评价|控制)|"                  # 质量评价
    r"生产工艺|"                            # 生产工艺
    r"Clinical\s+(?:Evaluation|Studies|Trial)|"
    r"Quality\s+Evaluation"
    r")",
    re.IGNORECASE,
)


def download(url: str, cache_dir: Path) -> Path:
    cache_dir.mkdir(parents=True, exist_ok=True)
    m = re.search(r"viewInfoCommon/([0-9a-f]+)", url)
    if not m:
        m = re.search(r"/([0-9a-f-]{8,})/?$", url)
    fname = f"cde_{m.group(1) if m else 'unknown'}.html"
    out = cache_dir / fname
    if out.exists() and out.stat().st_size > 0:
        return out
    print(f"  fetching {fname}...", end=" ", flush=True)
    req = Request(url, headers={
        "User-Agent": "biomate-research/1.0",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    })
    with urlopen(req, timeout=60) as resp, out.open("wb") as f:
        f.write(resp.read())
    print(f"{out.stat().st_size // 1024} KB")
    return out


def html_to_text(html: str) -> str:
    """Strip HTML tags, preserving Chinese characters and basic structure."""
    text = re.sub(r"<script[^>]*>.*?</script>", " ", html, flags=re.S | re.I)
    text = re.sub(r"<style[^>]*>.*?</style>",   " ", text, flags=re.S | re.I)
    # Treat headers + paragraphs as block boundaries (keep newlines for section detection)
    text = re.sub(r"</(?:h[1-6]|p|div|section)>", "\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    # HTML entities — full numeric + named entity map covers common Chinese sites
    text = re.sub(r"&nbsp;|&#160;", " ", text)
    text = re.sub(r"&amp;", "&", text)
    text = re.sub(r"&[a-z]+;|&#\d+;", " ", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n\s*\n", "\n\n", text).strip()
    return text


def extract_nonclinical(text: str) -> str | None:
    start = NONCLINICAL_START_RE.search(text)
    if not start:
        return None
    section = text[start.start():]
    end = NONCLINICAL_END_RE.search(section, pos=200)
    if end:
        section = section[: end.start()]
    return section.strip()


def detect_language(text: str) -> str:
    """Rough heuristic: count CJK characters vs ASCII letters."""
    cjk = len(re.findall(r"[一-鿿]", text))
    ascii_letters = len(re.findall(r"[A-Za-z]", text))
    if cjk > ascii_letters * 0.5:
        return "zh-CN"
    if cjk > 50:
        return "bilingual"
    return "en"


def make_record(url: str, nonclinical_text: str) -> dict:
    m = re.search(r"viewInfoCommon/([0-9a-f]+)", url)
    drug_id = m.group(1)[:8] if m else "unknown"
    lang = detect_language(nonclinical_text)

    # Bilingual / Chinese system prompt — model needs Chinese exposure to learn
    # NMPA regulatory voice. Cite ICH guidelines as adopted by NMPA + CDE technical
    # guidelines (e.g. CDE 化学药物非临床药代动力学研究技术指导原则).
    if lang == "zh-CN":
        system_msg = (
            "你是一名计算药理学家,负责为IND/IND等同申请撰写ICH M4 CTD 第2.6节"
            "(非临床部分)。请使用规范的中文药品监管语言,引用适用的 ICH 指导原则"
            "(如 ICH M3(R2)、ICH S2(R1)、ICH S7A/S7B)及 NMPA/CDE 技术指导原则。"
        )
        user_prompt = (
            f"请为药品 {drug_id} 撰写非临床评价摘要。引用适用的 ICH 指导原则及 "
            f"CDE 技术审评要点。"
        )
    else:
        system_msg = (
            "You are a computational pharmacologist preparing ICH M4 CTD Module "
            "2.6 nonclinical summaries for NMPA submission. Cite applicable ICH "
            "guidelines and NMPA/CDE technical guidelines."
        )
        user_prompt = (
            f"Write the nonclinical evaluation summary for {drug_id}. Cite ICH "
            f"M3(R2), ICH S2(R1), ICH S7A/S7B and NMPA/CDE technical guidelines "
            f"as appropriate."
        )

    return {
        "messages": [
            {"role": "system", "content": system_msg},
            {"role": "user", "content": user_prompt},
            {"role": "assistant", "content": nonclinical_text},
        ],
        "meta": {
            "task": "section_generation",
            "section_type": "tox_overview",
            "region": "NMPA",
            "source": "CDE_review",
            "drug": drug_id,
            "language": lang,
            "source_url": url,
        },
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", action="store_true",
                    help="use bundled placeholder seed list (replace with real URLs first)")
    ap.add_argument("--urls-file", type=Path)
    ap.add_argument("--out", type=Path,
                    default=ROOT / "data/regulatory_training/nmpa_cde/cde_nonclinical.jsonl")
    ap.add_argument("--cache", type=Path,
                    default=ROOT / "data/regulatory_training/nmpa_cde/html")
    ap.add_argument("--delay", type=float, default=2.0)
    args = ap.parse_args()

    if args.seed:
        print("NOTE: seed URLs are placeholders. Replace SEED_URLS in this script "
              "with actual CDE review IDs from https://www.cde.org.cn/main/xxgk/listpage/ "
              "before running productively.")
        urls = SEED_URLS
    elif args.urls_file:
        urls = [u.strip() for u in args.urls_file.read_text().splitlines() if u.strip()]
    else:
        print("Provide --seed or --urls-file")
        sys.exit(1)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    written, failed, skipped = 0, 0, 0
    lang_counts: dict[str, int] = {}

    with args.out.open("w") as f:
        for url in urls:
            try:
                html_path = download(url, args.cache)
                text = html_to_text(html_path.read_text(errors="replace"))
                nonclinical = extract_nonclinical(text)
                if not nonclinical or len(nonclinical) < 200:  # zh text is denser, lower min
                    print(f"    no nonclinical section in {html_path.name}")
                    skipped += 1
                    continue
                record = make_record(url, nonclinical[:8000])
                lang = record["meta"]["language"]
                lang_counts[lang] = lang_counts.get(lang, 0) + 1
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
                written += 1
                time.sleep(args.delay)
            except Exception as e:
                print(f"    FAIL {url}: {e}")
                failed += 1

    print(f"\nWrote {written} records ({lang_counts}), skipped {skipped}, failed {failed}")
    print(f"Output: {args.out}")


if __name__ == "__main__":
    main()
