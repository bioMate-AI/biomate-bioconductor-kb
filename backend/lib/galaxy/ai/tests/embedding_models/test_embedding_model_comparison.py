#!/usr/bin/env python
"""
Embedding Model Comparison Test Harness

Compares embedding models for biomate's tool search:
1. all-MiniLM-L6-v2 (current)
2. google/embeddinggemma-300m (proposed)

Metrics:
- Model loading time
- Encoding speed (sentences/second)
- Accuracy on tool search queries
- Memory usage

Run from backend directory:
    python lib/galaxy/ai/tests/embedding_models/test_embedding_model_comparison.py
"""

import sys
import os
import time
import json
import sqlite3
from pathlib import Path
from typing import List, Dict, Any, Tuple
import numpy as np

# Add backend to path
backend_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', '..'))
sys.path.insert(0, backend_path)


# Test queries and expected tool categories
TEST_QUERIES = [
    {
        "query": "RNA-seq differential expression analysis",
        "expected_tools": ["deseq2", "edger", "limma", "featurecounts", "htseq-count", "salmon", "kallisto"],
        "category": "RNA-seq"
    },
    {
        "query": "protein sequence alignment",
        "expected_tools": ["blast", "diamond", "clustalw", "muscle", "mafft", "t-coffee"],
        "category": "Alignment"
    },
    {
        "query": "variant calling from whole genome sequencing",
        "expected_tools": ["gatk", "freebayes", "bcftools", "samtools", "bwa", "bowtie2"],
        "category": "Variant Calling"
    },
    {
        "query": "quality control for sequencing reads",
        "expected_tools": ["fastqc", "multiqc", "trimmomatic", "cutadapt", "fastp"],
        "category": "QC"
    },
    {
        "query": "ChIP-seq peak calling",
        "expected_tools": ["macs2", "homer", "sicer", "peakseq", "spp"],
        "category": "ChIP-seq"
    },
    {
        "query": "metabolomics data analysis",
        "expected_tools": ["xcms", "metaboanalyst", "mzmine", "openms"],
        "category": "Metabolomics"
    },
    {
        "query": "genome assembly de novo",
        "expected_tools": ["spades", "velvet", "abyss", "megahit", "flye", "canu"],
        "category": "Assembly"
    },
    {
        "query": "phylogenetic tree construction",
        "expected_tools": ["raxml", "iqtree", "mrbayes", "fasttree", "beast"],
        "category": "Phylogenetics"
    },
]


def get_tool_database_path() -> str:
    """Get path to the tool database."""
    # Try common locations
    possible_paths = [
        os.path.join(backend_path, "database", "galaxy_ai_tools.db"),
        os.path.join(backend_path, "lib", "galaxy", "ai", "galaxy_ai_tools.db"),
        "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db",
    ]
    for path in possible_paths:
        if os.path.exists(path):
            return path
    return possible_paths[0]  # Return first as default


def load_tools_from_db(db_path: str, limit: int = 500) -> List[Dict[str, Any]]:
    """Load tools from database for testing."""
    if not os.path.exists(db_path):
        print(f"Warning: Database not found at {db_path}")
        return []

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute('''
        SELECT tool_id, name, description, category
        FROM tools
        LIMIT ?
    ''', (limit,))

    tools = []
    for row in cursor.fetchall():
        tools.append({
            'tool_id': row[0],
            'name': row[1],
            'description': row[2] or '',
            'category': row[3] or ''
        })

    conn.close()
    return tools


def create_tool_texts(tools: List[Dict]) -> Tuple[List[str], List[str]]:
    """Create searchable text for each tool."""
    texts = []
    tool_ids = []
    for tool in tools:
        text = f"{tool['name']} {tool['description']} {tool['category']}"
        texts.append(text)
        tool_ids.append(tool['tool_id'])
    return texts, tool_ids


