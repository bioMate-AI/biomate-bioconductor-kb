#!/bin/bash
set -euo pipefail
cd /opt/biomate-trial
rm -f MODEL_READY
python3 -m venv venv
venv/bin/pip install --quiet --upgrade pip
venv/bin/pip install --quiet huggingface_hub boto3
# Replacements use the engine revision tested with this model, not upstream main.
llama_revision=3057bb66c86c46d5781e50e85462a760ba7d1feb
if [ ! -d llama.cpp/.git ]; then
  git init llama.cpp
  git -C llama.cpp remote add origin https://github.com/ggml-org/llama.cpp.git
fi
git -C llama.cpp fetch --depth 1 origin "$llama_revision"
git -C llama.cpp checkout --detach "$llama_revision"
git -C llama.cpp rev-parse HEAD > llama-source-revision.txt
cmake -S llama.cpp -B llama.cpp/build -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=OFF -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS
cmake --build llama.cpp/build --config Release -j 12 --target llama-server llama-quantize
venv/bin/python scripts/download_model.py --directory /opt/biomate-trial/base-model --bucket biomate-models-399683337364 --prefix biomate-core-local-trial/20260912
venv/bin/python scripts/check_model_size.py base-model > model-size-check.json
# CPU PyTorch prevents downloading an unused CUDA runtime for conversion.
venv/bin/pip install --quiet torch --index-url https://download.pytorch.org/whl/cpu
venv/bin/pip install --quiet -r llama.cpp/requirements.txt
venv/bin/pip freeze > python-environment.txt
venv/bin/python llama.cpp/convert_hf_to_gguf.py base-model --outfile model-bf16.partial.gguf --outtype bf16
mv model-bf16.partial.gguf model-bf16.gguf
llama.cpp/build/bin/llama-quantize model-bf16.gguf model-q4_k_m.partial.gguf Q4_K_M
mv model-q4_k_m.partial.gguf model-q4_k_m.gguf
printf 'MODEL_CONVERTED\n' > MODEL_READY
