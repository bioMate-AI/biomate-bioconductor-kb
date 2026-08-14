"""Static pre-execution check for user-uploaded Nextflow (.nf) source.

**Defense in depth, not the security boundary** — the container/gVisor
sandbox (command.py) is the boundary. This catches obvious escape attempts
early (clearer error, cheaper than a failed sandboxed run) and gives an
audit trail. It is intentionally conservative: heuristic regex rules, each
tagged ``block`` (deny when reject_on_violation) or ``warn`` (log only).

It must never *replace* the sandbox: a determined attacker can obfuscate
past regexes, which is exactly why the container is the real control.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import List, Pattern, Tuple


@dataclass
class Violation:
    rule: str
    severity: str      # "block" | "warn"
    line: int
    snippet: str
    message: str


# (rule_id, severity, compiled_pattern, human message)
def _c(p: str) -> Pattern:
    return re.compile(p, re.IGNORECASE)


_RULES: List[Tuple[str, str, Pattern, str]] = [
    # --- container-escape / privilege escalation -----------------------
    ("privileged_container", "block", _c(r"--privileged\b"),
     "container privileged mode requested"),
    ("host_root_mount", "block", _c(r"(-v|--volume|--mount)[=\s]+[\"']?/(:|\s|[\"'])"),
     "attempt to mount host root (/) into a container"),
    ("host_docker_socket", "block", _c(r"/var/run/docker\.sock"),
     "attempt to mount the host Docker socket (docker-in-docker escape)"),
    ("docker_in_process", "block", _c(r"\b(docker|podman|nerdctl)\s+run\b"),
     "spawning a container engine from inside a process (escape vector)"),
    ("nsenter_or_unshare", "block", _c(r"\b(nsenter|unshare|chroot)\b"),
     "namespace/chroot manipulation"),

    # --- cloud metadata / SSRF ----------------------------------------
    ("cloud_metadata_ip", "block", _c(r"169\.254\.169\.254"),
     "access to the cloud instance-metadata endpoint (credential theft)"),
    ("link_local_metadata", "block", _c(r"metadata\.google\.internal"),
     "access to GCP metadata server"),

    # --- credential / secret exfiltration -----------------------------
    ("read_shadow", "block", _c(r"/etc/(shadow|gshadow)\b"),
     "reading the host shadow password file"),
    ("read_aws_creds", "block", _c(r"~?/?\.aws/(credentials|config)\b"),
     "reading AWS credential files"),
    ("read_ssh_keys", "block", _c(r"\.ssh/(id_[a-z0-9]+|authorized_keys)\b"),
     "reading SSH private keys / authorized_keys"),
    ("env_secret_exfil", "warn", _c(r"\b(printenv|env)\b.*\|(.*(curl|wget|nc))"),
     "piping the environment to a network client"),

    # --- remote code execution via download|shell ---------------------
    ("curl_pipe_shell", "block", _c(r"\b(curl|wget)\b[^\n|]*\|\s*(sudo\s+)?(ba)?sh\b"),
     "curl|wget piped directly into a shell"),
    ("groovy_runtime_exec", "block", _c(r"Runtime\.getRuntime\(\)\.exec\b"),
     "Groovy Runtime.exec in the workflow head (host-side arbitrary exec)"),
    ("groovy_string_execute", "warn", _c(r"\"\"\"?[^\n]*\"\"\"?\.execute\(\)"),
     "Groovy String.execute() in the workflow head"),
    ("groovy_process_builder", "block", _c(r"\bProcessBuilder\b"),
     "Groovy ProcessBuilder in the workflow head"),

    # --- writes outside the work dir ----------------------------------
    ("write_system_path", "warn", _c(r"(>|>>|cp|mv|tee)\s+/(etc|bin|sbin|usr|boot|root)\b"),
     "writing to a system path outside the work directory"),
    ("sudo_usage", "warn", _c(r"\bsudo\b"),
     "sudo usage (no effect in a rootless sandbox, but flagged)"),
]


def validate_nextflow_source(text: str) -> List[Violation]:
    """Scan .nf source; return violations (empty = clean).

    Line-based so violations point at a location for the audit log. Comment
    lines (// and #) are skipped to cut false positives from documentation.
    """
    violations: List[Violation] = []
    if not text:
        return violations
    for i, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("//") or line.startswith("#"):
            continue
        for rule, severity, pat, msg in _RULES:
            if pat.search(raw):
                violations.append(
                    Violation(
                        rule=rule,
                        severity=severity,
                        line=i,
                        snippet=raw.strip()[:200],
                        message=msg,
                    )
                )
    return violations


def has_blocking(violations: List[Violation]) -> bool:
    return any(v.severity == "block" for v in violations)


def format_violations(violations: List[Violation]) -> str:
    """One-line-per-violation summary for logs / error responses."""
    return "; ".join(
        f"L{v.line} [{v.severity}] {v.rule}: {v.message}" for v in violations
    )
