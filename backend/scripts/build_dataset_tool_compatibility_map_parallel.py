#!/usr/bin/env python3
"""
Parallel version of dataset-tool compatibility mapping.
Splits datasets into chunks and processes them concurrently.
"""
import json
import sqlite3
import os
import sys
import time
from typing import List, Dict, Any
from pathlib import Path
import anthropic
from concurrent.futures import ThreadPoolExecutor, as_completed
import argparse

# Import batch matcher
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from batch_compatibility_matcher import BatchCompatibilityMatcher

# Configuration
GALAXY_TOOLS_DB = "/Users/jingqiwang/biomate/backend/galaxy_ai_tools.db"
REFERENCE_DATA_JSON = "/Users/jingqiwang/biomate/backend/reference_data_complete.json"
OUTPUT_DIR = "/Users/jingqiwang/biomate/backend/parallel_results"
FINAL_OUTPUT_JSON = "/Users/jingqiwang/biomate/backend/reference_data_with_compatible_tools.json"

# LLM configuration
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
if not ANTHROPIC_API_KEY:
    print("Error: ANTHROPIC_API_KEY environment variable not set")
    sys.exit(1)

client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

# Category mapping (dataset category → tool categories)
CATEGORY_MAPPING = {
    'drug_discovery': ['Computational chemistry'],
    'drug_interactions': ['Computational chemistry', 'Systems Biology'],
    'metabolomics': ['Metabolomics'],
    'proteomics': ['Proteomics'],
    'genomics': ['Sequence Analysis', 'Genome annotation'],
    'cancer_genomics': ['Sequence Analysis', 'Systems Biology', 'Genomic Interval Operations'],
    'transcriptomics': ['RNA'],
    'systems_biology': ['Systems Biology'],
    'protein_interactions': ['Proteomics', 'Systems Biology'],
    'pathway_analysis': ['Systems Biology', 'Metabolomics'],
    'single_cell': ['Single-cell'],
    'genetics': ['Sequence Analysis', 'Genome annotation'],
    'gene_regulation': ['RNA', 'Sequence Analysis'],
}


