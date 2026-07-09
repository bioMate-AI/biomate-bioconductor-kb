#!/usr/bin/env python3
"""
Reddit bioinformatics data collector for BioMate product research.

Collects posts + top comments from relevant subreddits, then runs lightweight
text mining to extract questions, pain points, tool mentions, and answer quality.

Usage:
    pip install praw pandas
    export REDDIT_CLIENT_ID=your_client_id
    export REDDIT_CLIENT_SECRET=your_client_secret
    export REDDIT_USER_AGENT="BioMate Research Bot 1.0 by u/your_username"

    python reddit_bioinformatics_collector.py --mode collect
    python reddit_bioinformatics_collector.py --mode analyze --input data/reddit_posts.json
    python reddit_bioinformatics_collector.py --mode full   # collect + analyze in one pass

Setup:
    1. Go to https://www.reddit.com/prefs/apps
    2. Click "create another app" → choose "script"
    3. Set redirect URI to http://localhost:8080
    4. Copy client_id (under the app name) and client_secret

Note on Terms of Service:
    Reddit's ToS allows data collection for research and product analysis.
    It prohibits using scraped data to contact users directly.
    All data is collected via Reddit's official API with rate limiting respected.
"""

import argparse
import json
import csv
import os
import re
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

try:
    import praw
    from praw.models import MoreComments
except ImportError:
    print("Install praw: pip install praw")
    sys.exit(1)

try:
    import pandas as pd
    HAS_PANDAS = True
except ImportError:
    HAS_PANDAS = False

# ── Subreddit targets ──────────────────────────────────────────────────────────
SUBREDDITS = [
    # Core bioinformatics
    "bioinformatics",
    "learnbioinformatics",
    "computational_biology",
    # Omics
    "genomics",
    "scrnaseq",           # single-cell RNA-seq
    "epigenetics",
    "proteomics",
    # Biology adjacent
    "genetics",
    "labrats",
    "biology",
    "biotech",
    # Drug discovery / clinical
    "drugdiscovery",
    "clinicalresearch",
    # ML in bio
    "MachineLearning",    # filtered by search terms
    "datascience",        # filtered by search terms
]

# Search terms to use when crawling general subreddits (datascience, ML)
BIOLOGY_SEARCH_TERMS = [
    "bioinformatics",
    "RNA-seq", "RNAseq", "transcriptomics",
    "single cell", "scRNA", "Seurat", "Scanpy",
    "GWAS", "genome-wide association",
    "variant calling", "GATK", "SNP",
    "protein structure", "AlphaFold",
    "drug discovery", "ADMET", "molecular docking",
    "DESeq2", "edgeR", "limma",
    "phylogenetics", "metagenomics",
    "flow cytometry", "mass spectrometry",
    "cryo-EM",
    "CRISPR", "gene expression",
    "pathway enrichment", "Gene Ontology",
    "Nextflow", "Snakemake", "bioinformatics pipeline",
]

# Subreddits where we scrape everything (not search-filtered)
NATIVE_BIOINFORMATICS_SUBS = {
    "bioinformatics", "learnbioinformatics", "computational_biology",
    "genomics", "scrnaseq", "epigenetics", "proteomics", "genetics",
    "drugdiscovery",
}

# Tool / platform names to detect mentions of (for competitive intelligence)
TOOL_MENTIONS = [
    "Galaxy", "BioMate", "Nextflow", "Snakemake", "CWL",
    "DESeq2", "edgeR", "limma", "Seurat", "Scanpy", "Monocle",
    "GATK", "BWA", "STAR", "HISAT2", "Salmon", "kallisto",
    "AlphaFold", "Rosetta", "PyMOL",
    "Bioconductor", "Biopython", "BioPy",
    "Terra", "DNAnexus", "Basespace", "Seven Bridges", "Illumina DRAGEN",
    "AWS Batch", "Google Life Sciences",
    "ChatGPT", "GPT-4", "Claude", "Gemini",
]

# Question-signal words (to detect posts that ARE questions)
QUESTION_PATTERNS = [
    r'\?',
    r'\bhow (to|do|can|should|would)\b',
    r'\bwhat (is|are|should|would|can)\b',
    r'\bwhy (is|are|does|do)\b',
    r'\bis (there|it|this|that)\b',
    r'\bwhich (tool|software|method|approach|package)\b',
    r'\bbest (way|practice|tool|method|approach)\b',
    r'\bhelp\b',
    r'\bsuggestion',
    r'\brecommend',
    r'\badvice\b',
]

