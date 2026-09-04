"""
BioNeMo / NVIDIA NIM client for BioMate.

Provides typed wrappers for all confirmed-live biology models. The client
runs in one of three modes, chosen by the ``BIONEMO_MODE`` env var:

    self_host  — POST to self-hosted NIM containers on BioMate's own AWS
                 (``BIONEMO_SELF_HOST_URL``). Data never leaves the tenant.
                 This is the production posture (see
                 docs/20260903_ARCH_DECISIONS_BIONEMO_AND_GALAXY_EXIT.md §1).
    hosted_api — POST to NVIDIA's hosted NVCF API (needs ``NVIDIA_API_KEY``).
                 The original behaviour; kept for parity / dev convenience.
    stub       — never hit the network; return the documented result *shape*
                 with an honest ``reason`` and no fabricated values. This is
                 also the automatic fallback when the selected backend is
                 unconfigured or unreachable.

The default mode is auto-detected: ``self_host`` if ``BIONEMO_SELF_HOST_URL``
is set, else ``hosted_api`` if ``NVIDIA_API_KEY`` is set, else ``stub``.

All method signatures and return *shapes* are identical across modes, so
consumers (``models_inference.py``, ``denovo_pipeline.py`` / ``generators.py``)
need no changes. In stub / unreachable paths methods return the empty-but-
correctly-typed shape (``""`` for PDB strings, ``[]`` for molecule lists,
a shaped dict carrying ``_stub`` + ``reason`` for structured payloads) —
never a fabricated structure, sequence, or molecule.

Environment variables:
    BIONEMO_MODE            self_host | hosted_api | stub  (optional; auto)
    BIONEMO_SELF_HOST_URL   base URL of the self-hosted NIM gateway, e.g.
                            http://bionemo-nim.internal:8000  (self_host mode)
    NVIDIA_API_KEY          nvapi-... key with NVCF access   (hosted_api mode)
    BIONEMO_SELF_HOST_PATH_<MODEL>
                            optional per-model route override (uppercased
                            model name), e.g. BIONEMO_SELF_HOST_PATH_BOLTZ2

Usage:
    from galaxy.ai.bionemo_client import BioNeMoClient
    client = BioNeMoClient()
    print(client.health())            # which backend / which models are up
    pdb = client.esmfold("MKTAYIAKQRQISFVK")
    result = client.rfdiffusion(contigs="50-100", input_pdb=pdb)
"""

import os
import time
import json
import logging
import requests
from typing import Optional

log = logging.getLogger(__name__)

# ── Mode constants ────────────────────────────────────────────────────────────
MODE_SELF_HOST = "self_host"
MODE_HOSTED_API = "hosted_api"
MODE_STUB = "stub"
_VALID_MODES = (MODE_SELF_HOST, MODE_HOSTED_API, MODE_STUB)

# ── Endpoint constants ────────────────────────────────────────────────────────
_NVCF_BASE   = "https://api.nvcf.nvidia.com/v2/nvcf/pexec/functions"
_HEALTH_BASE = "https://health.api.nvidia.com/v1/biology/nvidia"

