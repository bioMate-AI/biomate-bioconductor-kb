#!/usr/bin/env python3
"""
Quick test to compare parallel vs sequential GitHub search performance.
"""
import time
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / 'scripts'))

from detect_github_tools import GitHubDetector, load_config

def test_search(parallel: bool, topics_count: int = 10):
    """Test search with parallel on/off."""
    # Load config
    config_dir = Path(__file__).parent / 'auto_update' / 'config'
    config = load_config(config_dir)

    # Get GitHub token
    import os
    token = os.getenv('GITHUB_TOKEN')
    if not token:
        print("ERROR: GITHUB_TOKEN not set")
        return

    # Initialize detector
    detector = GitHubDetector(token, config)

    # Use first N topics
    all_topics = [
        'bioinformatics', 'genomics', 'proteomics', 'metabolomics',
        'computational-biology', 'single-cell', 'rna-seq', 'variant-calling',
        'transcriptomics', 'systems-biology'
    ]
    topics = all_topics[:topics_count]

    print(f"\n{'='*60}")
    print(f"Testing {'PARALLEL' if parallel else 'SEQUENTIAL'} search")
    print(f"Topics: {topics_count} ({', '.join(topics[:3])}...)")
    print(f"{'='*60}\n")

    start_time = time.time()

    # Search with high early termination threshold so it searches more topics
    results = detector.search_repos(
        topics=topics,
        min_stars=75,
        days_back=30,
        max_high_quality=100,  # High threshold to force searching multiple topics
        parallel=parallel,
        max_workers=5
    )

    elapsed = time.time() - start_time

    print(f"\n{'='*60}")
    print(f"Results: {len(results)} unique tools found")
    print(f"Time: {elapsed:.1f}s")
    print(f"{'='*60}\n")

    return elapsed, len(results)

if __name__ == '__main__':
    print("Parallel Search Performance Test")
    print("=" * 60)

    # Test with 5 topics
    topics_count = 5

    print("\n🔄 Running SEQUENTIAL search...")
    seq_time, seq_count = test_search(parallel=False, topics_count=topics_count)

    print("\n⚡ Running PARALLEL search...")
    par_time, par_count = test_search(parallel=True, topics_count=topics_count)

    print("\n" + "=" * 60)
    print("COMPARISON")
    print("=" * 60)
    print(f"Sequential: {seq_time:.1f}s, {seq_count} tools")
    print(f"Parallel:   {par_time:.1f}s, {par_count} tools")
    print(f"Speedup:    {seq_time/par_time:.1f}x")
    print("=" * 60)
