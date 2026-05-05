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
    # AWS S3 user credentials — for private bucket access during workflows
    # ------------------------------------------------------------------
    "s3": {
        "display_name": "Amazon S3",
        "vendor": "Amazon Web Services",
        "type": "aws_credentials",       # credential shape: {aws_access_key_id, aws_secret_access_key, aws_region, s3_bucket}
        "registration_url": "https://aws.amazon.com/iam/",
        "approval_time": "instant (IAM console)",
        "cost": "standard AWS S3 pricing",
        "container_patterns": [],        # not a container tool — platform-level credential
        "user_must_provide": True,       # each user provides their own IAM credentials
        "env_key_access": "AWS_ACCESS_KEY_ID",
        "env_key_secret": "AWS_SECRET_ACCESS_KEY",
        "env_key_region": "AWS_DEFAULT_REGION",
        "open_alternatives": [],
        "description": "Your AWS Access Key ID and Secret Access Key for accessing private S3 buckets. Create a read-only IAM user with s3:GetObject and s3:ListBucket permissions on your data bucket.",
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
        "type": "license_server",
        "registration_url": "https://www.chemcomp.com/MOE-Molecular_Operating_Environment.htm",
        "approval_time": "contact sales (1–5 days for academic)",
        "cost": "~$3,000–$8,000/yr academic",
        "container_patterns": ["moebatch", "moe2024", "chemcomp", "moe2023"],
        "env_key": "LM_LICENSE_FILE",
        "open_alternatives": [
            {"id": "gnina", "label": "GNINA", "note": "Free, CNN scoring, good for non-covalent"},
            {"id": "diffdock", "label": "DiffDock", "note": "SOTA diffusion docking, free"},
        ],
    },
    # ------------------------------------------------------------------
    # PBPK / PK-PD licensed tools
    # ------------------------------------------------------------------
    "simcyp": {
        "display_name": "Simcyp Population-Based Simulator",
        "vendor": "Certara",
        "type": "license_file",         # credential: path to Simcyp.lic or FNP license server
        "registration_url": "https://www.certara.com/software/simcyp-pbpk/",
        "approval_time": "contact sales (1–4 weeks); academic consortium available",
        "cost": "~$50,000–$200,000/yr commercial; academic consortium ~$5,000–$15,000/yr",
        "container_patterns": ["simcyp", "certara/simcyp", "pbpksimcyp"],
        "user_must_provide": True,
        "env_key": "SIMCYP_LICENSE_FILE",   # path to Simcyp.lic
        "env_key_server": "SIMCYP_LICENSE_SERVER",  # alternative: FNP server "27000@host"
        "quality_tier": "submission",       # regulatory gold standard
        "regulatory_status": "EMA Qualification Opinion 2025; FDA accepted",
        "open_alternatives": [
            {"id": "pk_sim", "label": "PK-Sim (OSP Suite)", "note": "Free, LGPL, EMA-accepted; ontogeny models"},
            {"id": "pbpk_simulation", "label": "BioMate native PBPK", "note": "IND-ready screening; no license needed"},
        ],
        "byol_instructions": (
            "1. Obtain a Simcyp license from Certara (simcyp.com/contact). "
            "2. Locate your Simcyp.lic file (or FNP license server address). "
            "3. Enter the license file path or server address in BioMate Settings → Credentials → Simcyp. "
            "4. BioMate injects SIMCYP_LICENSE_FILE at workflow runtime — your license is used only for your runs."
        ),
    },
    "nonmem": {
        "display_name": "NONMEM (Nonlinear Mixed-Effects Modeling)",
        "vendor": "ICON plc (formerly Globomax)",
        "type": "license_file",
        "registration_url": "https://www.iconplc.com/solutions/technologies/nonmem/",
        "approval_time": "contact sales (1–2 weeks)",
        "cost": "~$10,000–$30,000/yr per site; academic discounts available",
        "container_patterns": ["nonmem", "nmfe75", "nmfe74", "icon_nonmem"],
        "user_must_provide": True,
        "env_key": "NONMEM_LICENSE_FILE",   # nonmem.lic path
        "env_key_home": "NONMEM_HOME",       # /opt/NONMEM/nm75 (install dir)
        "quality_tier": "submission",
        "regulatory_status": "FDA standard for NDA PopPK reports; 40+ years industry use",
        "open_alternatives": [
            {"id": "nlmixr2", "label": "nlmixr2 (R)", "note": "Free, GPL, FDA-acceptable, SAEM/FOCE"},
            {"id": "virtual_patient_cohort", "label": "BioMate Monte Carlo PopPK", "note": "IND-ready screening"},
        ],
        "byol_instructions": (
            "1. Purchase NONMEM from ICON (iconplc.com/nonmem). "
            "2. Install NONMEM to a directory (e.g. /opt/NONMEM/nm75). "
            "3. Enter your NONMEM_HOME and license file path in BioMate Settings → Credentials → NONMEM. "
            "4. BioMate mounts your NONMEM installation into the workflow container at runtime."
        ),
    },
    "gastroplus": {
        "display_name": "GastroPlus",
        "vendor": "Simulations Plus",
        "type": "license_key",          # credential: license key string
        "registration_url": "https://www.simulations-plus.com/software/gastroplus/",
        "approval_time": "contact sales (3–7 days)",
        "cost": "~$15,000–$40,000/yr; ADMET Predictor bundled or separate",
        "container_patterns": ["gastroplus", "simulations-plus", "gpplus", "admetpredictor"],
        "user_must_provide": True,
        "env_key": "GASTROPLUS_LICENSE_KEY",
        "quality_tier": "submission",
        "regulatory_status": "FDA accepted; PBBM (physiologically-based biopharmaceutics modeling) gold standard",
        "open_alternatives": [
            {"id": "pk_sim", "label": "PK-Sim (OSP Suite)", "note": "Free, LGPL; no ADAM gut model"},
            {"id": "pbpk_simulation", "label": "BioMate native PBPK", "note": "IND-ready; oral absorption modeled"},
        ],
        "byol_instructions": (
            "1. Purchase GastroPlus from Simulations Plus (simulations-plus.com). "
            "2. Retrieve your license key from the Simulations Plus customer portal. "
            "3. Enter it in BioMate Settings → Credentials → GastroPlus."
        ),
    },
    "schrodinger_fep": {
        "display_name": "Schrödinger FEP+ (Free Energy Perturbation)",
        "vendor": "Schrödinger, Inc.",
        "type": "license_server",
        "registration_url": "https://www.schrodinger.com/products/fep/",
        "approval_time": "contact sales",
        "cost": "Bundled with Schrödinger Suite; FEP+ tokens separate from Glide",
        "container_patterns": ["fep_plus", "fepplus", "schrodinger/fep", "desmond_fep"],
        "user_must_provide": True,
        "env_key": "SCHRODINGER_LICENSE_FILE",  # same FlexLM server as Glide; FEP+ needs separate token
        "quality_tier": "submission",
        "regulatory_status": "Industry standard for lead optimization RBFE; top-20 pharma standard",
        "open_alternatives": [
            {"id": "openfe", "label": "OpenFE", "note": "MIT license; AT-SOMD; close to FEP+ accuracy"},
            {"id": "gromacs_protein_md", "label": "GROMACS MM-GBSA", "note": "Free; less rigorous than FEP"},
        ],
        "byol_instructions": (
            "1. Your Schrödinger FlexLM license server must include FEP+ tokens. "
            "2. Use the same SCHRODINGER_LICENSE_FILE credential as Glide docking. "
            "3. Ensure your license includes 'DESMOND_FEP' or 'FEP_PLUS' tokens."
        ),
    },
    "stardrop": {
        "display_name": "StarDrop",
        "vendor": "Optibrium",
        "type": "license_server",
        "registration_url": "https://www.optibrium.com/stardrop/",
        "approval_time": "contact sales (1–5 days)",
        "cost": "annual license; no public pricing",
        "container_patterns": ["stardrop", "optibrium", "stardrop_nova"],
        "user_must_provide": True,
        "env_key": "STARDROP_LICENSE_SERVER",
        "quality_tier": "premium_screening",
        "regulatory_status": "Widely used in med chem; not submission-grade standalone",
        "open_alternatives": [
            {"id": "predict_admet_properties", "label": "BioMate ADMET (AI)", "note": "ChEMBL-trained; free"},
            {"id": "admet_ai", "label": "ADMET-AI", "note": "Open source; Therapeutics Data Commons"},
        ],
    },
    "monolix": {
        "display_name": "Monolix",
        "vendor": "Lixoft (Simulations Plus)",
        "type": "license_key",
        "registration_url": "https://lixoft.com/products/monolix/",
        "approval_time": "contact sales (1–5 days); academic free version available",
        "cost": "~$5,000–$15,000/yr commercial; free academic version (MonolixSuite Academic)",
        "container_patterns": ["monolix", "lixoft", "mlxr"],
        "user_must_provide": True,
        "env_key": "MONOLIX_LICENSE_KEY",
        "quality_tier": "submission",
        "regulatory_status": "FDA-acceptable; EMA standard in Europe; SAEM estimation",
        "open_alternatives": [
            {"id": "nlmixr2", "label": "nlmixr2 (R)", "note": "Free, SAEM-compatible, FDA-acceptable"},
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
