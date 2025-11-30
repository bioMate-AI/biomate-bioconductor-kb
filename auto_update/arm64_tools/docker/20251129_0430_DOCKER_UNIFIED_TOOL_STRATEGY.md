# Docker as Unified Tool Strategy for ARM64

**Date:** November 29, 2025, 04:30
**Status:** Architecture Decision

---

## Decision

**Docker is the unified solution for all bioinformatics tools on ARM64.**

### Why Docker?

| Requirement | Docker Solution |
|-------------|-----------------|
| Prepare once, run anywhere | Build image once, push to registry, pull on any ARM64 machine |
| Handle different install methods | Docker abstracts pip, conda, compile, prebuilt - all same to user |
| No dependency conflicts | Each tool isolated in container |
| Portable across machines | Same image works on any ARM64 host with Docker |

---

## Architecture

### Modular Image Strategy

```
Registry: biomate/
├── base:arm64              # Ubuntu 22.04 + common dependencies
├── samtools:arm64          # HTSlib + samtools + bcftools
├── mmseqs2:arm64           # MMseqs2 (compiled with Rust)
├── foldseek:arm64          # Foldseek (compiled with Rust)
├── seqkit:arm64            # SeqKit (pre-built Go binary)
├── rush:arm64              # Rush (pre-built Go binary)
└── biotools:arm64          # All-in-one combined image
```

### Database Schema

Simple addition to tools table:

```sql
-- Add docker image reference
ALTER TABLE tools ADD COLUMN docker_image TEXT;

-- Examples
UPDATE tools SET docker_image = 'biomate/seqkit:arm64' WHERE tool_id LIKE '%seqkit%';
UPDATE tools SET docker_image = 'biomate/samtools:arm64' WHERE tool_id LIKE '%samtools%';
UPDATE tools SET docker_image = 'biomate/mmseqs2:arm64' WHERE tool_id LIKE '%mmseqs%';
UPDATE tools SET docker_image = 'biomate/foldseek:arm64' WHERE tool_id LIKE '%foldseek%';
```

---

## Handling New Tools

### When a new tool is needed:

1. **Check registry** - Does `biomate/newtool:arm64` exist?
2. **If yes** - Pull and use
3. **If no** - Build new image using stored install instructions

### Install Instructions Table

```sql
CREATE TABLE tool_docker_build (
    tool_id TEXT PRIMARY KEY,
    base_image TEXT DEFAULT 'ubuntu:22.04',
    install_method TEXT,  -- 'prebuilt', 'pip', 'conda', 'compile', 'apt'
    install_commands TEXT,  -- Shell commands to install
    entrypoint TEXT,  -- Default entrypoint
    test_command TEXT  -- Command to verify installation
);

-- Examples:
INSERT INTO tool_docker_build VALUES (
    'seqkit', 'ubuntu:22.04', 'prebuilt',
    'apt-get update && apt-get install -y wget ca-certificates && wget -q https://github.com/shenwei356/seqkit/releases/download/v2.8.2/seqkit_linux_arm64.tar.gz && tar xzf seqkit_linux_arm64.tar.gz && mv seqkit /usr/local/bin/',
    'seqkit', 'seqkit version'
);

INSERT INTO tool_docker_build VALUES (
    'cutadapt', 'python:3.11-slim', 'pip',
    'pip install cutadapt',
    'cutadapt', 'cutadapt --version'
);

INSERT INTO tool_docker_build VALUES (
    'samtools', 'ubuntu:22.04', 'compile',
    'apt-get update && apt-get install -y build-essential autoconf zlib1g-dev libcurl4-openssl-dev git && git clone --depth 1 --branch 1.21 https://github.com/samtools/htslib.git && cd htslib && autoreconf -i && ./configure --disable-bz2 --disable-lzma && make -j4 && make install && cd .. && git clone --depth 1 --branch 1.21 https://github.com/samtools/samtools.git && cd samtools && autoheader && autoconf && ./configure --without-curses && make -j4 && make install',
    'samtools', 'samtools --version'
);

INSERT INTO tool_docker_build VALUES (
    'mmseqs2', 'ubuntu:22.04', 'compile',
    'apt-get update && apt-get install -y build-essential cmake git curl zlib1g-dev libbz2-dev && curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && . ~/.cargo/env && git clone --depth 1 https://github.com/soedinglab/MMseqs2.git && cd MMseqs2 && mkdir build && cd build && cmake -DCMAKE_BUILD_TYPE=Release -DHAVE_ARM8=1 .. && make -j4 && make install',
    'mmseqs', 'mmseqs version'
);
```

---

## Auto-Build System

