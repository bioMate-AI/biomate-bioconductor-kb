# Docker Image Optimization Opportunity

**Date:** 2026-01-22
**Status:** Documented for future implementation
**Priority:** Low (optimization, not required for functionality)

## Current State

### Image Size Comparison (ECR)

| Tool | x86 `:latest` | ARM64 `:arm64` | Difference |
|------|---------------|----------------|------------|
| boltz | 7,686 MB | 1,875 MB | **-75%** |
| chai1 | 7,805 MB | 1,906 MB | **-75%** |
| drugclip | 420 MB | 1,756 MB | +318%* |
| profam | 3,799 MB | 1,913 MB | **-50%** |
| protrek | 3,664 MB | 1,715 MB | **-53%** |
| scfv-pmpnn | 3,753 MB | 1,809 MB | **-52%** |
| state | 3,834 MB | 1,859 MB | **-52%** |

*drugclip x86 uses CPU-only `python:slim` base; ARM64 includes CUDA/PyTorch for GPU support.

### Root Cause: Different Base Images

**x86 Dockerfiles use:**
```dockerfile
FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime  # ~3.6 GB base
```

**ARM64 Dockerfiles use:**
```dockerfile
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04  # ~400 MB base
```

The `pytorch/pytorch` base image includes:
- Full Conda environment (~1.5 GB)
- Pre-installed PyTorch with all CUDA/cuDNN variants
- Many unnecessary Python packages
- Build tools and headers

The `nvidia/cuda` runtime image is minimal:
- Only CUDA runtime libraries needed for inference
- No Conda, no build tools
- We install only required packages via pip

## Proposed Optimization

Update x86 Dockerfiles to use the same minimal approach as ARM64.

### Before (current x86)
```dockerfile
FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

# Installs additional packages on top of bloated base
RUN pip install --no-cache-dir boltz==2.2.1
```

### After (optimized x86)
```dockerfile
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-dev git cmake build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install PyTorch and tool
RUN pip install --no-cache-dir torch==2.5.1 boltz==2.2.1
```

### Expected Results After Optimization

| Tool | Current x86 | Optimized x86 | Savings |
|------|-------------|---------------|---------|
| boltz | 7,686 MB | ~2,000 MB | ~5.7 GB |
| chai1 | 7,805 MB | ~2,000 MB | ~5.8 GB |
| profam | 3,799 MB | ~2,000 MB | ~1.8 GB |
| protrek | 3,664 MB | ~1,800 MB | ~1.9 GB |
| scfv-pmpnn | 3,753 MB | ~1,900 MB | ~1.9 GB |
| state | 3,834 MB | ~1,900 MB | ~1.9 GB |

**Total estimated savings: ~19 GB across all images**

## Benefits

1. **Faster deployments** - Smaller images pull faster from ECR
2. **Reduced storage costs** - Less ECR storage usage
3. **Consistency** - Same base image approach for x86 and ARM64
4. **Easier maintenance** - Single pattern to maintain
5. **Better caching** - Shared base layers across tools

## Implementation Steps

1. Update each x86 Dockerfile to use `nvidia/cuda:12.4.1-runtime-ubuntu22.04`
2. Add necessary apt packages (python3, pip, cmake, build-essential, etc.)
3. Install PyTorch via pip instead of relying on base image
4. Test each image locally
5. Rebuild and push to ECR with new `:latest` tag
6. Verify functionality on x86 GPU machines

## Files to Modify

```
backend/docker/biomate-ai-tools/
├── boltz/Dockerfile
├── chai1/Dockerfile
├── profam/Dockerfile
├── protrek/Dockerfile
├── scfv-pmpnn/Dockerfile
└── state/Dockerfile
```

Note: `drugclip/Dockerfile` uses `python:slim` for CPU-only mode. Consider whether GPU support is needed for x86 drugclip.

## Risk Assessment

- **Low risk** - ARM64 images already validated with this approach
- **Rollback** - Keep old images tagged as `:latest-legacy` if needed
- **Testing required** - Verify CUDA/GPU functionality after migration

## Decision

Deferred for later implementation. Current x86 images work correctly; this is a size/performance optimization only.

---

*Document created: 2026-01-22*
*Author: Claude Code assistant*
