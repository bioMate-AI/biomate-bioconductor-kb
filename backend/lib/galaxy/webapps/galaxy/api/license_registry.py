"""
License Registry — static metadata for tools that require registration/credentials.

Used by credentials_api.py to:
  1. Identify which tools appear in a .nf workflow file
  2. Know which env vars hold BioMate's master credentials (fallback for demo users)
  3. Serve display metadata to the frontend license gate
"""
import re
from pathlib import Path
from typing import Any, Dict, List

# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

LICENSE_REGISTRY: Dict[str, Dict[str, Any]] = {
    "alphafold3": {
        "display_name": "AlphaFold3",
        "vendor": "Google DeepMind / EBI",
        "type": "docker_auth",          # credential shape: {username, token}
        "registration_url": "https://alphafold.ebi.ac.uk/",
        "approval_time": "~1 day",
        "cost": "free (non-commercial)",
        # Strings to search for in .nf container directives
        "container_patterns": ["catgumag/alphafold3"],
        # BioMate master credential env vars
        "env_key_user": "ALPHAFOLD3_DOCKER_USER",
        "env_key_token": "ALPHAFOLD3_DOCKER_TOKEN",
        "open_alternatives": [
            {"id": "chai1",  "label": "Chai-1",  "note": "Open source (Apache 2.0), protein+ligand, no registration"},
            {"id": "boltz2", "label": "Boltz-2", "note": "MIT license, NVIDIA NIM API or local GPU"},
        ],
    },
    "boltz2": {
        "display_name": "Boltz-2",
        "vendor": "MIT / Boehringer Ingelheim (open weights); NVIDIA NIM (API)",
        "type": "api_key",              # credential shape: {api_key}
        "registration_url": "https://build.nvidia.com/boltz",
        "approval_time": "instant (NVIDIA developer account)",
        "cost": "free tier (1000 credits); ~$0.05–$0.10/call after",
        "container_patterns": ["boltz2", "boltz-2", "boltz_2"],
        # BioMate master NVIDIA NIM key (optional — falls back to local weights mode)
        "env_key": "NVIDIA_NIM_API_KEY",
        "open_alternatives": [],
    },
    "chai1": {
        "display_name": "Chai-1",
        "vendor": "Chai Discovery",
        "type": "none",                 # no credential required — Apache 2.0 open weights
        "registration_url": "https://github.com/chaidiscovery/chai-lab",
        "approval_time": "instant",
        "cost": "free (Apache 2.0)",
        "container_patterns": ["chai-lab", "chaidiscovery/chai"],
        "open_alternatives": [],
    },
    "cryosparc": {
        "display_name": "CryoSPARC",
        "vendor": "Structura Biotechnology",
        "type": "license_key",          # credential shape: {license_key}
        "registration_url": "https://cryosparc.com/download",
        "approval_time": "instant (academic) / contact sales (commercial)",
        "cost": "free (academic)",
        "container_patterns": ["cryosparc", "structura"],
        # Policy: each user must provide their own license key — BioMate's master
        # key is never used as a fallback.
        "user_must_provide": True,
        "env_key": "CRYOSPARC_LICENSE",
        "open_alternatives": [],
    },
    # ------------------------------------------------------------------
    # Phase 3: licensed MD / drug-discovery tools
    # ------------------------------------------------------------------
    "amber": {
        "display_name": "AMBER",
        "vendor": "University of California San Diego",
        "type": "license_agreement",    # no runtime key -- free academic since Amber24
        "registration_url": "https://ambermd.org/GetAmber.php",
        "approval_time": "instant (web form)",
        "cost": "free (academic/non-profit); $500–$2,000/yr commercial",
        "container_patterns": ["pmemd", "amber24", "ambertools", "amber-cuda"],
        # No env_key: BioMate ships pmemd in its ECR image; no user action needed
        "open_alternatives": [
            {"id": "openmm", "label": "OpenMM", "note": "Python API, GPU, free, slightly slower"},
            {"id": "gromacs", "label": "GROMACS", "note": "Free, HPC-optimized, wide FF support"},
        ],
    },
    "schrodinger": {
        "display_name": "Schrödinger Suite",
        "vendor": "Schrödinger, Inc.",
        "type": "license_server",       # credential shape: {license_server: "27008@host"}
        "registration_url": "https://www.schrodinger.com/contact/",
        "approval_time": "contact sales (days–weeks)",
        "cost": "~$100,000+/yr commercial (FEP+ suite); academic token licenses negotiated separately",
        "container_patterns": ["schrodinger", "schrödinger", "glide", "fep_plus"],
        # BioMate master: none -- cost prohibitive; users bring their own license
        "env_key": "SCHRODINGER_LICENSE_FILE",  # value: "27008@hostname"
        "open_alternatives": [
            {"id": "gnina", "label": "GNINA", "note": "CNN scoring, AutoDock-based, free"},
            {"id": "diffdock", "label": "DiffDock", "note": "Diffusion-based, state-of-art, free"},
        ],
    },
    "moe": {
        "display_name": "MOE (Molecular Operating Environment)",
        "vendor": "Chemical Computing Group (CCG)",
        "type": "license_server",       # credential shape: {license_server: "27001@host"}
        "registration_url": "https://www.chemcomp.com/MOE-Molecular_Operating_Environment.htm",
        "approval_time": "contact sales (1–5 days for academic)",
        "cost": "~$3,000–$8,000/yr academic",
        "container_patterns": ["moebatch", "moe2024", "chemcomp", "moe2023"],
        # BioMate master: none -- requires purchase decision
        "env_key": "LM_LICENSE_FILE",   # value: "27001@hostname"
        "open_alternatives": [
            {"id": "gnina", "label": "GNINA", "note": "Free, CNN scoring, good for non-covalent"},
            {"id": "diffdock", "label": "DiffDock", "note": "SOTA diffusion docking, free"},
        ],
    },
}

# ---------------------------------------------------------------------------
# Scanner
# ---------------------------------------------------------------------------

def scan_nf_for_tool_ids(nf_path: str) -> List[str]:
    """
    Return list of tool IDs from LICENSE_REGISTRY that are referenced
    in the given .nf file (container directives) or in the path itself.
    """
    matched: List[str] = []
    path_lower = nf_path.lower()

    # Path-name based detection (e.g. cryosparc in the workflow path)
    for tool_id, info in LICENSE_REGISTRY.items():
        for pattern in info.get("container_patterns", []):
            if pattern.lower() in path_lower:
                if tool_id not in matched:
                    matched.append(tool_id)
                break

    # Content-based detection: scan container directives in the .nf file
    try:
        content = Path(nf_path).read_text(errors="replace")
        for tool_id, info in LICENSE_REGISTRY.items():
            if tool_id in matched:
                continue
            for pattern in info.get("container_patterns", []):
                # Look for container = '...pattern...' or container "...pattern..."
                if re.search(rf"container\s*[=\s]\s*['\"].*{re.escape(pattern)}.*['\"]", content, re.IGNORECASE):
                    matched.append(tool_id)
                    break
    except (OSError, IOError):
        pass  # file not found / unreadable — path-based detection only

    return matched