class EmbeddingModelTester:
    """Test harness for embedding models."""

    def __init__(self, model_name: str, device: str = 'cpu'):
        self.model_name = model_name
        self.device = device
        self.model = None
        self.load_time = 0
        self.dimension = 0

    def load_model(self):
        """Load the embedding model and measure time."""
        from sentence_transformers import SentenceTransformer

        start = time.time()
        self.model = SentenceTransformer(self.model_name, device=self.device)
        self.load_time = time.time() - start

        # Get embedding dimension
        test_embedding = self.model.encode("test")
        self.dimension = len(test_embedding)

        print(f"  Model: {self.model_name}")
        print(f"  Device: {self.device}")
        print(f"  Load time: {self.load_time:.2f}s")
        print(f"  Dimension: {self.dimension}")

    def benchmark_encoding_speed(self, texts: List[str], batch_size: int = 32) -> Dict[str, float]:
        """Benchmark encoding speed."""
        # Warm up
        _ = self.model.encode(texts[:10])

        # Benchmark
        start = time.time()
        embeddings = self.model.encode(texts, batch_size=batch_size, show_progress_bar=False)
        elapsed = time.time() - start

        return {
            'total_texts': len(texts),
            'total_time': elapsed,
            'texts_per_second': len(texts) / elapsed,
            'ms_per_text': (elapsed / len(texts)) * 1000
        }

    def search_tools(
        self,
        query: str,
        tool_embeddings: np.ndarray,
        tool_ids: List[str],
        top_k: int = 10
    ) -> List[Tuple[str, float]]:
        """Search for tools using the query."""
        query_embedding = self.model.encode(query)

        # Compute cosine similarity
        similarities = np.dot(tool_embeddings, query_embedding) / (
            np.linalg.norm(tool_embeddings, axis=1) * np.linalg.norm(query_embedding)
        )

        # Get top-k
        top_indices = np.argsort(similarities)[::-1][:top_k]

        results = []
        for idx in top_indices:
            results.append((tool_ids[idx], float(similarities[idx])))

        return results

    def evaluate_accuracy(
        self,
        queries: List[Dict],
        tool_embeddings: np.ndarray,
        tool_ids: List[str],
        top_k: int = 10
    ) -> Dict[str, Any]:
        """Evaluate search accuracy on test queries."""
        results = []

        for query_info in queries:
            query = query_info['query']
            expected = [t.lower() for t in query_info['expected_tools']]

            search_results = self.search_tools(query, tool_embeddings, tool_ids, top_k)

            # Check how many expected tools are in top-k
            found_ids = [r[0].lower() for r in search_results]
            hits = sum(1 for e in expected if any(e in fid for fid in found_ids))

            results.append({
                'query': query,
                'category': query_info['category'],
                'expected_count': len(expected),
                'hits_in_top_k': hits,
                'recall': hits / len(expected) if expected else 0,
                'top_results': search_results[:5]
            })

        # Aggregate metrics
        avg_recall = np.mean([r['recall'] for r in results])

        return {
            'per_query': results,
            'average_recall': avg_recall,
            'total_queries': len(queries)
        }


