#!/usr/bin/env python3
"""
ProTrek CLI Embedding Tool
Generates protein embeddings from FASTA files.
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
    parser = argparse.ArgumentParser(description="ProTrek protein embedding CLI")
    parser.add_argument("--input", required=True, help="Input FASTA file")
    parser.add_argument("--type", choices=["sequence", "structure", "text"], default="sequence",
                        help="Input modality type (default: sequence)")
    parser.add_argument("--model_dir", default=os.environ.get("PROTREK_MODEL", "/models/protrek"),
                        help="Path to ProTrek model directory")
    parser.add_argument("--output", required=True, help="Output file (.pt for tensor or .json for JSON)")
    parser.add_argument("--batch_size", type=int, default=32, help="Batch size for embedding generation")
    return parser.parse_args()


def load_fasta(fasta_path):
    """Parse FASTA file and return list of (id, sequence) tuples."""
    sequences = []
    current_id = None
    current_seq = []

    with open(fasta_path) as f:
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if current_id is not None:
                    sequences.append((current_id, "".join(current_seq)))
                current_id = line[1:].split()[0]
                current_seq = []
            elif line:
                current_seq.append(line)

    if current_id is not None:
        sequences.append((current_id, "".join(current_seq)))

    return sequences


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


def main():
    args = parse_args()

    print(f"[ProTrek] Loading sequences from {args.input}", file=sys.stderr)
    sequences = load_fasta(args.input)
    print(f"[ProTrek] Loaded {len(sequences)} sequences", file=sys.stderr)

    model, device = load_model(args.model_dir)

    modality = args.type.replace("sequence", "protein")
    all_embeddings = []
    all_ids = []

    for i in range(0, len(sequences), args.batch_size):
        batch = sequences[i:i + args.batch_size]
        batch_ids = [s[0] for s in batch]
        batch_seqs = [s[1] for s in batch]

        with torch.no_grad():
            embeddings = getattr(model, f"get_{modality}_repr")(batch_seqs)
            all_embeddings.append(embeddings.cpu())
            all_ids.extend(batch_ids)

        print(f"[ProTrek] Processed {min(i + args.batch_size, len(sequences))}/{len(sequences)}", file=sys.stderr)

    all_embeddings = torch.cat(all_embeddings, dim=0)
    print(f"[ProTrek] Embedding shape: {all_embeddings.shape}", file=sys.stderr)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)

    if args.output.endswith(".pt"):
        torch.save({"ids": all_ids, "embeddings": all_embeddings}, args.output)
    else:
        # Save as JSON (less efficient but portable)
        output_data = {
            "ids": all_ids,
            "embeddings": all_embeddings.numpy().tolist(),
        }
        with open(args.output, "w") as f:
            json.dump(output_data, f)

    print(f"[ProTrek] Embeddings saved to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