```python
import subprocess
import sqlite3

class DockerToolManager:
    """Manage Docker images for bioinformatics tools."""

    def __init__(self, db_path: str, registry: str = "biomate"):
        self.db = sqlite3.connect(db_path)
        self.registry = registry

    def get_image_name(self, tool_id: str, arch: str = "arm64") -> str:
        return f"{self.registry}/{tool_id}:{arch}"

    def image_exists_locally(self, image_name: str) -> bool:
        result = subprocess.run(
            ["docker", "images", "-q", image_name],
            capture_output=True, text=True
        )
        return bool(result.stdout.strip())

    def pull_image(self, image_name: str) -> bool:
        try:
            subprocess.run(["docker", "pull", image_name], check=True)
            return True
        except subprocess.CalledProcessError:
            return False

    def generate_dockerfile(self, tool_id: str) -> str:
        cursor = self.db.execute(
            "SELECT base_image, install_commands, entrypoint FROM tool_docker_build WHERE tool_id = ?",
            [tool_id]
        )
        row = cursor.fetchone()

        if not row:
            raise ValueError(f"No build instructions for tool: {tool_id}")

        base_image, install_commands, entrypoint = row

        return f"""FROM {base_image}
ENV DEBIAN_FRONTEND=noninteractive
RUN {install_commands}
ENTRYPOINT ["{entrypoint}"]
CMD ["--help"]
"""

    def build_image(self, tool_id: str, arch: str = "arm64") -> str:
        image_name = self.get_image_name(tool_id, arch)
        dockerfile_content = self.generate_dockerfile(tool_id)

        # Write temporary Dockerfile
        dockerfile_path = f"/tmp/Dockerfile.{tool_id}"
        with open(dockerfile_path, "w") as f:
            f.write(dockerfile_content)

        # Build image
        subprocess.run([
            "docker", "build",
            "--platform", f"linux/{arch}",
            "-t", image_name,
            "-f", dockerfile_path,
            "/tmp"
        ], check=True)

        return image_name

    def ensure_tool_available(self, tool_id: str, arch: str = "arm64") -> str:
        """Ensure tool image is available, building if necessary."""

        image_name = self.get_image_name(tool_id, arch)

        # 1. Check local
        if self.image_exists_locally(image_name):
            return image_name

        # 2. Try pull from registry
        if self.pull_image(image_name):
            return image_name

        # 3. Build new image
        return self.build_image(tool_id, arch)

    def run_tool(self, tool_id: str, args: list, input_dir: str = None, output_dir: str = None):
        """Run a tool in its Docker container."""

        image_name = self.ensure_tool_available(tool_id)

        cmd = ["docker", "run", "--rm", "--platform", "linux/arm64"]

        if input_dir:
            cmd.extend(["-v", f"{input_dir}:/input"])
        if output_dir:
            cmd.extend(["-v", f"{output_dir}:/output"])

        cmd.append(image_name)
        cmd.extend(args)

        return subprocess.run(cmd, capture_output=True, text=True)
```

---

## Usage Examples

### Command Line
```bash
# Run seqkit
docker run --rm -v $PWD:/data biomate/seqkit:arm64 stats /data/sequences.fasta

# Run samtools
docker run --rm -v $PWD:/data biomate/samtools:arm64 view -bS /data/input.sam

# Run mmseqs2
docker run --rm -v $PWD:/data biomate/mmseqs2:arm64 easy-search /data/query.fasta /data/target.fasta /data/results.tsv /data/tmp
```

### Python API
```python
manager = DockerToolManager("galaxy_ai_tools.db")

# Automatically pulls/builds if needed
result = manager.run_tool("seqkit", ["stats", "/input/sequences.fasta"], input_dir="/data")
print(result.stdout)
```

---

## Workflow Integration

When workflow generator creates a workflow:

1. Parse required tools from workflow
2. For each tool, call `ensure_tool_available(tool_id)`
3. Execute workflow steps using Docker containers
4. Mount input/output directories appropriately

```python
def execute_workflow(workflow: dict, input_dir: str, output_dir: str):
    manager = DockerToolManager("galaxy_ai_tools.db")

    for step in workflow["steps"]:
        tool_id = step["tool_id"]
        args = step["arguments"]

        # Ensure tool is available (pulls or builds if needed)
        manager.ensure_tool_available(tool_id)

        # Run the step
        result = manager.run_tool(tool_id, args, input_dir, output_dir)

        if result.returncode != 0:
            raise RuntimeError(f"Step failed: {result.stderr}")
```

---

## Current Status

### Built Images (ARM64)

| Image | Size | Status |
|-------|------|--------|
| biomate/seqkit:arm64 | 91MB | Ready |
| biomate/rush:arm64 | 80MB | Ready |
| biomate/samtools:arm64 | ~100MB | Building |
| biomate/mmseqs2:arm64 | ~150MB | Building |
| biomate/foldseek:arm64 | ~180MB | Building |

### Files

```
/home/yzhang/biomate/auto_update/arm64_tools/docker/
├── Dockerfile.seqkit
├── Dockerfile.rush
├── Dockerfile.samtools
├── Dockerfile.mmseqs2
├── Dockerfile.foldseek
├── Dockerfile.biotools
├── build-all.sh
└── 20251129_0430_DOCKER_UNIFIED_TOOL_STRATEGY.md
```

---

## Summary

1. **Docker = Unified Solution** - All tools packaged as Docker images
2. **Modular Images** - One image per tool for flexibility
3. **Auto-Build** - Generate Dockerfiles from database when new tools needed
4. **Simple Schema** - Just add `docker_image` column to tools table
5. **Portable** - Build once, run on any ARM64 machine with Docker
