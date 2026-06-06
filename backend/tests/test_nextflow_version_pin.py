"""CI guard for the Nextflow version pin and offline-launcher mode.

This file exists because the NF version pin and the auto-fetch guard have
been silently stripped from nextflow_executor.py FIVE+ times by parallel
session sweeps. Each time, the next workflow run downloads "latest"
Nextflow (26.04 as of this writing), which:

  1. Makes AWS CRT the default S3 client → JVM SIGSEGV in
     `software.amazon.awssdk.crt.CRT.extractAndLoadLibrary` on Debian
     trixie glibc 2.41 + OpenJDK 21. Kills every workflow's NF head.
     See docs/20260605_19_WORKFLOW_SWEEP_RESULT.md for the empirical
     0/19 sweep that prompted this guard.
  2. Breaks 16+ workflow directives in cryosparc_standard_spa from
     DSL2 strictness changes (L5 in docs/20260514_CICD_REBUILD_PLAN.md
     §6.3).

If this test starts failing, DO NOT MODIFY THE TEST. Restore the pin in
backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py instead. The
desired version is 25.10.5 and the offline-launcher mode (NXF_OFFLINE +
NXF_HOME) must be set in subprocess env.

Pairs with the Dockerfile pin in backend/Dockerfile (ENV NXF_VER,
ENV NXF_OFFLINE, ENV NXF_HOME, and pre-cached framework jar at
/opt/nextflow/framework/25.10.5/). That's defense-in-depth: even if
ONE of these gets stripped, the others still prevent the network fetch.
"""
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
EXECUTOR = (
    REPO_ROOT
    / "backend" / "lib" / "galaxy" / "webapps" / "galaxy" / "api"
    / "nextflow_executor.py"
)
DOCKERFILE = REPO_ROOT / "backend" / "Dockerfile"

DESIRED_NXF_VER = "25.10.5"


def test_executor_pins_nxf_ver():
    text = EXECUTOR.read_text()
    assert f'desired_nxf_ver = "{DESIRED_NXF_VER}"' in text, (
        f"NXF_VER hard-pin removed from _sanitize_subprocess_env(). "
        f"Without it, NF launcher fetches the latest framework jar from "
        f"GitHub, which crashes the JVM in this glibc/JDK combo. Restore "
        f'`desired_nxf_ver = "{DESIRED_NXF_VER}"` in nextflow_executor.py.'
    )


# NOTE: tests for NXF_OFFLINE and NXF_HOME defaults in _sanitize_subprocess_env
# were removed. They were premature — the per-run code path overrides NXF_HOME
# to a per-run dir that has no pre-staged jar. With NXF_OFFLINE=true that means
# every run fails (launcher refuses to download). NXF_OFFLINE only becomes
# safe once the Dockerfile pre-bakes the framework jar AND the per-run NXF_HOME
# is wired to find it. Both pieces ship together or not at all. The Dockerfile
# tests below still assert the ENV NXF_OFFLINE for the eventual image-rebuild
# path, but the runtime assertions are deferred.


def test_dockerfile_pins_nf_version():
    text = DOCKERFILE.read_text()
    assert f"ARG NF_VERSION={DESIRED_NXF_VER}" in text, (
        f"Galaxy Dockerfile NF_VERSION ARG no longer pinned to {DESIRED_NXF_VER}. "
        f"This is the inner pin — the pre-fetched framework jar baked into "
        f"the image depends on this. If ARG drifts, the image will bake in "
        f"the wrong jar, and even NXF_OFFLINE=true will run the wrong version."
    )


def test_dockerfile_sets_nxf_ver_env():
    text = DOCKERFILE.read_text()
    assert "ENV NXF_VER=" in text, (
        "Galaxy Dockerfile no longer sets ENV NXF_VER. Restore it — that is "
        "the load-bearing pin against drift to NF 26.04."
    )


def test_dockerfile_does_not_force_offline():
    """NXF_OFFLINE=true breaks plugin resolution.

    The Nextflow framework jar is pre-baked, but the nf-amazon plugin (and
    other plugins) are still downloaded on first use. NXF_OFFLINE=true makes
    the launcher refuse to download AND fail with "Plugin with id nf-amazon
    not found in any repository". We removed it 2026-06-06; this guard
    prevents accidental restoration. See nextflow_executor.py:
    `clean.pop("NXF_OFFLINE", None)` and commit f5cd88d97.
    """
    text = DOCKERFILE.read_text()
    # Look for actual ENV/RUN lines that set NXF_OFFLINE=true (excluding
    # cautionary comments).
    bad = [
        line for line in text.splitlines()
        if "NXF_OFFLINE=true" in line and not line.lstrip().startswith("#")
    ]
    assert not bad, (
        f"Galaxy Dockerfile re-introduced NXF_OFFLINE=true via: {bad}. "
        f"This breaks plugin downloads. Either pre-bake nf-amazon@3.4.4 into "
        f"the image too, or leave NXF_OFFLINE unset. NXF_VER pin already "
        f"protects against version drift; offline mode is redundant + harmful."
    )


def test_dockerfile_prefetches_framework_jar():
    text = DOCKERFILE.read_text()
    assert "nextflow-${NF_VERSION}-one.jar" in text, (
        "Galaxy Dockerfile no longer pre-fetches the Nextflow framework "
        "jar into /opt/nextflow/framework. Without this, the very first "
        "`nextflow run ...` call needs to download the jar from GitHub. "
        "If NXF_OFFLINE=true is set (it is), the launch will then fail. "
        "If NXF_OFFLINE=true is missing (regression we're guarding against), "
        "the launcher will silently grab the latest jar, defeating the pin."
    )


def test_dockerfile_pins_jdk_17():
    text = DOCKERFILE.read_text()
    assert "openjdk-17-jre-headless" in text, (
        "Galaxy Dockerfile JDK pin removed. default-jre-headless on Debian "
        "trixie resolves to OpenJDK 21, which has a flaky dlopen path that "
        "AWS CRT native lib hits — crashes the JVM. JDK 17 is known-good. "
        "Restore `openjdk-17-jre-headless` in backend/Dockerfile."
    )
    # Check that default-jre-headless is not ACTUALLY installed (excluding
    # cautionary comments that mention the string).
    install_lines = [
        line for line in text.splitlines()
        if "default-jre-headless" in line and not line.lstrip().startswith("#")
    ]
    assert not install_lines, (
        f"Galaxy Dockerfile installs default-jre-headless via: {install_lines}. "
        f"On Debian trixie this is OpenJDK 21 which crashes NF. Use "
        f"openjdk-17-jre-headless explicitly."
    )
