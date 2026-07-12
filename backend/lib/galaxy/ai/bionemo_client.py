"""
BioNeMo / NVIDIA NIM API client for BioMate.

Provides typed wrappers for all confirmed-live biology models accessible
via the NVIDIA Cloud Functions (NVCF) API. All schemas are empirically
verified against live endpoints (2026-07-09).

Environment variable:
    NVIDIA_API_KEY  — nvapi-... key with NVCF access

Usage:
    from galaxy.ai.bionemo_client import BioNeMoClient
    client = BioNeMoClient()
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

# ── Endpoint constants ────────────────────────────────────────────────────────
_NVCF_BASE   = "https://api.nvcf.nvidia.com/v2/nvcf/pexec/functions"
_HEALTH_BASE = "https://health.api.nvidia.com/v1/biology/nvidia"

# NVCF function IDs — verified live 2026-07-09
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


class BioNeMoClient:
    """Thin client for NVIDIA BioNeMo NIM biology models."""

    def __init__(self, api_key: Optional[str] = None, timeout: int = 300,
                 poll_interval: int = 5):
        self.api_key = api_key or os.environ.get("NVIDIA_API_KEY", "")
        if not self.api_key:
            raise ValueError("NVIDIA_API_KEY not set")
        self.timeout = timeout
        self.poll_interval = poll_interval
        self._session = requests.Session()
        self._session.headers.update({
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        })

    # ── Low-level NVCF call with polling ─────────────────────────────────────

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

    # ── Structure Prediction ──────────────────────────────────────────────────

    def esmfold(self, sequence: str) -> str:
        """
        Predict protein structure from sequence via ESMFold.
        Returns PDB string.

        Schema: POST https://health.api.nvidia.com/v1/biology/nvidia/esmfold
        """
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

        molecule_type: 'protein' | 'dna' | 'rna'
        ligand_smiles: optional SMILES for protein-ligand complex prediction
        """
        polymers = [{"sequence": sequence, "molecule_type": molecule_type}]
        if ligand_smiles:
            polymers.append({"sequence": ligand_smiles, "molecule_type": "ligand"})
        return self._nvcf_call("boltz2", {"polymers": polymers})

    def alphafold2(self, sequence: str) -> dict:
        """AlphaFold2 structure prediction. Returns structure dict."""
        return self._nvcf_call("alphafold2", {"sequence": sequence})

    def alphafold2_multimer(self, sequences: list) -> dict:
        """AlphaFold2-Multimer for protein complexes. sequences = list of chain seqs."""
        return self._nvcf_call("alphafold2_multimer", {"sequences": sequences})

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

        Returns dict with 'output_pdb' key (designed backbone PDB string).
        """
        payload: dict = {"contigs": contigs, "num_designs": num_designs}
        if input_pdb:
            payload["input_pdb"] = input_pdb
        if hotspot_res:
            payload["hotspot_res"] = hotspot_res
        if partial_diffusion:
            payload["partial_diffusion"] = True
            payload["partial_T"] = partial_T
        return self._nvcf_call("rfdiffusion", payload, poll_seconds=120)

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
        return self._nvcf_call("proteinmpnn", payload)

    # ── Genomics Foundation Models (Evo2) ────────────────────────────────────

    def evo2_generate(self, sequence: str, num_tokens: int = 100,
                      temperature: float = 1.0, model: str = "evo2_7b") -> dict:
        """
        DNA/RNA sequence generation via Evo2 (Arc Institute).

        sequence: seed DNA/RNA sequence (ACGT alphabet)
        num_tokens: number of nucleotides to generate
        temperature: sampling temperature (1.0 = default, lower = more conservative)
        model: 'evo2_7b' (fast) or 'evo2_40b' (flagship, 40B params)

        Returns dict with: sequence (generated DNA), elapsed_ms
        """
        if model not in ("evo2_7b", "evo2_40b", "evo2_7b_forward", "evo2_40b_forward"):
            raise ValueError(f"Unknown Evo2 model: {model}")
        return self._nvcf_call(model, {
            "sequence": sequence,
            "num_tokens": num_tokens,
            "temperature": temperature,
        }, poll_seconds=180)

    # ── Protein Language Models ───────────────────────────────────────────────

    def esm2_embed(self, sequences: list) -> dict:
        """
        Protein sequence embeddings via ESM2-650M.
        sequences: list of protein sequences.
        Returns dict with embeddings per sequence.
        """
        return self._nvcf_call("esm2_650m", {"sequences": sequences})

    def msa_search(self, sequence: str,
                   databases: Optional[list] = None) -> dict:
        """
        Multiple sequence alignment search via ColabFold MSA server.

        databases: list from ['Uniref30_2302', 'colabfold_envdb_202108', 'PDB70_220313']
        Returns dict with A3M alignments per database.

        Used as input for AlphaFold2-Multimer and Boltz2.
        """
        if databases is None:
            databases = ["Uniref30_2302"]
        return self._nvcf_call("msa_search", {
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

        Returns dict with docked poses + confidence scores.
        """
        return self._nvcf_call("diffdock", {
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
        """
        result = self._nvcf_call("genmol", {
            "smi": smiles,
            "num_molecules": num_molecules,
            "unique": unique,
        })
        return result.get("molecules", [])

    def molmim(self, smiles: str, num_molecules: int = 10) -> list:
        """
        SMILES analog generation via MolMIM (NVIDIA latent diffusion).
        Generates molecules similar to the input SMILES.

        Returns list of dicts: [{"sample": "SMILES", "score": float}, ...]
        """
        result = self._nvcf_call("molmim", {
            "smi": smiles,
            "num_molecules": num_molecules,
        })
        molecules_raw = result.get("molecules", "[]")
        if isinstance(molecules_raw, str):
            return json.loads(molecules_raw)
        return molecules_raw

    def moflow(self, smiles: str, num_molecules: int = 10) -> list:
        """
        Flow-based molecular generation via MoFlow.
        Similar to MolMIM but different latent space.
        """
        result = self._nvcf_call("moflow", {
            "smi": smiles,
            "num_molecules": num_molecules,
        })
        molecules_raw = result.get("molecules", "[]")
        if isinstance(molecules_raw, str):
            return json.loads(molecules_raw)
        return molecules_raw

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

        Returns list of candidate dicts with sequence + design metadata.
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
    """Get a BioNeMoClient using env NVIDIA_API_KEY."""
    return BioNeMoClient()


def list_models() -> dict:
    """Return the full map of available model names → (function_id, version_id)."""
    return dict(_FUNCTIONS)