# Pain-point signal words
PAIN_PATTERNS = [
    r'\bstruggl',
    r'\bdifficult',
    r'\bconfus',
    r'\bfrustrat',
    r'\bproblem\b',
    r'\bissue\b',
    r'\berror\b',
    r'\bbug\b',
    r'\bfail',
    r'\bbroken\b',
    r'\bdoesn.t work',
    r'\bnot working',
    r'\bcan.t figure',
    r'\bcannot figure',
    r'\bstuck\b',
    r'\bgiving up',
    r'\bnightmare',
    r'\bawful',
    r'\bterrible',
]

OUTPUT_DIR = Path(__file__).parent.parent / "data" / "reddit"


def build_reddit_client() -> praw.Reddit:
    client_id = os.environ.get("REDDIT_CLIENT_ID")
    client_secret = os.environ.get("REDDIT_CLIENT_SECRET")
    user_agent = os.environ.get(
        "REDDIT_USER_AGENT", "BioMate Research Bot 1.0"
    )
    if not client_id or not client_secret:
        print(
            "\nMissing Reddit credentials.\n"
            "Set REDDIT_CLIENT_ID and REDDIT_CLIENT_SECRET env vars.\n"
            "Get them at: https://www.reddit.com/prefs/apps\n"
        )
        sys.exit(1)
    return praw.Reddit(
        client_id=client_id,
        client_secret=client_secret,
        user_agent=user_agent,
    )


def is_question(text: str) -> bool:
    text_lower = text.lower()
    return any(re.search(p, text_lower) for p in QUESTION_PATTERNS)


def has_pain_signal(text: str) -> bool:
    text_lower = text.lower()
    return any(re.search(p, text_lower) for p in PAIN_PATTERNS)


def detect_tool_mentions(text: str) -> list[str]:
    text_lower = text.lower()
    return [t for t in TOOL_MENTIONS if t.lower() in text_lower]


def extract_top_comments(submission, max_comments: int = 10) -> list[dict]:
    comments = []
    try:
        submission.comments.replace_more(limit=0)  # skip "load more"
        for comment in submission.comments.list()[:max_comments]:
            if isinstance(comment, MoreComments):
                continue
            comments.append({
                "id": comment.id,
                "body": comment.body,
                "score": comment.score,
                "author": str(comment.author) if comment.author else "[deleted]",
                "created_utc": int(comment.created_utc),
                "is_top_level": comment.parent_id.startswith("t3_"),
            })
    except Exception as e:
        print(f"  [warn] comment fetch failed: {e}")
    return sorted(comments, key=lambda c: c["score"], reverse=True)


def collect_subreddit(
    reddit: praw.Reddit,
    sub_name: str,
    limit: int,
    sort: str,
    search_term: str | None,
    time_filter: str,
) -> list[dict]:
    posts = []
    try:
        sub = reddit.subreddit(sub_name)
        if search_term:
            submissions = sub.search(search_term, sort=sort, time_filter=time_filter, limit=limit)
        elif sort == "hot":
            submissions = sub.hot(limit=limit)
        elif sort == "top":
            submissions = sub.top(time_filter=time_filter, limit=limit)
        elif sort == "new":
            submissions = sub.new(limit=limit)
        else:
            submissions = sub.top(time_filter=time_filter, limit=limit)

        for submission in submissions:
            full_text = f"{submission.title} {submission.selftext}"
            post = {
                "id": submission.id,
                "subreddit": sub_name,
                "title": submission.title,
                "selftext": submission.selftext,
                "score": submission.score,
                "upvote_ratio": submission.upvote_ratio,
                "num_comments": submission.num_comments,
                "created_utc": int(submission.created_utc),
                "created_date": datetime.fromtimestamp(
                    submission.created_utc, tz=timezone.utc
                ).strftime("%Y-%m-%d"),
                "url": f"https://reddit.com{submission.permalink}",
                "flair": submission.link_flair_text or "",
                "author": str(submission.author) if submission.author else "[deleted]",
                # Text mining signals
                "is_question": is_question(full_text),
                "has_pain_signal": has_pain_signal(full_text),
                "tool_mentions": detect_tool_mentions(full_text),
                "search_term_used": search_term or "",
                "top_comments": extract_top_comments(submission),
            }
            posts.append(post)
            print(f"  [{sub_name}] {submission.score:>5} pts | {submission.title[:70]}")
    except Exception as e:
        print(f"  [error] r/{sub_name}: {e}")
    return posts


