#!/usr/bin/env python
"""
Compare Embedding Models for Production

This script:
1. Uses existing MiniLM embeddings (production)
2. Generates BGE embeddings to a separate file
3. Compares search results side-by-side
4. Does NOT modify production embeddings

Run from backend directory:
    python lib/galaxy/ai/tests/embedding_models/compare_embeddings_production.py
"""

import sys
import os
import time
import sqlite3
from pathlib import Path
from typing import List, Dict, Any, Tuple
import numpy as np

# Add backend to path
backend_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', '..'))
sys.path.insert(0, backend_path)


# Test queries for side-by-side comparison
TEST_QUERIES = [
    "quality control for sequencing reads",
    "RNA-seq differential expression analysis",
    "protein sequence alignment BLAST",
    "variant calling SNP detection",
    "genome assembly de novo",
    "ChIP-seq peak calling",
    "metabolomics mass spectrometry",
    "phylogenetic tree construction",
]


def get_db_path() -> str:
    """Get path to tool database."""
    return os.path.join(backend_path, "database", "galaxy_ai_tools.db")


def get_production_embedding_path() -> str:
    """Get path to production embeddings (MiniLM)."""
    return os.path.join(backend_path, "database", "galaxy_ai_tools_embeddings.npz")


def get_bge_embedding_path() -> str:
    """Get path to BGE test embeddings (separate file)."""
    return os.path.join(backend_path, "database", "galaxy_ai_tools_embeddings_bge_test.npz")


def load_tools_text(db_path: str) -> Tuple[List[str], List[str], List[str]]:
    """Load tool texts for embedding."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute('''
        SELECT tool_id, name, description, category, help_text, tags,
               edam_operations, edam_topics
        FROM tools
    ''')

    tool_ids = []
    texts = []
    names = []

    for row in cursor.fetchall():
        tool_id, name, desc, category, help_text, tags, edam_ops, edam_topics = row
        tool_ids.append(tool_id)
        names.append(name or tool_id)

        # Create rich text representation (same as vector_search.py)
        parts = [name] if name else []
        if desc:
            parts.append(desc[:500])
        if category:
            parts.append(f"Category: {category}")
        if help_text:
            parts.append(f"Help: {help_text[:300]}")
        if tags:
            parts.append(f"Tags: {tags}")
        if edam_ops:
            parts.append(f"Operations: {edam_ops}")
        if edam_topics:
            parts.append(f"Topics: {edam_topics}")

        text = ". ".join(parts)
        texts.append(text)

    conn.close()
    return tool_ids, names, texts


def generate_bge_embeddings(texts: List[str], tool_ids: List[str], output_path: str):
    """Generate BGE embeddings and save to separate file."""
    from sentence_transformers import SentenceTransformer

    print(f"Loading BGE model...")
    model = SentenceTransformer('BAAI/bge-small-en-v1.5', device='cpu')

    print(f"Generating embeddings for {len(texts)} tools...")
    start = time.time()
    embeddings = model.encode(texts, show_progress_bar=True, batch_size=64)
    elapsed = time.time() - start
    print(f"Done in {elapsed:.1f}s ({len(texts)/elapsed:.1f} tools/sec)")

    # Save to separate file
    np.savez(output_path, tool_ids=tool_ids, embeddings=embeddings)
    print(f"Saved BGE embeddings to: {output_path}")

    return embeddings


def search_with_embeddings(
    query: str,
    model,
    embeddings: np.ndarray,
    tool_ids: List[str],
    names: List[str],
    top_k: int = 5
) -> List[Dict]:
    """Search using pre-computed embeddings."""
    query_emb = model.encode(query)

    # Cosine similarity
    query_norm = query_emb / np.linalg.norm(query_emb)
    emb_norm = embeddings / np.linalg.norm(embeddings, axis=1, keepdims=True)
    similarities = np.dot(emb_norm, query_norm)

    # Top-k
    top_idx = np.argsort(similarities)[::-1][:top_k]

    results = []
    for idx in top_idx:
        results.append({
            'tool_id': tool_ids[idx],
            'name': names[idx],
            'score': float(similarities[idx])
        })
    return results


def compare_search_results(query: str, minilm_results: List[Dict], bge_results: List[Dict]):
    """Print side-by-side comparison."""
    print(f"\nQuery: {query}")
    print("-" * 80)
    print(f"{'MiniLM Results':<40} {'BGE Results':<40}")
    print("-" * 80)

    for i in range(max(len(minilm_results), len(bge_results))):
        left = ""
        right = ""
        if i < len(minilm_results):
            r = minilm_results[i]
            left = f"{r['name'][:30]:<30} ({r['score']:.3f})"
        if i < len(bge_results):
            r = bge_results[i]
            right = f"{r['name'][:30]:<30} ({r['score']:.3f})"
        print(f"{left:<40} {right:<40}")


def main():
    from sentence_transformers import SentenceTransformer

    print("=" * 80)
    print("Embedding Model Comparison (Production vs BGE Test)")
    print("=" * 80)

    db_path = get_db_path()
    prod_emb_path = get_production_embedding_path()
    bge_emb_path = get_bge_embedding_path()

    # Load tool data
    print(f"\nLoading tools from: {db_path}")
    tool_ids, names, texts = load_tools_text(db_path)
    print(f"Loaded {len(tool_ids)} tools")

    # Check if BGE embeddings already exist
    if os.path.exists(bge_emb_path):
        print(f"\nLoading existing BGE embeddings from: {bge_emb_path}")
        bge_data = np.load(bge_emb_path, allow_pickle=True)
        bge_embeddings = bge_data['embeddings']
        bge_tool_ids = list(bge_data['tool_ids'])
    else:
        print(f"\nBGE embeddings not found, generating...")
        bge_embeddings = generate_bge_embeddings(texts, tool_ids, bge_emb_path)
        bge_tool_ids = tool_ids

    # Load production embeddings
    print(f"\nLoading production (MiniLM) embeddings from: {prod_emb_path}")
    prod_data = np.load(prod_emb_path, allow_pickle=True)
    prod_embeddings = prod_data['embeddings']
    prod_tool_ids = list(prod_data['tool_ids'])

    print(f"  Production: {prod_embeddings.shape}")
    print(f"  BGE Test:   {bge_embeddings.shape}")

    # Load models for query encoding
    print("\nLoading models for query encoding...")
    minilm_model = SentenceTransformer('all-MiniLM-L6-v2', device='cpu')
    bge_model = SentenceTransformer('BAAI/bge-small-en-v1.5', device='cpu')

    # Compare search results
    print("\n" + "=" * 80)
    print("SEARCH COMPARISON (Top 5 results)")
    print("=" * 80)

    for query in TEST_QUERIES:
        minilm_results = search_with_embeddings(
            query, minilm_model, prod_embeddings, prod_tool_ids, names, top_k=5
        )
        bge_results = search_with_embeddings(
            query, bge_model, bge_embeddings, bge_tool_ids, names, top_k=5
        )
        compare_search_results(query, minilm_results, bge_results)

    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Production embeddings: {prod_emb_path}")
    print(f"BGE test embeddings:   {bge_emb_path}")
    print("\nTo upgrade production:")
    print("  1. Review search results above")
    print("  2. If BGE is better, update vector_search.py DEFAULT_MODEL")
    print("  3. Replace production embeddings with BGE embeddings")
    print("=" * 80)


if __name__ == '__main__':
    main()
