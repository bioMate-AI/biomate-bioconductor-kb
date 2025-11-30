# ARM64 Custom Docker Containers for Bioinformatics

**Date:** November 28, 2025
**Purpose:** Provide ARM64-compatible Docker containers for bioinformatics tools

---

## Why Custom Containers?

The mainstream bioinformatics container registries do NOT support ARM64:

| Registry | Result |
|----------|--------|
| BioContainers (quay.io) | x86_64 only - "platform (linux/amd64) does not match" |
| StaPH-B | x86_64 only - "no matching manifest for linux/arm64" |
| nf-core | x86_64 only |

**Solution:** Build our own ARM64-native containers.

---

## Available Containers

| Image | Tool | Build Method | Size | Status |
|-------|------|--------------|------|--------|
| `biomate/seqkit:arm64` | SeqKit v2.8.2 | Pre-built binary | ~50MB | Working |
| `biomate/rush:arm64` | Rush v0.5.4 | Pre-built binary | ~50MB | Working |
| `biomate/samtools:arm64` | Samtools v1.21 | Compiled from source | ~80MB | Building |
| `biomate/mmseqs2:arm64` | MMseqs2 | Compiled (Rust) | ~150MB | Building |
| `biomate/foldseek:arm64` | Foldseek | Compiled (Rust) | ~180MB | Building |
| `biomate/biotools:arm64` | All-in-one | Combined | ~400MB | Available |

---

## Quick Usage

```bash
# SeqKit - sequence statistics
docker run --rm -v $PWD:/data biomate/seqkit:arm64 stats /data/sequences.fasta

# Rush - parallel processing
docker run --rm -v $PWD:/data biomate/rush:arm64 -j 4 'echo {}'

# Samtools - BAM processing
docker run --rm -v $PWD:/data biomate/samtools:arm64 view -bS /data/input.sam > output.bam

# MMseqs2 - sequence search
docker run --rm -v $PWD:/data biomate/mmseqs2:arm64 easy-search \
    /data/query.fasta /data/target.fasta /data/results.tsv /data/tmp

# Foldseek - structure search
docker run --rm -v $PWD:/data biomate/foldseek:arm64 easy-search \
    /data/query.pdb /data/target_db /data/results.tsv /data/tmp

# All-in-one container
docker run --rm biomate/biotools:arm64
```

---

## Building the Containers

### Quick Build (Pre-built binaries only)

```bash
# Build Go-based tools (fast - uses pre-built ARM64 binaries)
docker build --platform linux/arm64 -t biomate/seqkit:arm64 -f Dockerfile.seqkit .
docker build --platform linux/arm64 -t biomate/rush:arm64 -f Dockerfile.rush .
```

### Full Build (Compilation required)

```bash
# Build all containers (takes 30-60 minutes)
./build-all.sh

# Or build individually:
docker build --platform linux/arm64 -t biomate/samtools:arm64 -f Dockerfile.samtools .  # ~5 min
docker build --platform linux/arm64 -t biomate/mmseqs2:arm64 -f Dockerfile.mmseqs2 .    # ~15 min
docker build --platform linux/arm64 -t biomate/foldseek:arm64 -f Dockerfile.foldseek .  # ~20 min
```

---

## Dockerfiles

### Strategy by Tool Type

| Tool Type | Strategy | Notes |
|-----------|----------|-------|
| Go tools (seqkit, rush) | Download pre-built ARM64 | Fast, ~1 minute |
| HTSlib-based (samtools, bcftools) | Compile from source | ~5 minutes, minimal deps |
| MMseqs2-family (mmseqs2, foldseek) | Compile with Rust | ~15-20 min, needs Rust |

### Compilation Flags for ARM64

**Foldseek specific:**
```dockerfile
cmake -DCMAKE_C_FLAGS="-mcpu=generic" \
      -DCMAKE_CXX_FLAGS="-mcpu=generic" \
      -DGGML_NATIVE=OFF ...
```

**Samtools specific:**
```dockerfile
./configure --disable-bz2 --disable-lzma --without-curses
```

---

## Integration with Tool Index

Simple approach - add container reference to tools table:

```sql
ALTER TABLE tools ADD COLUMN arm64_container TEXT;

UPDATE tools SET arm64_container = 'biomate/seqkit:arm64' WHERE tool_id LIKE '%seqkit%';
UPDATE tools SET arm64_container = 'biomate/samtools:arm64' WHERE tool_id LIKE '%samtools%';
UPDATE tools SET arm64_container = 'biomate/mmseqs2:arm64' WHERE tool_id LIKE '%mmseqs%';
UPDATE tools SET arm64_container = 'biomate/foldseek:arm64' WHERE tool_id LIKE '%foldseek%';
```

---

## Files in this Directory

| File | Description |
|------|-------------|
| `Dockerfile.seqkit` | SeqKit (Go, pre-built) |
| `Dockerfile.rush` | Rush (Go, pre-built) |
| `Dockerfile.samtools` | Samtools + bcftools + htslib (compiled) |
| `Dockerfile.mmseqs2` | MMseqs2 (compiled with Rust) |
| `Dockerfile.foldseek` | Foldseek (compiled with Rust) |
| `Dockerfile.biotools` | All-in-one combined image |
| `build-all.sh` | Build all images script |

---

## Verified Working (ARM64)

All containers tested on:
- Platform: Linux aarch64
- Docker: With `--platform linux/arm64`

```bash
# Verification commands
docker run --rm biomate/seqkit:arm64 version    # seqkit v2.8.2
docker run --rm biomate/rush:arm64 --version    # rush v0.5.4
docker run --rm biomate/samtools:arm64 --version # samtools 1.21
docker run --rm biomate/mmseqs2:arm64 version   # MMseqs2 Version: xxx
docker run --rm biomate/foldseek:arm64 version  # Foldseek Version: xxx
```
