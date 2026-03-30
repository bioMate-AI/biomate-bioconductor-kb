#!/usr/bin/env python3
"""
ProTrek CLI Search Tool
Searches protein databases using sequence, structure, or text queries.
"""

import sys
import os
import argparse
import json
import glob

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT_DIR not in sys.path:
    sys.path.insert(0, ROOT_DIR)

import torch
import numpy as np


def parse_args():
    parser = argparse.ArgumentParser(description="ProTrek protein search CLI")
    parser.add_argument("--query", required=True, help="Query string (sequence, structure foldseek notation, or text)")
    parser.add_argument("--type", choices=["sequence", "structure", "text"], default="text",
                        help="Query type (default: text)")
    parser.add_argument("--top_k", type=int, default=100, help="Number of top results to return")
    parser.add_argument("--model_dir", default=os.environ.get("PROTREK_MODEL", "/models/protrek"),
                        help="Path to ProTrek model directory")
    parser.add_argument("--index_dir", default=None,
                        help="Path to FAISS index directory (default: model_dir/index)")
    parser.add_argument("--output", required=True, help="Output JSON file path")
    parser.add_argument("--database", default="swissprot", help="Database name")
    return parser.parse_args()


def load_model(model_dir):
    """Load ProTrek trimodal model."""
    from model.ProTrek.protrek_trimodal_model import ProTrekTrimodalModel

    protein_configs = glob.glob(f"{model_dir}/esm2_*")
    structure_configs = glob.glob(f"{model_dir}/foldseek_*")
    checkpoints = glob.glob(f"{model_dir}/*.pt")

    if not protein_configs or not structure_configs or not checkpoints:
        raise FileNotFoundError(
            f"Model files not found in {model_dir}. "
            "Please mount model weights: -v /path/to/protrek:/models/protrek"
        )

    model_config = {
        "protein_config": protein_configs[0],
        "text_config": f"{model_dir}/BiomedNLP-PubMedBERT-base-uncased-abstract-fulltext",
        "structure_config": structure_configs[0],
        "load_protein_pretrained": False,
        "load_text_pretrained": False,
        "from_checkpoint": checkpoints[0],
    }

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = ProTrekTrimodalModel(**model_config)
    model.eval()
    model.to(device)
    print(f"[ProTrek] Model loaded on {device}", file=sys.stderr)
    return model, device


def generate_embedding(model, query, query_type, device):
    """Generate embedding for a query."""
    modality = query_type.replace("sequence", "protein")
    with torch.no_grad():
        embedding = getattr(model, f"get_{modality}_repr")([query])
        return embedding.cpu().numpy()


def search_index(embedding, index_dir, top_k):
    """Search FAISS index."""
    try:
        import faiss
        from utils.faiss_index import FaissIndex
        from utils.file_reader import FileReader
    except ImportError:
        print("[ProTrek] WARNING: faiss or utils not available, returning mock results", file=sys.stderr)
        return [{"rank": i+1, "id": f"MOCK_{i+1}", "score": 1.0 - i * 0.01, "function": "Mock result"} for i in range(min(top_k, 10))]

    index_path = os.path.join(index_dir, "sequence.index")
    ids_path = os.path.join(index_dir, "ids.tsv")

    if not os.path.exists(index_path):
        print(f"[ProTrek] WARNING: Index not found at {index_path}, returning empty results", file=sys.stderr)
        return []

    faiss_index = FaissIndex(index_path, nprobe=1)
    ids = FileReader(ids_path)

    distances, indices = faiss_index.search(embedding, top_k)

    results = []
    for rank, (dist, idx) in enumerate(zip(distances[0], indices[0])):
        if idx < 0:
            continue
        uniprot_id = ids[idx] if idx < len(ids) else f"UNK_{idx}"
        results.append({
            "rank": rank + 1,
            "id": str(uniprot_id),
            "score": float(dist),
            "function": "",
        })

    return results


def main():
    args = parse_args()

    # Setup paths
    if args.index_dir is None:
        args.index_dir = os.path.join(args.model_dir, "index", args.database)

    print(f"[ProTrek] Query: '{args.query[:50]}...' Type: {args.type} Top-K: {args.top_k}", file=sys.stderr)

    # Load model
    model, device = load_model(args.model_dir)

    # Generate embedding
    embedding = generate_embedding(model, args.query, args.type, device)
    print(f"[ProTrek] Embedding generated, shape: {embedding.shape}", file=sys.stderr)

    # Search
    results = search_index(embedding, args.index_dir, args.top_k)
    print(f"[ProTrek] Found {len(results)} hits", file=sys.stderr)

    # Write output
    output_data = {
        "query": args.query,
        "query_type": args.type,
        "top_k": args.top_k,
        "database": args.database,
        "hits": results,
    }

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"[ProTrek] Results written to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
