# Biomate AI Tools - Test Results

**Date:** 2026-01-22
**Platform:** ARM64 (NVIDIA GB10, CUDA 13.0 driver)

## Test Summary

| Tool | Container | Dependencies | GPU/CUDA | Status |
|------|-----------|--------------|----------|--------|
| ESMFold | N/A (API) | curl | N/A | ✅ PASS |
| AlphaFold DB | N/A (API) | curl | N/A | ✅ PASS |
| SynCraft | ✅ Works | Python | N/A (CPU) | ⚠️ Needs GEMINI_API_KEY |
| Boltz | ✅ Works | PyTorch 2.5.1 | ❌ CPU only | ⚠️ No CUDA |
| Chai-1 | ⚠️ Entrypoint | chai_lab 0.6.1 | ❌ CPU only | ⚠️ Fix entrypoint |
| DrugCLIP | ✅ Works | PyTorch, RDKit | ❌ CPU only | ⚠️ No CUDA |
| ProTrek | ✅ Works | PyTorch, transformers | ❌ CPU only | ⚠️ No CUDA |
| ProFam | ❌ Missing dep | Missing numba | ❌ CPU only | ❌ FAIL |
| scFv-pMPNN | ✅ Works | PyTorch, JAX | ❌ CPU only | ⚠️ No CUDA |
| STATE | ✅ Works | state CLI | ❌ CPU only | ⚠️ No CUDA |

## Critical Issues

### 1. ARM64 PyTorch Has No CUDA Support

**Problem:** `pip install torch` on ARM64 installs CPU-only version.

```
torch.version.cuda: None
torch.backends.cuda.is_built(): False
torch.cuda.is_available(): False
```

**Root Cause:** PyPI only has CPU wheels for ARM64. CUDA wheels require special installation.

**Solution Options:**

1. **Use NVIDIA NGC base image** (Recommended):
   ```dockerfile
   FROM nvcr.io/nvidia/pytorch:24.10-py3  # Has ARM64 + CUDA
   ```

2. **Install from NGC/conda**:
   ```bash
   pip install torch --index-url https://developer.download.nvidia.com/compute/redist/jp/v60
   ```

3. **Build from source** (complex)

### 2. ProFam Missing numba Dependency

**Error:**
```
ModuleNotFoundError: No module named 'numba'
```

**Fix:** Add to Dockerfile:
```dockerfile
RUN pip install numba
```

### 3. Chai-1 Entrypoint Issue

**Error:**
```
/entrypoint.sh: line 6: exec: chai: not found
```

**Fix:** chai_lab is a Python library, not CLI. Update entrypoint:
```dockerfile
ENTRYPOINT ["python3", "-m", "chai_lab"]
```

Or remove entrypoint and use:
```bash
docker run ... python3 -c "from chai_lab.chai1 import run_inference; ..."
```

## Detailed Test Results

### API-Based Tools (No Container Needed)

#### ESMFold API
```bash
curl -X POST --data "MVLSPADKTNVKAAWGKVGAHAGEYGAEALERMFLSFPTTKTYFPHFDLSH" \
    https://api.esmatlas.com/foldSequence/v1/pdb/
# Result: Valid PDB file returned ✅
```

#### AlphaFold DB API
```bash
curl "https://alphafold.ebi.ac.uk/api/prediction/P69905"
# Result: Entry AF-P69905-F1, pLDDT: 98.06 ✅
```

### Container Tests

#### Boltz
```
Container: ✅ Loads
CLI: ✅ boltz --help works
PyTorch: 2.5.1
CUDA: ❌ Not available (CPU-only torch)
```

#### STATE
```
Container: ✅ Loads
CLI: ✅ state --help works (emb, tx subcommands)
```

#### DrugCLIP
```
Container: ✅ Loads
PyTorch: 2.5.1
RDKit: 2025.09.3
CUDA: ❌ Not available
```

#### ProTrek
```
Container: ✅ Loads
PyTorch: 2.5.1
transformers: ✅ Installed
CUDA: ❌ Not available
```

#### scFv-pMPNN
```
Container: ✅ Loads
PyTorch: 2.5.1
JAX: 0.6.2
CUDA: ❌ Not available
```

## Recommended Fixes

### High Priority

1. **Rebuild ARM64 images with NVIDIA NGC base**:
   ```dockerfile
   # Replace:
   FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

   # With:
   FROM nvcr.io/nvidia/pytorch:24.10-py3
   ```

2. **Fix ProFam dependencies**:
   ```dockerfile
   RUN pip install numba llvmlite
   ```

3. **Fix Chai-1 entrypoint**:
   ```dockerfile
   ENTRYPOINT ["python3"]
   CMD ["-c", "from chai_lab.chai1 import run_inference; print('Ready')"]
   ```

### Medium Priority

4. Add integration tests with actual GPU workloads
5. Test model weight loading for each tool
6. Validate Nextflow pipeline execution

## Next Steps

1. Rebuild ARM64 images using NGC PyTorch base
2. Fix ProFam numba dependency
3. Fix Chai-1 entrypoint
4. Re-test GPU functionality
5. Run full pipeline tests with sample data