def deduplicate(posts: list[dict]) -> list[dict]:
    seen = set()
    unique = []
    for p in posts:
        if p["id"] not in seen:
            seen.add(p["id"])
            unique.append(p)
    return unique


def collect(args) -> list[dict]:
    reddit = build_reddit_client()
    all_posts: list[dict] = []

    print(f"\n=== Collecting Reddit posts (limit={args.limit}, sort={args.sort}, time={args.time_filter}) ===\n")

    for sub_name in SUBREDDITS:
        if sub_name in NATIVE_BIOINFORMATICS_SUBS:
            print(f"\nr/{sub_name} (all posts)")
            posts = collect_subreddit(
                reddit, sub_name, args.limit, args.sort, None, args.time_filter
            )
            all_posts.extend(posts)
        else:
            # For general subs, search by biology terms
            for term in BIOLOGY_SEARCH_TERMS[:8]:  # top 8 terms to avoid rate limits
                print(f"\nr/{sub_name} [search: {term}]")
                posts = collect_subreddit(
                    reddit, sub_name, min(args.limit, 25), "relevance", term, args.time_filter
                )
                all_posts.extend(posts)
                time.sleep(0.5)  # be respectful of rate limits

    all_posts = deduplicate(all_posts)
    print(f"\nCollected {len(all_posts)} unique posts total")
    return all_posts


def save_json(posts: list[dict], path: Path):
    with open(path, "w") as f:
        json.dump(posts, f, indent=2)
    print(f"Saved JSON: {path}")


def save_csv(posts: list[dict], path: Path):
    if not posts:
        return
    flat = []
    for p in posts:
        row = {k: v for k, v in p.items() if k not in ("top_comments", "tool_mentions")}
        row["tool_mentions"] = ", ".join(p.get("tool_mentions", []))
        top = p.get("top_comments", [])
        row["top_answer"] = top[0]["body"][:500] if top else ""
        row["top_answer_score"] = top[0]["score"] if top else 0
        flat.append(row)

    keys = list(flat[0].keys())
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=keys)
        writer.writeheader()
        writer.writerows(flat)
    print(f"Saved CSV:  {path}")


