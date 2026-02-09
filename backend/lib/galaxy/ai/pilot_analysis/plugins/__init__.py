"""
Domain-specific pilot analysis plugins.

Each domain implements a plugin that defines its quick data characterization analyzers.
"""

from .genomics import GenomicsPilotPlugin
from .single_cell import SingleCellPilotPlugin
from .bioimaging import BioimagingPilotPlugin
from .cryo_em import CryoEMPilotPlugin
from .molecular_biology import MolecularBiologyPilotPlugin
from .pharmacology import PharmacologyPilotPlugin
from .biochemistry import BiochemistryPilotPlugin

__all__ = [
    "GenomicsPilotPlugin",
    "SingleCellPilotPlugin",
    "BioimagingPilotPlugin",
    "CryoEMPilotPlugin",
    "MolecularBiologyPilotPlugin",
    "PharmacologyPilotPlugin",
    "BiochemistryPilotPlugin",
]
