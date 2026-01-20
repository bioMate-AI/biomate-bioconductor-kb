# Docker Container Routing Approach for Galaxy Tools

**Date:** 2026-01-19 15:38
**Status:** Documented - Ready for Implementation

---

## Summary

Galaxy can route different tools to specialized Docker containers using two approaches:
1. Per-tool container specification in tool XML
2. Tool destination mapping in `job_conf.yml`

---

## Current State

### Available Docker Images

| Image | Tag | Size | Purpose |
|-------|-----|------|---------|
| `biomate/biomni-tools` | latest | 6.5GB | Biomni Python functions |
| `biomate/biotools` | arm64 | 8-17GB | Default Galaxy tools |
| `biomate/singlecell` | x86 | 9.2GB | Single cell analysis (scanpy, etc.) |
| `biomate/rnaseq` | x86 | 10.1GB | RNA-seq pipeline tools |
| `biomate/cutandrun` | x86 | 6GB | CUT&RUN workflows |
| `biomate/wgs-wes` | x86 | 12.7GB | WGS/WES analysis |
| `biomate/interactive` | arm64 | 4-5GB | Interactive tools (Jupyter, etc.) |

### Current Configuration

```yaml
# job_conf.yml - Current
docker_default_container_id: biomate/biotools:arm64
```

Biomni tools override this via XML:
```xml
<requirements>
    <container type="docker">biomate/biomni-tools:latest</container>
</requirements>
```

---

## Approach 1: Per-Tool Container in XML (Currently Used)

**How it works:** Each tool XML specifies its required container.

**Example:** `/Biomni/biomni_galaxy/tools/biomni/molecular_biology/find_restriction_sites.xml`
```xml
<tool id="biomni_molecular_biology_find_restriction_sites" ...>
    <requirements>
        <container type="docker">biomate/biomni-tools:latest</container>
    </requirements>
    ...
</tool>
```

**Pros:**
- Container specification travels with the tool
- Clear dependency declaration
- Works without job_conf.yml changes

**Cons:**
- Must update each tool XML individually
- No centralized management

---

## Approach 2: Tool Destination Mapping in job_conf.yml

**How it works:** Define execution environments and map tools to them by ID pattern.

**Example Configuration:**

```yaml
runners:
  local:
    load: galaxy.jobs.runners.local:LocalJobRunner
    workers: 4

execution:
  default: docker_local

  environments:
    # Default environment
    docker_local:
      runner: local
      docker_enabled: true
      docker_auto_rm: true
      docker_net: host
      docker_set_user: $UID
      docker_default_container_id: biomate/biotools:arm64
      docker_volumes: $defaults

    # Biomni tools environment
    docker_biomni:
      runner: local
      docker_enabled: true
      docker_auto_rm: true
      docker_net: host
      docker_set_user: $UID
      docker_default_container_id: biomate/biomni-tools:latest
      docker_volumes: $defaults

    # Single-cell analysis environment
    docker_singlecell:
      runner: local
      docker_enabled: true
      docker_auto_rm: true
      docker_net: host
      docker_set_user: $UID
      docker_default_container_id: biomate/singlecell:x86
      docker_volumes: $defaults

    # RNA-seq environment
    docker_rnaseq:
      runner: local
      docker_enabled: true
      docker_auto_rm: true
      docker_net: host
      docker_set_user: $UID
      docker_default_container_id: biomate/rnaseq:x86
      docker_volumes: $defaults

    # WGS/WES environment
    docker_wgs:
      runner: local
      docker_enabled: true
      docker_auto_rm: true
      docker_net: host
      docker_set_user: $UID
      docker_default_container_id: biomate/wgs-wes:x86
      docker_volumes: $defaults

# Tool-to-destination mapping
tools:
  # Biomni tools → biomni container
  - id: biomni_.*
    environment: docker_biomni

  # Scanpy/single-cell tools → singlecell container
  - id: python_scanpy_.*
    environment: docker_singlecell
  - id: scanpy_.*
    environment: docker_singlecell
  - id: anndata_.*
    environment: docker_singlecell

  # RNA-seq tools → rnaseq container
  - id: hisat2
    environment: docker_rnaseq
  - id: star
    environment: docker_rnaseq
  - id: featurecounts
    environment: docker_rnaseq
  - id: htseq_count
    environment: docker_rnaseq
  - id: deseq2
    environment: docker_rnaseq
  - id: edger
    environment: docker_rnaseq
  - id: kallisto_.*
    environment: docker_rnaseq
  - id: salmon_.*
    environment: docker_rnaseq

  # WGS/WES tools → wgs container
  - id: bwa_.*
    environment: docker_wgs
  - id: gatk_.*
    environment: docker_wgs
  - id: picard_.*
    environment: docker_wgs
  - id: bcftools_.*
    environment: docker_wgs
  - id: samtools_.*
    environment: docker_wgs
  - id: freebayes
    environment: docker_wgs

limits:
  - type: registered_user_concurrent_jobs
    value: 4
  - type: anonymous_user_concurrent_jobs
    value: 1
```

**Pros:**
- Centralized container management
- Pattern matching for tool groups
- Easy to add/modify routing rules
- No tool XML changes needed

**Cons:**
- Tool XML container specs override job_conf.yml mapping
- Requires knowing tool ID patterns

---

## Recommendation

**Use hybrid approach:**

1. **Biomni tools**: Keep container spec in XML (already done)
   - Ensures `biomate/biomni-tools:latest` is always used

2. **Library wrapper tools** (scanpy, cv2, rdkit, etc.): Add to job_conf.yml
   - These don't have container specs in XML
   - Route to appropriate specialized containers

3. **Standard Galaxy tools**: Use default container
   - Falls back to `biomate/biotools:arm64`

---

## Implementation Steps

1. [ ] Update `job_conf.yml` with specialized environments
2. [ ] Add tool-to-destination mappings for library tools
3. [ ] Test routing with sample tools from each category
4. [ ] Verify container selection in Galaxy job logs

---

## Notes

- Tool XML `<container>` specification takes precedence over job_conf.yml
- Pattern matching uses regex (e.g., `biomni_.*` matches all Biomni tools)
- Consider ARM64 vs x86 architecture when selecting containers
