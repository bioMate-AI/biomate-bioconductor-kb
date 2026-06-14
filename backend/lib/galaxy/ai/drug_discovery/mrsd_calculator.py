"""
Forward MRSD calculator — Lane B1.

Companion to `mrsd_verifier.py`. Computes MRSD/HED/AS deterministically given
structured inputs so the LLM can call it as a tool instead of doing the
arithmetic itself (which the cross-judge eval scored at 0.21).

Math reference: FDA "Estimating the Maximum Safe Starting Dose in Initial
Clinical Trials" (2005). Uses BSA_DIVISOR + DEFAULT_SAFETY_FACTOR from
mrsd_verifier so calculator + checker agree by construction.
"""
from __future__ import annotations
from dataclasses import dataclass, asdict
from typing import Any

from .mrsd_verifier import BSA_DIVISOR, DEFAULT_SAFETY_FACTOR, _normalize_species

DEFAULT_HUMAN_WEIGHT_KG = 60.0


@dataclass(frozen=True)
class MRSDResult:
    species: str
    noael_mg_per_kg: float
    safety_factor: float
    human_weight_kg: float
    hed_mg_per_kg: float
    mrsd_mg_per_kg: float
    mrsd_mg_per_patient: float
    notes: list[str]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def to_prose(self) -> str:
        """One-paragraph FDA-style summary the LLM can drop into §2.6.1.1."""
        return (
            f"The {self.species} NOAEL of {self.noael_mg_per_kg:.1f} mg/kg/day "
            f"yields a human equivalent dose (HED) of {self.hed_mg_per_kg:.2f} mg/kg/day "
            f"after body-surface-area conversion. Applying a {self.safety_factor:g}× "
            f"safety factor, the maximum recommended starting dose (MRSD) is "
            f"{self.mrsd_mg_per_kg:.3f} mg/kg/day, or {self.mrsd_mg_per_patient:.1f} mg "
            f"for a {self.human_weight_kg:.0f}-kg patient."
        )


def compute_mrsd(
    noael_mg_per_kg: float,
    species: str,
    safety_factor: float = DEFAULT_SAFETY_FACTOR,
    human_weight_kg: float = DEFAULT_HUMAN_WEIGHT_KG,
) -> MRSDResult:
    notes: list[str] = []

    if noael_mg_per_kg <= 0:
        raise ValueError(f"noael_mg_per_kg must be > 0, got {noael_mg_per_kg}")
    if safety_factor <= 0:
        raise ValueError(f"safety_factor must be > 0, got {safety_factor}")
    if human_weight_kg <= 0:
        raise ValueError(f"human_weight_kg must be > 0, got {human_weight_kg}")

    normalized = _normalize_species(species)
    if normalized is None or normalized not in BSA_DIVISOR:
        raise ValueError(
            f"unknown_species:{species} — recognized: {sorted(BSA_DIVISOR.keys())}"
        )

    divisor = BSA_DIVISOR[normalized]
    hed = noael_mg_per_kg / divisor
    mrsd = hed / safety_factor
    mrsd_total = mrsd * human_weight_kg

    if safety_factor < DEFAULT_SAFETY_FACTOR:
        notes.append(
            f"safety_factor_below_default:{safety_factor}<{DEFAULT_SAFETY_FACTOR} — "
            f"document justification per FDA 2005 guidance §III"
        )

    return MRSDResult(
        species=normalized,
        noael_mg_per_kg=float(noael_mg_per_kg),
        safety_factor=float(safety_factor),
        human_weight_kg=float(human_weight_kg),
        hed_mg_per_kg=round(hed, 4),
        mrsd_mg_per_kg=round(mrsd, 4),
        mrsd_mg_per_patient=round(mrsd_total, 2),
        notes=notes,
    )


def compute_mrsd_tool_schema() -> dict[str, Any]:
    """OpenAI-compatible tool schema for LLM function-calling."""
    return {
        "type": "function",
        "function": {
            "name": "compute_mrsd",
            "description": (
                "Compute the FDA Maximum Recommended Starting Dose (MRSD) and "
                "Human Equivalent Dose (HED) from an animal NOAEL. Use this "
                "for any §2.6.1.1 Phase 1 starting-dose narrative. ALWAYS prefer "
                "this tool over computing MRSD yourself — LLM arithmetic on "
                "BSA conversions is unreliable."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "noael_mg_per_kg": {
                        "type": "number",
                        "description": "Animal NOAEL in mg/kg/day",
                    },
                    "species": {
                        "type": "string",
                        "enum": sorted(BSA_DIVISOR.keys()),
                        "description": "Animal species used in pivotal toxicology study",
                    },
                    "safety_factor": {
                        "type": "number",
                        "description": (
                            f"Safety divisor applied to HED. Default {DEFAULT_SAFETY_FACTOR}. "
                            "Use larger when novel target, steep dose-response, or severe AEs."
                        ),
                        "default": DEFAULT_SAFETY_FACTOR,
                    },
                    "human_weight_kg": {
                        "type": "number",
                        "description": "Assumed adult human weight in kg",
                        "default": DEFAULT_HUMAN_WEIGHT_KG,
                    },
                },
                "required": ["noael_mg_per_kg", "species"],
            },
        },
    }