def run_comparison(device: str = 'cpu'):
    """Run comparison between embedding models."""
    print("=" * 70)
    print("Embedding Model Comparison Test")
    print("=" * 70)
    print(f"\nDevice: {device}")
    print(f"Date: {time.strftime('%Y-%m-%d %H:%M:%S')}")

    # Models to compare
    models = [
        "sentence-transformers/all-MiniLM-L6-v2",  # Previous biomate model
        "BAAI/bge-small-en-v1.5",                   # New biomate model (+6 MTEB points)
        # "google/embeddinggemma-300m",            # Gated - requires HuggingFace login
    ]

    # Load tools - use ALL tools for full test
    db_path = get_tool_database_path()
    print(f"\nLoading tools from: {db_path}")
    tools = load_tools_from_db(db_path, limit=10000)  # Load all tools

    if not tools:
        print("No tools found. Using synthetic test data.")
        tools = [
            {'tool_id': f'tool_{i}', 'name': f'Test Tool {i}',
             'description': f'Description for tool {i}', 'category': 'Test'}
            for i in range(100)
        ]

    print(f"Loaded {len(tools)} tools")

    tool_texts, tool_ids = create_tool_texts(tools)

    results = {}

    for model_name in models:
        print(f"\n{'=' * 70}")
        print(f"Testing: {model_name}")
        print("=" * 70)

        try:
            tester = EmbeddingModelTester(model_name, device=device)

            # Load model
            print("\n1. Loading model...")
            tester.load_model()

            # Benchmark encoding speed
            print("\n2. Benchmarking encoding speed...")
            speed_results = tester.benchmark_encoding_speed(tool_texts)
            print(f"  Total texts: {speed_results['total_texts']}")
            print(f"  Total time: {speed_results['total_time']:.2f}s")
            print(f"  Speed: {speed_results['texts_per_second']:.1f} texts/sec")
            print(f"  Latency: {speed_results['ms_per_text']:.2f} ms/text")

            # Generate tool embeddings
            print("\n3. Generating tool embeddings...")
            start = time.time()
            tool_embeddings = tester.model.encode(tool_texts, show_progress_bar=False)
            embed_time = time.time() - start
            print(f"  Time: {embed_time:.2f}s")
            print(f"  Shape: {tool_embeddings.shape}")

            # Evaluate accuracy
            print("\n4. Evaluating search accuracy...")
            accuracy_results = tester.evaluate_accuracy(
                TEST_QUERIES, tool_embeddings, tool_ids, top_k=10
            )
            print(f"  Average Recall@10: {accuracy_results['average_recall']:.2%}")

            # Print per-query results
            print("\n  Per-query results:")
            for qr in accuracy_results['per_query']:
                print(f"    [{qr['category']}] {qr['query'][:40]}...")
                print(f"      Recall: {qr['recall']:.2%} ({qr['hits_in_top_k']}/{qr['expected_count']})")
                print(f"      Top-3: {[r[0] for r in qr['top_results'][:3]]}")

            results[model_name] = {
                'load_time': tester.load_time,
                'dimension': tester.dimension,
                'speed': speed_results,
                'accuracy': accuracy_results
            }

        except Exception as e:
            print(f"  ERROR: {e}")
            import traceback
            traceback.print_exc()
            results[model_name] = {'error': str(e)}

    # Summary comparison
    print("\n" + "=" * 70)
    print("SUMMARY COMPARISON")
    print("=" * 70)

    print(f"\n{'Model':<45} {'Load(s)':<10} {'Dim':<8} {'Speed':<15} {'Recall@10':<10}")
    print("-" * 88)

    for model_name, data in results.items():
        if 'error' in data:
            print(f"{model_name:<45} ERROR: {data['error'][:30]}")
        else:
            short_name = model_name.split('/')[-1]
            load_time = f"{data['load_time']:.2f}"
            dim = str(data['dimension'])
            speed = f"{data['speed']['texts_per_second']:.1f} t/s"
            recall = f"{data['accuracy']['average_recall']:.2%}"
            print(f"{short_name:<45} {load_time:<10} {dim:<8} {speed:<15} {recall:<10}")

    print("\n" + "=" * 70)

    return results


def main():
    """Main entry point."""
    import argparse
    parser = argparse.ArgumentParser(description='Compare embedding models')
    parser.add_argument('--device', default='cpu', choices=['cpu', 'cuda'],
                        help='Device to use (default: cpu)')
    args = parser.parse_args()

    results = run_comparison(device=args.device)

    # Save results
    output_path = os.path.join(
        os.path.dirname(__file__),
        f"comparison_results_{time.strftime('%Y%m%d_%H%M%S')}.json"
    )
    with open(output_path, 'w') as f:
        # Convert numpy types for JSON
        def convert(obj):
            if isinstance(obj, np.floating):
                return float(obj)
            if isinstance(obj, np.integer):
                return int(obj)
            if isinstance(obj, np.ndarray):
                return obj.tolist()
            return obj

        json.dump(results, f, indent=2, default=convert)

    print(f"\nResults saved to: {output_path}")


if __name__ == '__main__':
    main()