class ParallelDatasetMatcher:
    """Process datasets in parallel"""

    def __init__(self, worker_id: int, delay: float = 0.0):
        self.worker_id = worker_id
        self.delay = delay
        self.db_conn = sqlite3.connect(GALAXY_TOOLS_DB)
        self.batch_matcher = BatchCompatibilityMatcher()

        # Small initial delay to stagger workers
        if self.delay > 0:
            time.sleep(self.delay)

    def log(self, message: str):
        """Log with worker ID"""
        timestamp = time.strftime("%H:%M:%S")
        print(f"[Worker {self.worker_id}] [{timestamp}] {message}", flush=True)

    def filter_candidate_tools(self, dataset: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Code-based filtering to get candidate tools"""
        dataset_category = dataset.get('category', 'unknown')
        tool_categories = CATEGORY_MAPPING.get(dataset_category, [])

        if not tool_categories:
            tool_categories = ['Sequence Analysis', 'Systems Biology', 'Data Source']

        # Build category filter with EXACT match
        category_conditions = " OR ".join([f"category = '{cat}'" for cat in tool_categories])

        cursor = self.db_conn.cursor()
        query = f"""
        SELECT tool_id, name, category, rawText
        FROM tools
        WHERE ({category_conditions})
        LIMIT 500
        """

        cursor.execute(query)
        rows = cursor.fetchall()

        candidates = []
        for row in rows:
            candidates.append({
                'tool_id': row[0],
                'name': row[1],
                'category': row[2],
                'rawText': row[3],
                'score': 1  # Simple scoring
            })

        # Sort by score
        candidates.sort(key=lambda x: x['score'], reverse=True)
        return candidates

    def process_dataset(self, dataset_key: str, dataset: Dict[str, Any]) -> Dict[str, Any]:
        """Process a single dataset"""
        self.log(f"Processing {dataset['name']}...")

        # Filter candidates
        candidates = self.filter_candidate_tools(dataset)
        self.log(f"  Found {len(candidates)} candidates for {dataset['name']}")

        # Batch evaluate ALL candidates in ONE API call - much faster!
        validation_limit = min(100, len(candidates))  # Check top 100 candidates
        candidates_to_evaluate = candidates[:validation_limit]

        self.log(f"  Batch evaluating {len(candidates_to_evaluate)} candidates...")

        try:
            compatible_tools = self.batch_matcher.analyze_batch(dataset, candidates_to_evaluate)

            for tool in compatible_tools:
                self.log(f"  ✓ Compatible: {tool['name']} (conf: {tool['confidence']:.2f})")

            self.log(f"✅ Found {len(compatible_tools)} compatible tools for {dataset['name']}")

        except Exception as e:
            self.log(f"✗ Batch evaluation error: {e}")
            compatible_tools = []

        return {
            'dataset_key': dataset_key,
            'dataset_name': dataset['name'],
            'compatible_tools': compatible_tools,
            'total_candidates': len(candidates),
            'validated': validation_limit
        }

    def process_batch(self, datasets_batch: Dict[str, Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Process a batch of datasets"""
        results = []
        for dataset_key, dataset in datasets_batch.items():
            try:
                result = self.process_dataset(dataset_key, dataset)
                results.append(result)
            except Exception as e:
                self.log(f"ERROR processing {dataset_key}: {e}")
                results.append({
                    'dataset_key': dataset_key,
                    'error': str(e)
                })
        return results


def split_datasets(datasets: Dict[str, Dict[str, Any]], num_workers: int) -> List[Dict[str, Dict[str, Any]]]:
    """Split datasets into chunks for parallel processing"""
    dataset_items = list(datasets.items())
    chunk_size = len(dataset_items) // num_workers + 1

    chunks = []
    for i in range(num_workers):
        start = i * chunk_size
        end = start + chunk_size
        chunk = dict(dataset_items[start:end])
        if chunk:
            chunks.append(chunk)

    return chunks


def merge_results(output_dir: str, reference_data: Dict[str, Any]) -> Dict[str, Any]:
    """Merge partial results into final output"""
    print("\n" + "="*70)
    print("MERGING RESULTS")
    print("="*70)

    # Load all result files
    result_files = sorted(Path(output_dir).glob("worker_*.json"))

    all_results = {}
    for result_file in result_files:
        with open(result_file, 'r') as f:
            worker_results = json.load(f)
            for result in worker_results:
                dataset_key = result['dataset_key']
                all_results[dataset_key] = result

    # Update reference data with compatible_tools
    updated_data = reference_data.copy()
    for dataset_key, result in all_results.items():
        if dataset_key in updated_data['datasets']:
            updated_data['datasets'][dataset_key]['compatible_tools'] = result.get('compatible_tools', [])

    # Summary
    total_datasets = len(all_results)
    datasets_with_tools = sum(1 for r in all_results.values() if len(r.get('compatible_tools', [])) > 0)
    total_compatible = sum(len(r.get('compatible_tools', [])) for r in all_results.values())

    print(f"\nSUMMARY:")
    print(f"  Total datasets processed: {total_datasets}")
    print(f"  Datasets with compatible tools: {datasets_with_tools}")
    print(f"  Total compatible tools found: {total_compatible}")

    return updated_data


def main():
    parser = argparse.ArgumentParser(description='Parallel dataset-tool compatibility mapping')
    parser.add_argument('--workers', type=int, default=8, help='Number of parallel workers')
    parser.add_argument('--delay', type=float, default=0.5, help='Delay between worker starts (seconds)')
    args = parser.parse_args()

    print("="*70)
    print("PARALLEL DATASET-TOOL COMPATIBILITY MAPPING")
    print("="*70)
    print(f"Workers: {args.workers}")
    print(f"Stagger delay: {args.delay}s")

    # Load reference data
    with open(REFERENCE_DATA_JSON, 'r') as f:
        reference_data = json.load(f)

    datasets = reference_data['datasets']

    # Filter to local datasets only
    local_datasets = {k: v for k, v in datasets.items() if v.get('access_method') == 'local_file'}

    print(f"\nTotal datasets: {len(datasets)}")
    print(f"Local datasets (processing): {len(local_datasets)}")
    print(f"API datasets (skipped): {len(datasets) - len(local_datasets)}")

    # Create output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Split datasets into chunks
    dataset_chunks = split_datasets(local_datasets, args.workers)

    print(f"\nDataset distribution:")
    for i, chunk in enumerate(dataset_chunks):
        print(f"  Worker {i}: {len(chunk)} datasets")

    # Process in parallel
    print(f"\n{'='*70}")
    print("STARTING PARALLEL PROCESSING")
    print(f"{'='*70}\n")

    def process_worker(worker_id: int, chunk: Dict[str, Dict[str, Any]]) -> str:
        """Worker function"""
        matcher = ParallelDatasetMatcher(worker_id, delay=worker_id * args.delay)
        results = matcher.process_batch(chunk)

        # Save results
        output_file = os.path.join(OUTPUT_DIR, f"worker_{worker_id}.json")
        with open(output_file, 'w') as f:
            json.dump(results, f, indent=2)

        return output_file

    # Execute with ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {
            executor.submit(process_worker, i, chunk): i
            for i, chunk in enumerate(dataset_chunks)
        }

        for future in as_completed(futures):
            worker_id = futures[future]
            try:
                output_file = future.result()
                print(f"\n[MAIN] Worker {worker_id} completed → {output_file}")
            except Exception as e:
                print(f"\n[MAIN] Worker {worker_id} failed: {e}")

    print(f"\n{'='*70}")
    print("ALL WORKERS COMPLETED")
    print(f"{'='*70}\n")

    # Merge results
    final_data = merge_results(OUTPUT_DIR, reference_data)

    # Save final output
    with open(FINAL_OUTPUT_JSON, 'w') as f:
        json.dump(final_data, f, indent=2)

    print(f"\n✅ Final output saved to: {FINAL_OUTPUT_JSON}")


if __name__ == '__main__':
    main()