# NVCF function IDs — verified live 2026-07-09 (used only in hosted_api mode)
_FUNCTIONS = {
    # Structure prediction
    "esmfold":            ("a68c59e0-47a6-4a50-bf64-6d88766d56bf", "9150f163-6736-438f-89e8-1564390343e4"),
    "alphafold2":         ("e3dfc6dd-fc27-4f0e-9ede-94412256af18", "5a0d3a6e-b5d7-4fd4-93dc-57bd1db53433"),
    "alphafold2_multimer":("e973390d-ec28-43a3-880a-ef5bb4f505a3", "4e9018fb-77df-4fc9-a2bb-62fac130cbfd"),
    "boltz2":             ("deb120d0-a306-4c97-9538-0d9a23081047", "bb421ae6-4354-43e8-beac-d0b2d4f6147b"),
    "openfold2":          ("fb8a1686-a8c7-4302-a898-b9e150d9f0f6", "7ff4d03b-cf68-41e0-916a-6346538cfa5e"),
    "openfold3":          ("19c208c3-cef4-4d11-bfe2-6491495fff67", "f45a2208-b126-438b-a1ef-48f95758e990"),
    # Sequence / backbone design
    "rfdiffusion":        ("e469fc55-91c0-460d-a444-15d9921ac277", "0df48f4b-251b-4635-a4c3-3576be5aa86d"),
    "proteinmpnn":        ("77598af7-e712-44a2-8e91-d3522725740c", "0d18c2e5-c287-4dba-ade4-eb740540d6be"),
    # Protein language models
    "esm2_650m":          ("9e8155ab-97fc-487d-b325-02186064a14c", "5b28b508-a85c-44e0-b2ee-614b76acb4b1"),
    # Genomics foundation models (Arc Institute Evo2)
    "evo2_7b":            ("aae4817f-f496-4931-bf85-a55a951e9533", "9cf625df-f11c-4311-934b-01e941072041"),
    "evo2_7b_forward":    ("2a5ab2b3-a331-4544-847c-91f102feba64", "f58dea2e-92ef-4729-9d9f-1bbfcecb8ad0"),
    "evo2_40b":           ("de70b31d-cc9c-4b32-917f-e0d4cb49ce20", "87a3b98b-12c1-4597-a686-5831acce3713"),
    "evo2_40b_forward":   ("475da3a9-515e-417e-8c4d-f847c271d2be", "bb89e7fe-a8c0-4cf4-b6b8-e35518ef5c5f"),
    # Molecular docking
    "diffdock":           ("f3dda972-561a-4772-8c09-873594b6fb72", "1297cd61-e889-47d0-b574-82fd16b5b290"),
    # Small molecule generation
    "genmol":             ("9cfa4a89-6233-4f93-94f8-4f6e13998185", "19692e03-1bdf-4fe1-891b-61f19cfd3c70"),
    "molmim":             ("310d70d2-bb85-4085-88af-1847764defe2", "455a6e1a-db06-4da4-8bc4-9e6e6c02acc9"),
    "moflow":             ("8d93d27e-f6ef-4549-b915-2b205fa7152c", "b01dda07-3f96-4e06-86e2-a6c7276b210c"),
    # MSA
    "msa_search":         ("59978109-0fdc-4fc3-8e79-3fda0fc2981d", "7a886306-0194-4d9b-a7aa-22bfba32602b"),
    # Segmentation
    "vista3d":            ("72311276-923f-4478-a506-d5b80914728a", "bc599fe9-4814-43a2-a5ae-bf98cc9d5755"),
}

# ── Self-host NIM path map ────────────────────────────────────────────────────
# Per-model HTTP path appended to BIONEMO_SELF_HOST_URL when a NIM is
# self-hosted. NIM containers expose a REST route per model; the exact route
# CAN VARY BY NIM IMAGE. The compose/k8s gateway is expected to publish the
# models on these paths (or set BIONEMO_SELF_HOST_PATH_<MODEL> to override).
# These routes follow NVIDIA's published NIM URL conventions but MUST be
# confirmed against the running NIM's OpenAPI (`/docs`) at provision time —
# they are NOT asserted as verified here.
_SELF_HOST_PATHS = {
    "esmfold":            "/v1/biology/nvidia/esmfold",
    "alphafold2":         "/protein-structure/alphafold2/predict-structure-from-sequence",
    "alphafold2_multimer":"/protein-structure/alphafold2/multimer/predict-structure-from-sequences",
    "boltz2":             "/biology/mit/boltz2/predict",
    "openfold2":          "/protein-structure/openfold2/predict-structure-from-msa-and-template",
    "openfold3":          "/protein-structure/openfold3/predict",
    "rfdiffusion":        "/biology/ipd/rfdiffusion/generate",
    "proteinmpnn":        "/biology/ipd/proteinmpnn/predict",
    "esm2_650m":          "/biology/nvidia/esm2-650m/infer",
    "evo2_7b":            "/biology/arc/evo2-7b/generate",
    "evo2_7b_forward":    "/biology/arc/evo2-7b/forward",
    "evo2_40b":           "/biology/arc/evo2-40b/generate",
    "evo2_40b_forward":   "/biology/arc/evo2-40b/forward",
    "diffdock":           "/biology/mit/diffdock/generate",
    "genmol":             "/biology/nvidia/genmol/generate",
    "molmim":             "/biology/nvidia/molmim/generate",
    "moflow":             "/biology/nvidia/moflow/generate",
    "msa_search":         "/biology/colabfold/msa-search/predict",
    "vista3d":            "/vista3d/inference",
}