def analyze(posts: list[dict]) -> dict:
    print("\n=== Text Mining Analysis ===\n")

    # ── 1. Question posts ──────────────────────────────────────────────────────
    questions = [p for p in posts if p["is_question"]]
    pain_posts = [p for p in posts if p["has_pain_signal"]]

    print(f"Total posts:          {len(posts)}")
    print(f"Question posts:       {len(questions)} ({100*len(questions)//max(len(posts),1)}%)")
    print(f"Pain-signal posts:    {len(pain_posts)} ({100*len(pain_posts)//max(len(posts),1)}%)")

    # ── 2. Top questions by engagement ────────────────────────────────────────
    top_questions = sorted(questions, key=lambda p: p["score"], reverse=True)[:20]
    print("\nTop 20 highest-voted questions:")
    for p in top_questions:
        print(f"  {p['score']:>5} pts | r/{p['subreddit']:<25} | {p['title'][:70]}")

    # ── 3. Top pain posts ─────────────────────────────────────────────────────
    top_pain = sorted(pain_posts, key=lambda p: p["score"], reverse=True)[:20]
    print("\nTop 20 pain-signal posts (by votes):")
    for p in top_pain:
        print(f"  {p['score']:>5} pts | r/{p['subreddit']:<25} | {p['title'][:70]}")

    # ── 4. Subreddit breakdown ─────────────────────────────────────────────────
    sub_counts = Counter(p["subreddit"] for p in posts)
    print("\nPosts per subreddit:")
    for sub, count in sub_counts.most_common():
        print(f"  r/{sub:<30} {count}")

    # ── 5. Tool mention frequency ─────────────────────────────────────────────
    all_tool_mentions = []
    for p in posts:
        all_tool_mentions.extend(p.get("tool_mentions", []))
    tool_freq = Counter(all_tool_mentions)
    print("\nTool/platform mentions:")
    for tool, count in tool_freq.most_common(20):
        print(f"  {tool:<30} {count}")

    # ── 6. Flair / topic breakdown ────────────────────────────────────────────
    flair_counts = Counter(p["flair"] for p in posts if p["flair"])
    print("\nTop flairs/topics:")
    for flair, count in flair_counts.most_common(20):
        print(f"  {flair:<40} {count}")

    # ── 7. Monthly volume trend ───────────────────────────────────────────────
    monthly = Counter(p["created_date"][:7] for p in posts)
    print("\nMonthly post volume (recent 12 months):")
    for month in sorted(monthly)[-12:]:
        bar = "█" * (monthly[month] // 2)
        print(f"  {month}  {monthly[month]:>4}  {bar}")

    # ── 8. High-value answered questions (question + top comment score > 10) ──
    answered = [
        p for p in questions
        if p.get("top_comments") and p["top_comments"][0]["score"] > 10
    ]
    answered.sort(key=lambda p: p["top_comments"][0]["score"], reverse=True)
    print(f"\nWell-answered questions (top answer score > 10): {len(answered)}")

    return {
        "total_posts": len(posts),
        "question_posts": len(questions),
        "pain_signal_posts": len(pain_posts),
        "top_questions": top_questions,
        "top_pain_posts": top_pain,
        "subreddit_breakdown": dict(sub_counts),
        "tool_mention_frequency": dict(tool_freq),
        "flair_breakdown": dict(flair_counts),
        "well_answered_questions": answered[:50],
    }


def save_analysis(analysis: dict, path: Path):
    with open(path, "w") as f:
        json.dump(analysis, f, indent=2)
    print(f"Saved analysis: {path}")


def save_qa_csv(analysis: dict, path: Path):
    """Save a clean Q&A CSV with best questions + best answers — ready for LLM fine-tuning or review."""
    rows = []
    for p in analysis.get("well_answered_questions", []):
        top = p.get("top_comments", [])
        rows.append({
            "subreddit": p["subreddit"],
            "date": p["created_date"],
            "score": p["score"],
            "question": p["title"],
            "question_body": p["selftext"][:1000],
            "best_answer": top[0]["body"][:2000] if top else "",
            "answer_score": top[0]["score"] if top else 0,
            "url": p["url"],
            "tool_mentions": ", ".join(p.get("tool_mentions", [])),
            "has_pain_signal": p["has_pain_signal"],
        })
    # Add top questions even if answer score < 10
    seen_ids = {p["url"] for p in analysis.get("well_answered_questions", [])}
    for p in analysis.get("top_questions", []):
        if p["url"] not in seen_ids:
            top = p.get("top_comments", [])
            rows.append({
                "subreddit": p["subreddit"],
                "date": p["created_date"],
                "score": p["score"],
                "question": p["title"],
                "question_body": p["selftext"][:1000],
                "best_answer": top[0]["body"][:2000] if top else "",
                "answer_score": top[0]["score"] if top else 0,
                "url": p["url"],
                "tool_mentions": ", ".join(p.get("tool_mentions", [])),
                "has_pain_signal": p["has_pain_signal"],
            })

    rows.sort(key=lambda r: r["score"], reverse=True)
    if not rows:
        return
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Saved Q&A CSV:  {path} ({len(rows)} rows)")


def main():
    parser = argparse.ArgumentParser(description="Reddit bioinformatics collector")
    parser.add_argument(
        "--mode",
        choices=["collect", "analyze", "full"],
        default="full",
        help="collect: crawl only; analyze: mine existing JSON; full: both",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=100,
        help="Max posts per subreddit (default: 100)",
    )
    parser.add_argument(
        "--sort",
        choices=["hot", "top", "new"],
        default="top",
        help="Sort order (default: top)",
    )
    parser.add_argument(
        "--time-filter",
        choices=["day", "week", "month", "year", "all"],
        default="year",
        help="Time filter for 'top' sort (default: year)",
    )
    parser.add_argument(
        "--input",
        type=str,
        help="Path to existing JSON (for --mode analyze)",
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default=str(OUTPUT_DIR),
        help=f"Output directory (default: {OUTPUT_DIR})",
    )
    args = parser.parse_args()

    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M")

    if args.mode in ("collect", "full"):
        posts = collect(args)
        json_path = out / f"reddit_posts_{timestamp}.json"
        csv_path = out / f"reddit_posts_{timestamp}.csv"
        save_json(posts, json_path)
        save_csv(posts, csv_path)
    else:
        if not args.input:
            print("--mode analyze requires --input <path-to-json>")
            sys.exit(1)
        with open(args.input) as f:
            posts = json.load(f)
        print(f"Loaded {len(posts)} posts from {args.input}")

    if args.mode in ("analyze", "full"):
        analysis = analyze(posts)
        analysis_path = out / f"reddit_analysis_{timestamp}.json"
        qa_path = out / f"reddit_qa_{timestamp}.csv"
        save_analysis(analysis, analysis_path)
        save_qa_csv(analysis, qa_path)

    print("\nDone.")


if __name__ == "__main__":
    main()
