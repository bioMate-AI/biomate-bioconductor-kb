"""
CLI entrypoint invoked inside the Nextflow training process.

The `chemprop_train.nf` wrapper runs:

    python -m galaxy.ai.ml_training.cli \
        --dataset <staged.csv|tdc:hERG|fixture:herg> \
        --target-col y --model-type chemprop_gnn --epochs 50 \
        --out results/

`build_config_from_args()` maps flat CLI args → TrainingConfig (pure, testable
without argparse side effects). `main()` runs the full training job and writes
`results/metrics.json` for the executor's step parser to pick up.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Optional, Sequence

from .config import TrainingConfig, DatasetSpec, Hyperparams


def _dataset_spec_from_arg(dataset: str, smiles_col: str, target_col: str,
                           split: str, val_frac: float, test_frac: float,
                           cv_folds: int = 5) -> DatasetSpec:
    """A dataset arg is an S3/local path when it looks like one, else a named shortcut."""
    kw = dict(smiles_col=smiles_col, target_col=target_col, split=split,
              val_frac=val_frac, test_frac=test_frac, cv_folds=cv_folds)
    if dataset.startswith("s3://"):
        return DatasetSpec(s3_uri=dataset, **kw)
    if ":" in dataset and not dataset.endswith((".csv", ".tsv", ".sdf")):
        # tdc:hERG / fixture:herg
        return DatasetSpec(name=dataset, **kw)
    return DatasetSpec(path=dataset, **kw)


def build_config_from_args(args: argparse.Namespace) -> TrainingConfig:
    ds = _dataset_spec_from_arg(args.dataset, args.smiles_col, args.target_col,
                                args.split, args.val_frac, args.test_frac,
                                cv_folds=getattr(args, "cv_folds", 5))
    hp = Hyperparams(
        epochs=args.epochs, batch_size=args.batch_size, depth=args.depth,
        hidden_size=args.hidden_size, dropout=args.dropout,
        learning_rate=args.learning_rate, ensemble_size=args.ensemble_size, seed=args.seed,
    )
    llm = None
    diffusion = None
    sc = None
    tabular = None
    from .config import LLM_MODEL_TYPES
    if args.model_type in LLM_MODEL_TYPES:
        from .config import LLMSpec
        llm = LLMSpec(base_model=args.base_model, instruction_col=args.instruction_col,
                      output_col=args.output_col, max_sequence_length=args.max_sequence_length,
                      adapter=args.adapter, beta=args.beta,
                      num_generations=args.num_generations, reward=args.reward,
                      reward_keyword=args.reward_keyword)
        # LLM/RL uses text-generation + random split regardless of molecular defaults.
        if args.task_type == "classification":
            args.task_type = "text_generation"
        ds.split = "random"
    elif args.model_type == "protein_diffusion":
        from .config import DiffusionSpec
        diffusion = DiffusionSpec(
            framework=args.framework, base_checkpoint=args.base_checkpoint,
            finetune=args.finetune, target_pdb=args.target_pdb,
            hotspot_residues=args.hotspot_residues, motif_pdb=args.motif_pdb,
            contig=args.contig, length_min=args.length_min, length_max=args.length_max,
            num_designs=args.num_designs, diffusion_steps=args.diffusion_steps,
            noise_schedule=args.noise_schedule)
        # Structure generation uses the structure_generation task regardless of
        # the molecular default.
        if args.task_type == "classification":
            args.task_type = "structure_generation"
    elif args.model_type == "scrna_diffusion":
        from .config import SCDiffusionSpec
        sc = SCDiffusionSpec(
            framework=args.sc_framework, base_checkpoint=args.sc_base_checkpoint,
            base_model=args.sc_base_model, finetune=args.sc_finetune,
            cell_type=args.sc_cell_type, condition_label=args.sc_condition_label,
            n_cells_to_generate=args.sc_n_cells_to_generate, n_genes=args.sc_n_genes,
            guidance_scale=args.sc_guidance_scale, diffusion_steps=args.sc_diffusion_steps,
            noise_schedule=args.sc_noise_schedule,
        )
        # scrna_diffusion always uses expression_generation + random split.
        if args.task_type == "classification":
            args.task_type = "expression_generation"
        ds.split = "random"
    elif args.model_type == "tabular_diffusion":
        from .config import TabularDiffusionSpec
        tabular = TabularDiffusionSpec(
            framework=args.tab_framework, base_checkpoint=args.tab_base_checkpoint,
            finetune=args.tab_finetune, target_column=args.tab_target_column,
            n_rows_to_generate=args.tab_n_rows_to_generate,
            guidance_scale=args.tab_guidance_scale,
            diffusion_steps=args.tab_diffusion_steps,
            noise_schedule=args.tab_noise_schedule,
        )
        # tabular_diffusion always uses tabular_generation + random split.
        if args.task_type == "classification":
            args.task_type = "tabular_generation"
        ds.split = "random"
    return TrainingConfig(
        name=args.model_name, task_type=args.task_type, model_type=args.model_type,
        featurizer=args.featurizer, dataset=ds, hyperparams=hp,
        mlflow_experiment=args.mlflow_experiment, campaign_id=args.campaign_id,
        metric=args.metric, gate_threshold=args.gate_threshold, llm=llm,
        diffusion=diffusion, sc=sc, tabular=tabular,
    ).validate()


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="ml_training", description="Train a molecular model")
    p.add_argument("--dataset", required=True)
    p.add_argument("--smiles-col", default="smiles", dest="smiles_col")
    p.add_argument("--target-col", default="y", dest="target_col")
    p.add_argument("--split", default="scaffold")
    p.add_argument("--cv-folds", type=int, default=5, dest="cv_folds",
                   help="k for split=kfold (generic tabular cross-validation)")
    p.add_argument("--val-frac", type=float, default=0.1, dest="val_frac")
    p.add_argument("--test-frac", type=float, default=0.1, dest="test_frac")
    p.add_argument("--model-name", default="molecular-model", dest="model_name")
    p.add_argument("--model-type", default="chemprop_gnn", dest="model_type")
    p.add_argument("--task-type", default="classification", dest="task_type")
    p.add_argument("--featurizer", default="rdkit_2d")
    p.add_argument("--epochs", type=int, default=50)
    p.add_argument("--batch-size", type=int, default=50, dest="batch_size")
    p.add_argument("--depth", type=int, default=3)
    p.add_argument("--hidden-size", type=int, default=300, dest="hidden_size")
    p.add_argument("--dropout", type=float, default=0.0)
    p.add_argument("--learning-rate", type=float, default=1e-3, dest="learning_rate")
    p.add_argument("--ensemble-size", type=int, default=1, dest="ensemble_size")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--metric", default="auc")
    p.add_argument("--gate-threshold", type=float, default=None, dest="gate_threshold")
    # LLM fine-tuning (model-type=ludwig_llm)
    p.add_argument("--base-model", default="HuggingFaceTB/SmolLM2-135M-Instruct", dest="base_model")
    p.add_argument("--instruction-col", default="instruction", dest="instruction_col")
    p.add_argument("--output-col", default="output", dest="output_col")
    p.add_argument("--adapter", default="qlora")
    p.add_argument("--max-sequence-length", type=int, default=256, dest="max_sequence_length")
    # Preference optimization (trl_dpo) / RL (trl_grpo)
    p.add_argument("--beta", type=float, default=0.1, help="DPO KL beta")
    p.add_argument("--num-generations", type=int, default=4, dest="num_generations",
                   help="GRPO samples per prompt")
    p.add_argument("--reward", default="length", help="GRPO reward: length|keyword|numeric_answer")
    p.add_argument("--reward-keyword", default="", dest="reward_keyword",
                   help="keyword for --reward keyword")
    # Protein/peptide structure diffusion (model-type=protein_diffusion)
    p.add_argument("--framework", default="rfdiffusion",
                   help="diffusion framework: rfdiffusion|chroma|genie")
    p.add_argument("--base-checkpoint", default="rfdiffusion/Base_ckpt.pt", dest="base_checkpoint",
                   help="warm-start checkpoint for fine-tuning")
    p.add_argument("--finetune", dest="finetune", action="store_true", default=True,
                   help="fine-tune a checkpoint (default)")
    p.add_argument("--from-scratch", dest="finetune", action="store_false",
                   help="train the diffusion model from scratch")
    p.add_argument("--target-pdb", default="", dest="target_pdb",
                   help="target/receptor PDB for binder design")
    p.add_argument("--hotspot-residues", default="", dest="hotspot_residues",
                   help="target hotspot residues, e.g. A30,A33,A34")
    p.add_argument("--motif-pdb", default="", dest="motif_pdb", help="scaffolding motif PDB")
    p.add_argument("--contig", default="", help="RFdiffusion contig/scaffold spec")
    p.add_argument("--length-min", type=int, default=60, dest="length_min")
    p.add_argument("--length-max", type=int, default=100, dest="length_max")
    p.add_argument("--num-designs", type=int, default=8, dest="num_designs")
    p.add_argument("--diffusion-steps", type=int, default=50, dest="diffusion_steps")
    p.add_argument("--noise-schedule", default="linear", dest="noise_schedule",
                   help="linear|cosine")
    # Single-cell expression diffusion (model-type=scrna_diffusion)
    p.add_argument("--sc-framework", default="scdiffusion", dest="sc_framework",
                   help="scdiffusion|cfgen")
    p.add_argument("--sc-base-checkpoint", default="", dest="sc_base_checkpoint",
                   help="pretrained diffusion checkpoint for fine-tune warm-start")
    p.add_argument("--sc-base-model", default="", dest="sc_base_model",
                   help="pretrained autoencoder/foundation weight (e.g. SCimilarity)")
    p.add_argument("--sc-finetune", action=argparse.BooleanOptionalAction, default=True,
                   dest="sc_finetune", help="fine-tune a pretrained checkpoint vs. train-from-scratch")
    p.add_argument("--sc-cell-type", default="", dest="sc_cell_type",
                   help="obs cell type to condition generation on")
    p.add_argument("--sc-condition-label", default="", dest="sc_condition_label",
                   help="obs column for perturbation/condition conditioning")
    p.add_argument("--sc-n-cells-to-generate", type=int, default=1000,
                   dest="sc_n_cells_to_generate")
    p.add_argument("--sc-n-genes", type=int, default=0, dest="sc_n_genes",
                   help="0 = infer from the h5ad var axis")
    p.add_argument("--sc-guidance-scale", type=float, default=1.0, dest="sc_guidance_scale")
    p.add_argument("--sc-diffusion-steps", type=int, default=1000, dest="sc_diffusion_steps")
    p.add_argument("--sc-noise-schedule", default="cosine", dest="sc_noise_schedule",
                   help="cosine|linear|sqrt")
    # Generic tabular diffusion (model-type=tabular_diffusion)
    p.add_argument("--tab-framework", default="tabddpm", dest="tab_framework",
                   help="tabddpm|tabsyn")
    p.add_argument("--tab-base-checkpoint", default="", dest="tab_base_checkpoint",
                   help="pretrained diffusion checkpoint for fine-tune warm-start")
    p.add_argument("--tab-finetune", action=argparse.BooleanOptionalAction, default=True,
                   dest="tab_finetune", help="fine-tune a pretrained checkpoint vs. train-from-scratch")
    p.add_argument("--tab-target-column", default="", dest="tab_target_column",
                   help="categorical column to condition synthesis on ('' = unconditional)")
    p.add_argument("--tab-n-rows-to-generate", type=int, default=1000,
                   dest="tab_n_rows_to_generate")
    p.add_argument("--tab-guidance-scale", type=float, default=1.0, dest="tab_guidance_scale")
    p.add_argument("--tab-diffusion-steps", type=int, default=1000, dest="tab_diffusion_steps")
    p.add_argument("--tab-noise-schedule", default="cosine", dest="tab_noise_schedule",
                   help="cosine|linear|sqrt")
    p.add_argument("--mlflow-experiment", default="biomate-ml-training", dest="mlflow_experiment")
    p.add_argument("--campaign-id", default="default", dest="campaign_id")
    p.add_argument("--out", default="results", help="output dir for metrics.json + artifact")
    return p


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = _build_parser().parse_args(argv)
    cfg = build_config_from_args(args)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    # Imported here so `build_config_from_args` stays importable without the
    # training stack (keeps arg-mapping unit tests dependency-free).
    from .training_job import run_training_job
    result = run_training_job(cfg, artifact_dir=str(out / "artifact"))

    (out / "metrics.json").write_text(json.dumps(result.to_dict(), indent=2, default=str))
    print(json.dumps({"name": cfg.name, "metrics": result.training.metrics if result.training else {},
                      "gate_passed": result.gate.passed if result.gate else None}))
    return 0 if (result.gate is None or result.gate.passed) else 2


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