def _resolve_mode(mode: Optional[str], self_host_url: str, api_key: str) -> str:
    """Resolve the effective client mode from explicit arg / env / auto-detect."""
    raw = (mode or os.environ.get("BIONEMO_MODE", "")).strip().lower()
    if raw in _VALID_MODES:
        return raw
    if raw:
        log.warning("BIONEMO_MODE=%r is not one of %s — auto-detecting instead",
                    raw, _VALID_MODES)
    # Auto-detect: self-host wins if a base URL is configured, else hosted API
    # if a key is present, else stub.
    if self_host_url:
        return MODE_SELF_HOST
    if api_key:
        return MODE_HOSTED_API
    return MODE_STUB


class BioNeMoClient:
    """Thin client for NVIDIA BioNeMo NIM biology models (self-host / hosted / stub)."""

    def __init__(self, api_key: Optional[str] = None, timeout: int = 300,
                 poll_interval: int = 5, mode: Optional[str] = None,
                 self_host_url: Optional[str] = None):
        self.api_key = api_key or os.environ.get("NVIDIA_API_KEY", "")
        self.self_host_url = (
            self_host_url
            if self_host_url is not None
            else os.environ.get("BIONEMO_SELF_HOST_URL", "")
        ).rstrip("/")
        self.mode = _resolve_mode(mode, self.self_host_url, self.api_key)
        self.timeout = timeout
        self.poll_interval = poll_interval

        # NOTE: the constructor NEVER raises on a missing key/URL. In stub mode
        # (and self_host mode, which needs no key) that would break the graceful
        # fallback the consumers rely on. Reachability is surfaced via health().
        self._session = requests.Session()
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        self._session.headers.update(headers)

        if self.mode == MODE_HOSTED_API and not self.api_key:
            log.warning("BioNeMoClient in hosted_api mode but NVIDIA_API_KEY is "
                        "unset — calls will fall back to stub shapes")
        if self.mode == MODE_SELF_HOST and not self.self_host_url:
            log.warning("BioNeMoClient in self_host mode but BIONEMO_SELF_HOST_URL "
                        "is unset — calls will fall back to stub shapes")

    # ── Mode / reachability helpers ──────────────────────────────────────────

    def _effective_mode(self) -> str:
        """
        The mode actually used for a call. If the selected backend is
        unconfigured we degrade to stub so callers get honest empty shapes
        rather than a network error.
        """
        if self.mode == MODE_HOSTED_API and not self.api_key:
            return MODE_STUB
        if self.mode == MODE_SELF_HOST and not self.self_host_url:
            return MODE_STUB
        return self.mode

    def _self_host_path(self, model: str) -> str:
        override = os.environ.get(f"BIONEMO_SELF_HOST_PATH_{model.upper()}")
        if override:
            return override
        return _SELF_HOST_PATHS.get(model, f"/{model}")

    @staticmethod
    def _stub_reason(model: str, mode: str) -> str:
        if mode == MODE_STUB:
            return (f"BioNeMo unreachable for {model!r}: no backend configured "
                    f"(set BIONEMO_MODE=self_host + BIONEMO_SELF_HOST_URL, or "
                    f"BIONEMO_MODE=hosted_api + NVIDIA_API_KEY)")
        return f"BioNeMo stub for {model!r} in mode {mode}"

    # ── Dispatch: one entry point for all models ─────────────────────────────

    def _call(self, model: str, payload: dict, poll_seconds: int = 60) -> dict:
        """
        Route a model call to the effective backend.

        Returns the backend's raw JSON dict on success, or a stub dict of the
        form ``{"_stub": True, "reason": "...", "model": model}`` when the
        backend is not configured. Method wrappers below adapt this to each
        model's documented return shape. Never fabricates model outputs.
        """
        eff = self._effective_mode()
        if eff == MODE_STUB:
            return {"_stub": True, "model": model,
                    "reason": self._stub_reason(model, eff)}
        if eff == MODE_SELF_HOST:
            return self._self_host_call(model, payload)
        # hosted_api
        if model not in _FUNCTIONS:
            raise RuntimeError(f"BioNeMo hosted_api: no NVCF function id for {model!r}")
        return self._nvcf_call(model, payload, poll_seconds=poll_seconds)

    # ── Self-host NIM call ───────────────────────────────────────────────────

    def _self_host_call(self, model: str, payload: dict) -> dict:
        """
        POST to a self-hosted NIM container. NIM images may respond
        synchronously (200) or, for long jobs, use a 202 + task-polling
        protocol; we handle both without fabricating a result.
        """
        url = f"{self.self_host_url}{self._self_host_path(model)}"
        try:
            resp = self._session.post(url, json=payload, timeout=self.timeout)
        except requests.RequestException as exc:
            # Unreachable self-host → honest stub shape, NOT a fabricated result.
            log.warning("BioNeMo self-host unreachable for %s at %s: %s",
                        model, url, exc)
            return {"_stub": True, "model": model,
                    "reason": f"self-host unreachable at {url}: {exc}"}

        if resp.status_code == 200:
            return resp.json()

        if resp.status_code == 202:
            # NIM async task pattern: poll the status/task URL from the header.
            task_url = (resp.headers.get("nvcf-reqid")
                        or resp.headers.get("x-task-id")
                        or resp.headers.get("location"))
            if not task_url:
                try:
                    return resp.json()
                except Exception:
                    return {"_stub": True, "model": model,
                            "reason": "self-host 202 with no task handle"}
            return self._self_host_poll(model, task_url)

        try:
            err = resp.json()
        except Exception:
            err = resp.text[:300]
        raise RuntimeError(f"BioNeMo self-host {model} error {resp.status_code}: {err}")

    def _self_host_poll(self, model: str, task_url: str) -> dict:
        # If the header is a full URL use it, else assume a task-id under the base.
        if not task_url.startswith("http"):
            task_url = f"{self.self_host_url}/v1/tasks/{task_url}"
        deadline = time.time() + self.timeout
        while time.time() < deadline:
            r = self._session.get(task_url, timeout=30)
            if r.status_code == 200:
                return r.json()
            if r.status_code == 202:
                time.sleep(self.poll_interval)
                continue
            raise RuntimeError(f"self-host poll {model} error {r.status_code}: {r.text[:300]}")
        raise TimeoutError(f"self-host {model} task did not complete within {self.timeout}s")

    # ── Low-level NVCF call with polling (hosted_api mode) ────────────────────

    def _nvcf_call(self, model: str, payload: dict, poll_seconds: int = 60) -> dict:
        """
        POST to NVCF function; handle both sync (200) and async (202) responses.
        202 responses use NVCF-REQID + polling until 200/error.
        """
        fn_id, ver_id = _FUNCTIONS[model]
        url = f"{_NVCF_BASE}/{fn_id}/versions/{ver_id}"
        headers = {"NVCF-POLL-SECONDS": str(poll_seconds)}

        resp = self._session.post(url, json=payload, headers=headers,
                                  timeout=self.timeout)

        if resp.status_code == 200:
            return resp.json()

        if resp.status_code == 202:
            req_id = resp.headers.get("NVCF-REQID")
            if not req_id:
                raise RuntimeError("NVCF 202 but no NVCF-REQID header")
            return self._poll(req_id)

        try:
            err = resp.json()
        except Exception:
            err = resp.text
        raise RuntimeError(f"BioNeMo {model} error {resp.status_code}: {err}")

    def _poll(self, req_id: str) -> dict:
        poll_url = f"https://api.nvcf.nvidia.com/v2/nvcf/pexec/status/{req_id}"
        deadline = time.time() + self.timeout
        while time.time() < deadline:
            r = self._session.get(poll_url, timeout=30)
            if r.status_code == 200:
                return r.json()
            if r.status_code == 202:
                time.sleep(self.poll_interval)
                continue
            raise RuntimeError(f"NVCF poll error {r.status_code}: {r.text[:300]}")
        raise TimeoutError(f"NVCF request {req_id} did not complete within {self.timeout}s")

    @staticmethod
    def _is_stub(raw: dict) -> bool:
        return isinstance(raw, dict) and raw.get("_stub") is True

    # ── Structure Prediction ──────────────────────────────────────────────────

    def esmfold(self, sequence: str) -> str:
        """
        Predict protein structure from sequence via ESMFold.
        Returns PDB string ('' when the backend is unreachable — never a
        fabricated structure).
        """
        eff = self._effective_mode()
        if eff == MODE_STUB:
            log.info("esmfold: %s", self._stub_reason("esmfold", eff))
            return ""
        if eff == MODE_SELF_HOST:
            raw = self._self_host_call("esmfold", {"sequence": sequence})
            if self._is_stub(raw):
                return ""
            pdbs = raw.get("pdbs", [])
            return pdbs[0] if pdbs else raw.get("pdb", "")
        # hosted_api: dedicated health endpoint
        url = f"{_HEALTH_BASE}/esmfold"
        resp = self._session.post(url, json={"sequence": sequence}, timeout=self.timeout)
        if resp.status_code != 200:
            raise RuntimeError(f"ESMFold error {resp.status_code}: {resp.text[:300]}")
        data = resp.json()
        pdbs = data.get("pdbs", [])
        return pdbs[0] if pdbs else ""

    def boltz2(self, sequence: str, molecule_type: str = "protein",
               ligand_smiles: Optional[str] = None) -> dict:
        """
        Structure prediction via Boltz-2 (AF3-class, fast).
        Returns dict with: structures (CIF), confidence_scores, ptm_scores, iptm_scores.
        On an unreachable backend, returns a stub dict (``_stub``/``reason``)
        with those keys empty — never a fabricated structure.

        molecule_type: 'protein' | 'dna' | 'rna'
        ligand_smiles: optional SMILES for protein-ligand complex prediction
        """
        polymers = [{"sequence": sequence, "molecule_type": molecule_type}]
        if ligand_smiles:
            polymers.append({"sequence": ligand_smiles, "molecule_type": "ligand"})
        raw = self._call("boltz2", {"polymers": polymers})
        return raw  # shape passthrough; consumers read structures/confidence keys

    def alphafold2(self, sequence: str) -> dict:
        """AlphaFold2 structure prediction. Returns structure dict (stub when unreachable)."""
        return self._call("alphafold2", {"sequence": sequence})

    def alphafold2_multimer(self, sequences: list) -> dict:
        """AlphaFold2-Multimer for protein complexes. sequences = list of chain seqs."""
        return self._call("alphafold2_multimer", {"sequences": sequences})

    # ── Backbone & Sequence Design ────────────────────────────────────────────

    def rfdiffusion(self, contigs: str, input_pdb: Optional[str] = None,
                    hotspot_res: Optional[str] = None,
                    num_designs: int = 1, partial_diffusion: bool = False,
                    partial_T: int = 20) -> dict:
        """
        Protein backbone design via RFdiffusion.

        contigs: RFdiffusion contig string
            Unconditional:    "100"           → design 100-residue protein
            Motif scaffold:   "A1-50/0 B1-50" → scaffold a motif from chain A
            Cyclic peptide:   "A163-170/0 10-15" → scaffold IL-17A hotspot with 10-15 aa ring
        input_pdb: receptor PDB string (required for motif scaffolding)
        hotspot_res: comma-separated hotspot residues e.g. "A163,A167,A168"
        num_designs: number of backbone designs to generate

        Returns dict with 'output_pdb' key (designed backbone PDB string), or a
        stub dict when the backend is unreachable.
        """
        payload: dict = {"contigs": contigs, "num_designs": num_designs}
        if input_pdb:
            payload["input_pdb"] = input_pdb
        if hotspot_res:
            payload["hotspot_res"] = hotspot_res
        if partial_diffusion:
            payload["partial_diffusion"] = True
            payload["partial_T"] = partial_T
        return self._call("rfdiffusion", payload, poll_seconds=120)

    def proteinmpnn(self, input_pdb: str, num_seq_per_target: int = 8,
                    sampling_temp: list = None,
                    chains_to_design: Optional[str] = None) -> dict:
        """
        Sequence design on a backbone structure via ProteinMPNN.

        input_pdb: backbone PDB string (from RFdiffusion or experimental)
        num_seq_per_target: sequences to design per structure
        sampling_temp: list of temperatures, e.g. [0.1] (lower = more conservative)
        chains_to_design: comma-separated chain IDs to design, e.g. "A"

        Returns dict with:
            mfasta: multi-FASTA string of designed sequences + scores
            scores: list of per-sequence recovery scores
            probs: per-position amino acid probability matrices
        (or a stub dict when the backend is unreachable).
        """
        if sampling_temp is None:
            sampling_temp = [0.1]
        payload: dict = {
            "input_pdb": input_pdb,
            "num_seq_per_target": num_seq_per_target,
            "sampling_temp": sampling_temp,
        }
        if chains_to_design:
            payload["chains_to_design"] = chains_to_design
        return self._call("proteinmpnn", payload)

    # ── Genomics Foundation Models (Evo2) ────────────────────────────────────

    def evo2_generate(self, sequence: str, num_tokens: int = 100,
                      temperature: float = 1.0, model: str = "evo2_7b") -> dict:
        """
        DNA/RNA sequence generation via Evo2 (Arc Institute).

        sequence: seed DNA/RNA sequence (ACGT alphabet)
        num_tokens: number of nucleotides to generate
        temperature: sampling temperature (1.0 = default, lower = more conservative)
        model: 'evo2_7b' (fast) or 'evo2_40b' (flagship, 40B params)

        Returns dict with: sequence (generated DNA), elapsed_ms — or a stub dict
        with an empty 'sequence' when the backend is unreachable.
        """
        if model not in ("evo2_7b", "evo2_40b", "evo2_7b_forward", "evo2_40b_forward"):
            raise ValueError(f"Unknown Evo2 model: {model}")
        return self._call(model, {
            "sequence": sequence,
            "num_tokens": num_tokens,
            "temperature": temperature,
        }, poll_seconds=180)

    # ── Protein Language Models ───────────────────────────────────────────────

    def esm2_embed(self, sequences: list) -> dict:
        """
        Protein sequence embeddings via ESM2-650M.
        sequences: list of protein sequences.
        Returns dict with embeddings per sequence (stub when unreachable).
        """
        return self._call("esm2_650m", {"sequences": sequences})

    def msa_search(self, sequence: str,
                   databases: Optional[list] = None) -> dict:
        """
        Multiple sequence alignment search via ColabFold MSA server.

        databases: list from ['Uniref30_2302', 'colabfold_envdb_202108', 'PDB70_220313']
        Returns dict with A3M alignments per database (stub when unreachable).

        Used as input for AlphaFold2-Multimer and Boltz2.
        """
        if databases is None:
            databases = ["Uniref30_2302"]
        return self._call("msa_search", {
            "sequence": sequence,
            "databases": databases,
        })

    # ── Molecular Docking ────────────────────────────────────────────────────

    def diffdock(self, ligand_smiles: str, protein_pdb: str,
                 num_poses: int = 10) -> dict:
        """
        Molecular docking via DiffDock (SE(3)-diffusion, Stark et al. 2022).

        ligand_smiles: SMILES string of small molecule
        protein_pdb: receptor PDB string
        num_poses: number of docked poses to return

        Returns dict with docked poses + confidence scores (stub when unreachable).
        """
        return self._call("diffdock", {
            "ligand_file_string": ligand_smiles,
            "protein_file_string": protein_pdb,
            "num_poses": num_poses,
        }, poll_seconds=120)

    # ── Small Molecule Generation ─────────────────────────────────────────────

    def genmol(self, smiles: str, num_molecules: int = 10,
               unique: bool = True) -> list:
        """
        De novo molecule generation via GenMol (NVIDIA).

        smiles: seed SMILES (use '' for unconditional generation)
        Returns list of dicts: [{"smiles": "...", "score": float}, ...]
        (empty list when the backend is unreachable — never fabricated molecules).
        """
        result = self._call("genmol", {
            "smi": smiles,
            "num_molecules": num_molecules,
            "unique": unique,
        })
        if self._is_stub(result):
            return []
        return result.get("molecules", [])

    def molmim(self, smiles: str, num_molecules: int = 10) -> list:
        """
        SMILES analog generation via MolMIM (NVIDIA latent diffusion).
        Generates molecules similar to the input SMILES.

        Returns list of dicts: [{"sample": "SMILES", "score": float}, ...]
        (empty list when the backend is unreachable).
        """
        result = self._call("molmim", {
            "smi": smiles,
            "num_molecules": num_molecules,
        })
        if self._is_stub(result):
            return []
        molecules_raw = result.get("molecules", "[]")
        if isinstance(molecules_raw, str):
            return json.loads(molecules_raw)
        return molecules_raw

    def moflow(self, smiles: str, num_molecules: int = 10) -> list:
        """
        Flow-based molecular generation via MoFlow.
        Similar to MolMIM but different latent space.
        Returns empty list when the backend is unreachable.
        """
        result = self._call("moflow", {
            "smi": smiles,
            "num_molecules": num_molecules,
        })
        if self._is_stub(result):
            return []
        molecules_raw = result.get("molecules", "[]")
        if isinstance(molecules_raw, str):
            return json.loads(molecules_raw)
        return molecules_raw

    # ── Health / status ───────────────────────────────────────────────────────

    def health(self, models: Optional[list] = None,
               probe: bool = True) -> dict:
        """
        Report the client's backend and, in self_host mode, which NIMs are up.

        Returns a dict:
            {
              "mode": "self_host" | "hosted_api" | "stub",
              "effective_mode": <mode actually used for calls>,
              "self_host_url": "..." | None,
              "api_key_present": bool,
              "reachable": bool | None,      # overall backend reachability
              "models": {                     # per-model status (self_host only)
                  "boltz2": {"reachable": bool, "detail": "..."}, ...
              },
              "reason": "..."                 # when not reachable
            }

        probe=False skips network probes (config-only view). In stub mode no
        network is touched regardless of ``probe``. Never fabricates
        model availability.
        """
        eff = self._effective_mode()
        status: dict = {
            "mode": self.mode,
            "effective_mode": eff,
            "self_host_url": self.self_host_url or None,
            "api_key_present": bool(self.api_key),
            "reachable": None,
            "models": {},
        }

        if eff == MODE_STUB:
            status["reachable"] = False
            status["reason"] = self._stub_reason("<any>", eff)
            return status

        if not probe:
            return status

        if eff == MODE_HOSTED_API:
            # We don't burn an inference call to probe NVCF; presence of a key
            # is the config gate. Report reachable=None (unknown without a call).
            status["reachable"] = None
            status["reason"] = "hosted_api: reachability unknown without an inference call"
            return status

        # self_host: probe the gateway (and each requested model's route with a
        # cheap GET, which NIMs typically answer via /docs or a health route).
        probe_models = models or ["boltz2", "genmol", "molmim", "evo2_7b", "diffdock"]
        base_ok = None
        try:
            r = self._session.get(f"{self.self_host_url}/v1/health/ready", timeout=10)
            base_ok = r.status_code < 500
        except requests.RequestException as exc:
            base_ok = False
            status["reason"] = f"self-host gateway unreachable: {exc}"

        status["reachable"] = base_ok
        for m in probe_models:
            path = self._self_host_path(m)
            model_url = f"{self.self_host_url}{path}"
            try:
                # A GET on the inference route: 200/405/422 all mean the route
                # exists (the NIM is up); connection errors mean it's down.
                r = self._session.get(model_url, timeout=10)
                up = r.status_code in (200, 400, 405, 415, 422)
                status["models"][m] = {
                    "reachable": up,
                    "detail": f"HTTP {r.status_code} at {path}",
                }
            except requests.RequestException as exc:
                status["models"][m] = {"reachable": False, "detail": str(exc)}
        return status

    # ── Convenience: full cyclic peptide chain ────────────────────────────────

    def design_cyclic_peptide(self, receptor_pdb: str, hotspot_residues: str,
                               ring_size_range: str = "8,12",
                               num_backbones: int = 10,
                               num_sequences_per_backbone: int = 4) -> list:
        """
        End-to-end cyclic peptide design: RFdiffusion → ProteinMPNN.

        receptor_pdb: receptor PDB string (e.g. fetched from RCSB)
        hotspot_residues: comma-separated hotspot residues e.g. "A163,A167,A168"
        ring_size_range: "min,max" residues in macrocyclic ring
        num_backbones: number of RFdiffusion backbone scaffolds
        num_sequences_per_backbone: ProteinMPNN sequences per backbone

        Returns list of candidate dicts with sequence + design metadata (empty
        list when the backend is unreachable).
        """
        ring_min, ring_max = ring_size_range.split(",")
        results = []

        for i in range(num_backbones):
            log.info(f"RFdiffusion backbone {i+1}/{num_backbones}")
            # Motif-scaffolding contig: hotspot residues + ring of designed residues
            hotspot_parts = hotspot_residues.replace(",", "/")
            contigs = f"{hotspot_parts}/0 A{ring_min}-{ring_max}"

            try:
                backbone_result = self.rfdiffusion(
                    contigs=contigs,
                    input_pdb=receptor_pdb,
                    hotspot_res=hotspot_residues,
                    num_designs=1,
                )
                backbone_pdb = backbone_result.get("output_pdb", "")
                if not backbone_pdb:
                    log.warning(f"Backbone {i+1}: no output_pdb in response")
                    continue

                log.info(f"ProteinMPNN on backbone {i+1}")
                mpnn_result = self.proteinmpnn(
                    input_pdb=backbone_pdb,
                    num_seq_per_target=num_sequences_per_backbone,
                    sampling_temp=[0.1],
                )
                mfasta = mpnn_result.get("mfasta", "")
                scores = mpnn_result.get("scores", [])

                # Parse FASTA sequences
                seqs = []
                current_header = None
                for line in mfasta.split("\n"):
                    if line.startswith(">"):
                        current_header = line[1:].strip()
                    elif line.strip() and current_header:
                        seqs.append({
                            "backbone_idx": i + 1,
                            "sequence": line.strip(),
                            "header": current_header,
                            "backbone_pdb": backbone_pdb,
                        })
                        current_header = None

                results.extend(seqs)

            except Exception as e:
                log.error(f"Backbone {i+1} failed: {e}")
                continue

        return results


# ── Module-level convenience functions ────────────────────────────────────────

def get_client() -> BioNeMoClient:
    """Get a BioNeMoClient using env BIONEMO_MODE / BIONEMO_SELF_HOST_URL / NVIDIA_API_KEY."""
    return BioNeMoClient()


def list_models() -> dict:
    """Return the full map of available model names → (function_id, version_id)."""
    return dict(_FUNCTIONS)
