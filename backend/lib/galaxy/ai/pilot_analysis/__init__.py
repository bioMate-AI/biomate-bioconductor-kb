"""
Pilot Analysis Framework - Domain plugin architecture for intelligent parameter inference.

This module provides a plugin-based system for quick data characterization across
different scientific domains. Each domain (genomics, cryo-EM, etc.) implements
a plugin with its specific analyzers.

Architecture:
- base.py: Base classes (PilotAnalysisPlugin, AnalyzerSpec)
- plugins/: Domain-specific plugins (genomics.py, cryo_em.py, etc.)
- __init__.py: PluginManager to coordinate all plugins

Usage:
    from lib.galaxy.ai.pilot_analysis import get_pilot_manager

    manager = get_pilot_manager()

    # Get analyzer from any domain
    analyzer = manager.get_analyzer("estimate_fragment_size")

    # Get all analyzers for a specific domain
    genomics_analyzers = manager.get_domain_analyzers("genomics")

    # Find quick analyzers across all domains
    quick_ones = manager.get_quick_analyzers(max_runtime=30)

    # Check dependencies for a domain
    deps = manager.check_domain_dependencies("cryo_em")
"""

from typing import Dict, List, Optional, Any
import logging

from .base import PilotAnalysisPlugin, AnalyzerSpec
from .plugins import (
    GenomicsPilotPlugin,
    SingleCellPilotPlugin,
    BioimagingPilotPlugin,
    CryoEMPilotPlugin,
    MolecularBiologyPilotPlugin,
    PharmacologyPilotPlugin,
    BiochemistryPilotPlugin,
)
from .executor import PilotAnalysisExecutor, AnalysisResult, run_pilot_analysis

logger = logging.getLogger(__name__)


