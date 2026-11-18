"""Concrete critic implementations (one module per domain)."""
from .survival import SurvivalConfoundingCritic, SurvivalPHCritic

__all__ = ["SurvivalConfoundingCritic", "SurvivalPHCritic"]
