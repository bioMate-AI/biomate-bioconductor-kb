# Nextflow Biomni Workflow Testing Documentation

**Test Date:** 2026-01-23
**Docker Image:** biomate/biomni-tools:latest
**Nextflow Version:** 25.10.0
**Total Workflows:** 237

## Overview

This document records the testing of Nextflow workflows generated from Galaxy Biomni tools.
The workflows are designed to call functions from the `biomni.tool` Python module.

## Test Environment

- **Container:** biomate/biomni-tools:latest
- **Python Path:** /usr/bin/python3
- **Biomni Module:** /opt/biomni/src/biomni/

## Verified Working Workflows

### 1. molecular_biology/design_primer.nf ✅

**Command:**
```bash
nextflow run subworkflows/molecular_biology/design_primer.nf \
  --sequence "ATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCG" \
  --start_pos 10 \
  -with-docker biomate/biomni-tools:latest
```

**Output:**
```json
{
  "sequence": "CGATCGATCGATCGATCGAT",
  "position": 10,
  "gc": 0.5,
  "tm": 60.0,
  "score": 0.0
}
```

## Available Functions by Domain

The following functions are available in the biomni module and have corresponding workflows:

