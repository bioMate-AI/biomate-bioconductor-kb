# M6 proof — OM-TPS container + Batch ablation (turnkey recipe, reviewed, UNBUILT)

Status: **ready to build, not yet built.** The density-guidance code is validated locally (`test_density_guidance.py`,
all pass). This is the remaining path to the *scientific* proof (needs GPU + real spend).

## Why CodeBuild, not an EC2 builder
CloudTrail (2026-08-18) shows a sibling Claude session terminating EC2 instances via the shared `biomate-admin`
user (it killed an On-Demand `g5.xlarge` immune-LLM job mid-flight). An EC2 builder we launch could be terminated
mid-build the same way. **AWS CodeBuild is managed** — no long-lived EC2 instance for a sibling to `terminate-instances`.
Use CodeBuild to build + push, then submit the Batch job. (No local docker on this Mac, so a remote build is required
regardless.)

## Dockerfile (from OM-TPS README pins; fenics/MB-only deps omitted — protein run needs torch/mdtraj/openmm/pyEMMA)
```dockerfile
FROM nvidia/cuda:11.3.1-cudnn8-runtime-ubuntu20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget git ca-certificates build-essential && rm -rf /var/lib/apt/lists/*
# Miniconda + python 3.9 (OM-TPS is pinned to 3.9)
RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/mc.sh \
 && bash /tmp/mc.sh -b -p /opt/conda && rm /tmp/mc.sh
ENV PATH=/opt/conda/bin:$PATH
RUN conda create -y -n omtps python=3.9 && conda clean -a -y
SHELL ["conda","run","-n","omtps","/bin/bash","-c"]
# Pins straight from OM-TPS/README.md (revert numpy last — pyemma needs 1.21.2)
RUN pip install numpy==1.21.2 pandas==1.5.3 && \
    pip install torch==1.12.1+cu113 -f https://download.pytorch.org/whl/torch_stable.html && \
    pip install mdtraj==1.9.9 biopython==1.79 && \
    pip install wandb==0.18.7 dm-tree einops torchdiffeq fair-esm pyEMMA && \
    pip install ase torch-geometric rmsd tqdm gsd flow_matching ema-pytorch tensorboard moleculekit parmed && \
    pip install --no-deps torchmd==0.0.2 && \
    pip install matplotlib==3.7.2 numpy==1.21.2
# OpenMM for energy eval (README uses a separate env; try same-image first, split if it conflicts)
RUN conda install -y -c conda-forge openmm pdbfixer && conda clean -a -y
COPY OM-TPS /opt/OM-TPS
COPY m6_density_guidance/density_guidance.py /opt/OM-TPS/two-for-one-diffusion/density_guidance.py
WORKDIR /opt/OM-TPS/two-for-one-diffusion
```
> Known risks (expect 1–3 build iterations): torch 1.12+cu113 wheel availability; `torchmd==0.0.2 --no-deps`;
> moleculekit/openmm conda-vs-pip conflicts (README deliberately splits OpenMM into a 2nd env — if the combined
> image fails, build two envs and shell into `omtps` for sampling, `openmm-env` for energy eval).

## Build (CodeBuild) — one-time, reuse the ECR image forever
1. `aws ecr create-repository --repository-name biomate/ai-tools/om-tps --region us-west-2` (once).
2. CodeBuild project (Linux GPU or standard large image, privileged for docker): source = this repo subset
   (`research/OM-TPS` + `research/m6_density_guidance`), buildspec = docker build + `aws ecr get-login-password |
   docker login` + push to `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/om-tps:v1`.
3. Verify the pushed image runs: `docker run --rm ...:v1 conda run -n omtps python -c "import torch,mdtraj; print('ok')"`.

## Data staging (public, one-time → S3, no sister data)
- Alanine `Ala2Train.zip` and fast-folder `torch_trajectories.zip` are on Google Drive (README links). `gdown`
  them, unzip, `aws s3 cp` to `s3://biomate-nextflow-work/projects/omtps/datasets/`. Bundled model weights are in
  `saved_models/` already (real .pt, in-repo).

## Run the ablation (Batch GPU, On-Demand — NOT the SPOT CE `biomate-gpu-spot-v1`)
Two arms on a within-regime fast-folder (e.g. BBA/villin) — anchor OFF vs ON:
1. **Baseline (unconditioned)** — reproduce a bare path/rate: `sample.py --model_path saved_models/bba
   --gen_mode om_interpolate --atom_selection c-alpha --num_samples_eval 32 --action hutch ...` (README command).
2. **Guided (density ON)** — same, with `guided_action()` injecting a synthetic CA-space density built from a
   DESRES on-pathway *intermediate*; sweep λ (scaled to OM magnitude — see validation finding).
3. **Gate:** ON must move committor/rate toward the DESRES ground truth beyond seed noise (≥3 seeds/arm);
   endpoint-only shift = FAIL (reduction trap). See `docs/20260818_CRYODYNAMICS_M6_DESIGN_AND_ABLATION.md` §4.

## Spend estimate (order-of-magnitude)
CodeBuild build: minutes, ~cents. Batch: BBA is small (≤~80 aa, CA-CG), one g5/g4dn GPU; per arm minutes–~1 h;
3 seeds × 2 arms ≈ a few GPU-hours → **~$5–15** for the first real ablation. On-Demand (Spot risks mid-flight kill).

## Decision needed
This is the first real cloud spend of the M6 effort. Greenlight → I run CodeBuild build (safe from the sibling
terminate hazard), stage data, submit the On-Demand Batch ablation, and report the anchor ON/OFF result.