class PilotAnalysisPluginManager:
    """
    Central manager for all domain-specific pilot analysis plugins.

    Provides unified interface to discover and use analyzers across all domains.
    """

    def __init__(self):
        """Initialize plugin manager and load all domain plugins."""
        self.plugins: Dict[str, PilotAnalysisPlugin] = {}
        self._analyzer_index: Dict[str, tuple] = {}  # analyzer_name -> (domain, spec)

        # Register all domain plugins
        self._register_plugins()

    def _register_plugins(self):
        """Load and register all available domain plugins."""
        plugin_classes = [
            GenomicsPilotPlugin,
            SingleCellPilotPlugin,
            BioimagingPilotPlugin,
            CryoEMPilotPlugin,
            MolecularBiologyPilotPlugin,
            PharmacologyPilotPlugin,
            BiochemistryPilotPlugin,
        ]

        for plugin_class in plugin_classes:
            try:
                plugin = plugin_class()
                self.plugins[plugin.domain_name] = plugin

                # Build analyzer index for fast lookup
                for name, spec in plugin.analyzers.items():
                    if name in self._analyzer_index:
                        logger.warning(
                            f"Duplicate analyzer name '{name}' in domain '{plugin.domain_name}'. "
                            f"Previously defined in '{self._analyzer_index[name][0]}'"
                        )
                    self._analyzer_index[name] = (plugin.domain_name, spec)

                logger.info(
                    f"Registered {plugin.domain_name} plugin with {len(plugin.analyzers)} analyzers"
                )
            except Exception as e:
                logger.error(f"Failed to register plugin {plugin_class.__name__}: {e}")

    def get_analyzer(self, name: str) -> Optional[AnalyzerSpec]:
        """
        Get analyzer specification by name (searches across all domains).

        Args:
            name: Analyzer name (e.g., "estimate_fragment_size")

        Returns:
            AnalyzerSpec if found, None otherwise
        """
        if name in self._analyzer_index:
            domain, spec = self._analyzer_index[name]
            return spec
        return None

    def get_domain_analyzers(self, domain: str) -> Dict[str, AnalyzerSpec]:
        """
        Get all analyzers for a specific domain.

        Args:
            domain: Domain name (e.g., "genomics", "cryo_em")

        Returns:
            Dict mapping analyzer names to specs
        """
        if domain in self.plugins:
            return self.plugins[domain].analyzers
        return {}

    def get_all_analyzers(self) -> Dict[str, Dict[str, Any]]:
        """
        Get all analyzers across all domains.

        Returns:
            Nested dict: {analyzer_name: {"domain": ..., "spec": ...}}
        """
        result = {}
        for name, (domain, spec) in self._analyzer_index.items():
            result[name] = {"domain": domain, "spec": spec}
        return result

    def get_quick_analyzers(self, max_runtime: int = 30) -> List[Dict[str, Any]]:
        """
        Get analyzers that run in under max_runtime seconds.

        Args:
            max_runtime: Maximum runtime in seconds

        Returns:
            List of dicts with analyzer info: [{"name": ..., "domain": ..., "spec": ...}]
        """
        quick = []
        for name, (domain, spec) in self._analyzer_index.items():
            if spec.max_runtime_seconds <= max_runtime:
                quick.append({"name": name, "domain": domain, "spec": spec})
        return quick

    def get_analyzers_by_input_type(self, input_type: str) -> List[Dict[str, Any]]:
        """
        Get all analyzers that accept a specific input type.

        Args:
            input_type: Input type (e.g., "bam", "fasta", "h5ad")

        Returns:
            List of matching analyzers with domain info
        """
        matching = []
        for name, (domain, spec) in self._analyzer_index.items():
            if spec.input_type == input_type:
                matching.append({"name": name, "domain": domain, "spec": spec})
        return matching

    def list_domains(self) -> List[str]:
        """Get list of all registered domain names."""
        return list(self.plugins.keys())

    def get_domain_plugin(self, domain: str) -> Optional[PilotAnalysisPlugin]:
        """Get plugin instance for a specific domain."""
        return self.plugins.get(domain)

    def check_domain_dependencies(self, domain: str) -> Dict[str, bool]:
        """
        Check if dependencies are available for a domain's analyzers.

        Args:
            domain: Domain name

        Returns:
            Dict mapping dependency name to availability status
        """
        if domain in self.plugins:
            return self.plugins[domain].validate_dependencies()
        return {}

    def check_all_dependencies(self) -> Dict[str, Dict[str, bool]]:
        """
        Check dependencies for all domains.

        Returns:
            Nested dict: {domain: {dependency: available}}
        """
        results = {}
        for domain, plugin in self.plugins.items():
            results[domain] = plugin.validate_dependencies()
        return results

    def get_analyzer_count_by_domain(self) -> Dict[str, int]:
        """Get count of analyzers per domain."""
        return {domain: len(plugin.analyzers) for domain, plugin in self.plugins.items()}

    def export_to_legacy_format(self) -> Dict[str, Any]:
        """
        Export all analyzers to the legacy monolithic registry format.

        This is for backward compatibility with code expecting the old
        PILOT_ANALYZERS dict structure.

        Returns:
            Dict in old registry.py format
        """
        analyzers = {}
        categories = {}

        for domain, plugin in self.plugins.items():
            analyzer_names = []
            for name, spec in plugin.analyzers.items():
                analyzers[name] = spec.to_dict()
                analyzer_names.append(name)
            categories[domain] = analyzer_names

        return {"PILOT_ANALYZERS": analyzers, "ANALYZER_CATEGORIES": categories}

    def summary(self) -> str:
        """Generate summary report of registered plugins and analyzers."""
        lines = ["Pilot Analysis Plugin Manager Summary", "=" * 50]

        total_analyzers = len(self._analyzer_index)
        lines.append(f"\nTotal analyzers: {total_analyzers}")
        lines.append(f"Total domains: {len(self.plugins)}\n")

        for domain, plugin in sorted(self.plugins.items()):
            analyzer_count = len(plugin.analyzers)
            dep_count = len(plugin.dependencies)
            lines.append(f"  {domain:20} {analyzer_count:2} analyzers, {dep_count} dependencies")

        # Quick analyzers
        quick_30s = len(self.get_quick_analyzers(30))
        quick_60s = len(self.get_quick_analyzers(60))
        lines.append(f"\nQuick analyzers (<30s): {quick_30s}")
        lines.append(f"Quick analyzers (<60s): {quick_60s}")

        return "\n".join(lines)


# Singleton instance
_manager_instance = None


def get_pilot_manager() -> PilotAnalysisPluginManager:
    """
    Get singleton instance of the plugin manager.

    Returns:
        PilotAnalysisPluginManager instance
    """
    global _manager_instance
    if _manager_instance is None:
        _manager_instance = PilotAnalysisPluginManager()
    return _manager_instance


# Convenience functions for backward compatibility
def get_analyzer(name: str) -> Optional[AnalyzerSpec]:
    """Get analyzer by name (convenience wrapper)."""
    return get_pilot_manager().get_analyzer(name)


def get_analyzers_by_category(category: str) -> Dict[str, AnalyzerSpec]:
    """Get analyzers by category/domain (convenience wrapper)."""
    return get_pilot_manager().get_domain_analyzers(category)


def get_quick_analyzers(max_runtime: int = 30) -> List[str]:
    """Get quick analyzer names (convenience wrapper)."""
    quick = get_pilot_manager().get_quick_analyzers(max_runtime)
    return [item["name"] for item in quick]


# Export main classes and functions
__all__ = [
    "PilotAnalysisPluginManager",
    "get_pilot_manager",
    "get_analyzer",
    "get_analyzers_by_category",
    "get_quick_analyzers",
    "PilotAnalysisPlugin",
    "AnalyzerSpec",
    "PilotAnalysisExecutor",
    "AnalysisResult",
    "run_pilot_analysis",
]
