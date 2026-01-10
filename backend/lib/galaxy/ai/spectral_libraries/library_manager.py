#!/usr/bin/env python3
"""
Spectral Library Manager for DIA-NN Pre-computed Libraries

This module manages pre-computed spectral libraries for DIA-NN proteomics analysis.
It handles library discovery, download, caching, and validation.

Usage:
    from spectral_libraries.library_manager import SpectralLibraryManager

    manager = SpectralLibraryManager()

    # List available libraries
    libraries = manager.list_libraries()

    # Get recommended library for organism
    lib_info = manager.get_recommended_library("human")

    # Download library
    local_path = manager.download_library("human", "reviewed")
"""

import json
import hashlib
import logging
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from urllib.request import urlretrieve, urlopen
from urllib.error import URLError, HTTPError
import os

logger = logging.getLogger(__name__)

# Default paths
MODULE_DIR = Path(__file__).parent
REGISTRY_FILE = MODULE_DIR / "library_registry.json"
DEFAULT_CACHE_DIR = Path.home() / ".biomate" / "spectral_libraries"


@dataclass
class LibraryInfo:
    """Information about a spectral library."""
    organism: str
    organism_name: str
    taxonomy_id: Optional[int]
    variant: str
    name: str
    description: str
    filename: str
    url: str
    proteins: int
    peptides: int
    file_size_bytes: int
    file_size_human: str
    md5: Optional[str]
    enzyme: str
    missed_cleavages: int
    fixed_mods: List[str]
    variable_mods: List[str]
    diann_version: str
    uniprot_version: str
    recommended: bool = False


class SpectralLibraryManager:
    """
    Manager for pre-computed DIA-NN spectral libraries.

    Provides functionality to:
    - List available pre-computed libraries
    - Download libraries with progress tracking
    - Cache libraries locally
    - Validate library integrity
    - Check compatibility with analysis parameters
    """

    def __init__(self, cache_dir: Optional[Path] = None, registry_file: Optional[Path] = None):
        """
        Initialize the library manager.

        Args:
            cache_dir: Directory to cache downloaded libraries
            registry_file: Path to library registry JSON file
        """
        self.cache_dir = Path(cache_dir) if cache_dir else DEFAULT_CACHE_DIR
        self.registry_file = Path(registry_file) if registry_file else REGISTRY_FILE
        self._registry = None

        # Ensure cache directory exists
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    @property
    def registry(self) -> Dict:
        """Load and cache the library registry."""
        if self._registry is None:
            if not self.registry_file.exists():
                raise FileNotFoundError(f"Library registry not found: {self.registry_file}")
            with open(self.registry_file) as f:
                self._registry = json.load(f)
        return self._registry

    @property
    def base_url(self) -> str:
        """Get the base URL for library downloads."""
        return self.registry.get("base_url", "")

    @property
    def speclib_prefix(self) -> str:
        """Get the S3 prefix for spectral libraries."""
        return self.registry.get("speclib_prefix", "spectral_libraries")

    def list_organisms(self) -> List[str]:
        """List all available organisms."""
        return list(self.registry.get("libraries", {}).keys())

    def list_variants(self, organism: str) -> List[str]:
        """List available library variants for an organism."""
        org_data = self.registry.get("libraries", {}).get(organism, {})
        return list(org_data.get("variants", {}).keys())

    def list_libraries(self) -> List[LibraryInfo]:
        """List all available libraries."""
        libraries = []
        for organism, org_data in self.registry.get("libraries", {}).items():
            for variant, var_data in org_data.get("variants", {}).items():
                lib_info = self._make_library_info(organism, org_data, variant, var_data)
                libraries.append(lib_info)
        return libraries

    def get_library_info(self, organism: str, variant: str = "reviewed") -> Optional[LibraryInfo]:
        """
        Get information about a specific library.

        Args:
            organism: Organism key (e.g., "human", "mouse")
            variant: Library variant (e.g., "reviewed", "full", "phospho")

        Returns:
            LibraryInfo object or None if not found
        """
        org_data = self.registry.get("libraries", {}).get(organism)
        if not org_data:
            logger.warning(f"Organism not found: {organism}")
            return None

        var_data = org_data.get("variants", {}).get(variant)
        if not var_data:
            logger.warning(f"Variant not found: {organism}/{variant}")
            return None

        return self._make_library_info(organism, org_data, variant, var_data)

    def get_recommended_library(self, organism: str) -> Optional[LibraryInfo]:
        """
        Get the recommended library for an organism.

        Args:
            organism: Organism key (e.g., "human", "mouse")

        Returns:
            LibraryInfo for recommended variant, or first available
        """
        org_data = self.registry.get("libraries", {}).get(organism)
        if not org_data:
            return None

        # Find recommended variant
        for variant, var_data in org_data.get("variants", {}).items():
            if var_data.get("recommended", False):
                return self._make_library_info(organism, org_data, variant, var_data)

        # Fall back to first variant
        variants = org_data.get("variants", {})
        if variants:
            variant = list(variants.keys())[0]
            return self._make_library_info(organism, org_data, variant, variants[variant])

        return None

    def _make_library_info(self, organism: str, org_data: Dict, variant: str, var_data: Dict) -> LibraryInfo:
        """Create LibraryInfo from registry data."""
        filename = var_data.get("filename", "")
        url = f"{self.base_url}/{self.speclib_prefix}/{organism}/{filename}" if self.base_url else ""

        return LibraryInfo(
            organism=organism,
            organism_name=org_data.get("organism", organism),
            taxonomy_id=org_data.get("taxonomy_id"),
            variant=variant,
            name=var_data.get("name", ""),
            description=var_data.get("description", ""),
            filename=filename,
            url=url,
            proteins=var_data.get("proteins", 0),
            peptides=var_data.get("peptides", 0),
            file_size_bytes=var_data.get("file_size_bytes", 0),
            file_size_human=var_data.get("file_size_human", ""),
            md5=var_data.get("md5"),
            enzyme=var_data.get("enzyme", "trypsin"),
            missed_cleavages=var_data.get("missed_cleavages", 1),
            fixed_mods=var_data.get("fixed_mods", []),
            variable_mods=var_data.get("variable_mods", []),
            diann_version=var_data.get("diann_version", ""),
            uniprot_version=var_data.get("uniprot_version", ""),
            recommended=var_data.get("recommended", False)
        )

    def get_cached_path(self, organism: str, variant: str = "reviewed") -> Path:
        """Get the local cache path for a library."""
        lib_info = self.get_library_info(organism, variant)
        if not lib_info:
            raise ValueError(f"Library not found: {organism}/{variant}")
        return self.cache_dir / organism / lib_info.filename

    def is_cached(self, organism: str, variant: str = "reviewed") -> bool:
        """Check if a library is already cached locally."""
        cache_path = self.get_cached_path(organism, variant)
        return cache_path.exists()

    def download_library(
        self,
        organism: str,
        variant: str = "reviewed",
        force: bool = False,
        progress_callback: Optional[callable] = None
    ) -> Path:
        """
        Download a spectral library.

        Args:
            organism: Organism key
            variant: Library variant
            force: Force re-download even if cached
            progress_callback: Optional callback(downloaded_bytes, total_bytes)

        Returns:
            Path to the downloaded library file
        """
        lib_info = self.get_library_info(organism, variant)
        if not lib_info:
            raise ValueError(f"Library not found: {organism}/{variant}")

        cache_path = self.get_cached_path(organism, variant)

        # Check cache
        if cache_path.exists() and not force:
            logger.info(f"Library already cached: {cache_path}")
            return cache_path

        # Create directory
        cache_path.parent.mkdir(parents=True, exist_ok=True)

        # Download
        logger.info(f"Downloading {lib_info.name} ({lib_info.file_size_human})...")

        if not lib_info.url:
            raise ValueError(f"No download URL for library: {organism}/{variant}")

        try:
            if progress_callback:
                def reporthook(block_num, block_size, total_size):
                    downloaded = block_num * block_size
                    progress_callback(downloaded, total_size)
                urlretrieve(lib_info.url, cache_path, reporthook=reporthook)
            else:
                urlretrieve(lib_info.url, cache_path)
        except URLError as e:
            logger.error(f"Failed to download library: {e}")
            raise

        # Validate MD5 if available
        if lib_info.md5:
            if not self._validate_md5(cache_path, lib_info.md5):
                cache_path.unlink()
                raise ValueError(f"MD5 validation failed for {cache_path}")

        logger.info(f"Library downloaded: {cache_path}")
        return cache_path

    def _validate_md5(self, file_path: Path, expected_md5: str) -> bool:
        """Validate file MD5 checksum."""
        md5 = hashlib.md5()
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b''):
                md5.update(chunk)
        return md5.hexdigest() == expected_md5

    def check_compatibility(
        self,
        organism: str,
        variant: str,
        enzyme: str,
        fixed_mods: List[str],
        variable_mods: List[str]
    ) -> Tuple[bool, List[str]]:
        """
        Check if a library is compatible with analysis parameters.

        Returns:
            Tuple of (is_compatible, list of warnings/differences)
        """
        lib_info = self.get_library_info(organism, variant)
        if not lib_info:
            return False, [f"Library not found: {organism}/{variant}"]

        warnings = []

        # Check enzyme
        if enzyme.lower() != lib_info.enzyme.lower():
            warnings.append(f"Enzyme mismatch: library={lib_info.enzyme}, requested={enzyme}")

        # Check fixed modifications
        lib_fixed = set(m.lower() for m in lib_info.fixed_mods)
        req_fixed = set(m.lower() for m in fixed_mods)
        if lib_fixed != req_fixed:
            warnings.append(f"Fixed mods differ: library={lib_info.fixed_mods}, requested={fixed_mods}")

        # Check variable modifications (requested should be subset of library)
        lib_var = set(m.lower() for m in lib_info.variable_mods)
        req_var = set(m.lower() for m in variable_mods)
        if not req_var.issubset(lib_var):
            missing = req_var - lib_var
            warnings.append(f"Variable mods not in library: {missing}")

        is_compatible = len(warnings) == 0
        return is_compatible, warnings

    def get_download_command(self, organism: str, variant: str = "reviewed") -> str:
        """Get the wget/curl command to download a library."""
        lib_info = self.get_library_info(organism, variant)
        if not lib_info or not lib_info.url:
            return ""

        return f"wget -O {lib_info.filename} '{lib_info.url}'"

    def clear_cache(self, organism: Optional[str] = None):
        """Clear cached libraries."""
        if organism:
            cache_path = self.cache_dir / organism
            if cache_path.exists():
                import shutil
                shutil.rmtree(cache_path)
                logger.info(f"Cleared cache for {organism}")
        else:
            import shutil
            if self.cache_dir.exists():
                shutil.rmtree(self.cache_dir)
                self.cache_dir.mkdir(parents=True, exist_ok=True)
                logger.info("Cleared all cached libraries")

    def check_s3_availability(self, organism: str, variant: str = "reviewed") -> Tuple[bool, Optional[int]]:
        """
        Check if a library is available in S3.

        Returns:
            Tuple of (is_available, file_size_bytes or None)
        """
        lib_info = self.get_library_info(organism, variant)
        if not lib_info or not lib_info.url:
            return False, None

        try:
            # Use HEAD request to check availability without downloading
            from urllib.request import Request
            req = Request(lib_info.url, method='HEAD')
            with urlopen(req, timeout=10) as response:
                size = response.headers.get('Content-Length')
                return True, int(size) if size else None
        except (HTTPError, URLError) as e:
            logger.debug(f"Library not available: {e}")
            return False, None

    def check_all_availability(self) -> Dict[str, Dict[str, Tuple[bool, Optional[int]]]]:
        """
        Check availability of all libraries.

        Returns:
            Dict of {organism: {variant: (is_available, size)}}
        """
        results = {}
        for lib in self.list_libraries():
            if lib.organism not in results:
                results[lib.organism] = {}
            available, size = self.check_s3_availability(lib.organism, lib.variant)
            results[lib.organism][lib.variant] = (available, size)
        return results

    def get_s3_bucket(self) -> str:
        """Get the S3 bucket name."""
        return self.registry.get("s3_bucket", "")

    def get_s3_path(self, organism: str, variant: str = "reviewed") -> str:
        """Get the S3 path for a library."""
        lib_info = self.get_library_info(organism, variant)
        if not lib_info:
            return ""
        return f"s3://{self.get_s3_bucket()}/{self.speclib_prefix}/{organism}/{lib_info.filename}"


def main():
    """CLI interface for library manager."""
    import argparse

    parser = argparse.ArgumentParser(description="Manage DIA-NN spectral libraries")
    subparsers = parser.add_subparsers(dest="command")

    # List command
    list_parser = subparsers.add_parser("list", help="List available libraries")
    list_parser.add_argument("--organism", help="Filter by organism")

    # Info command
    info_parser = subparsers.add_parser("info", help="Get library info")
    info_parser.add_argument("organism", help="Organism (e.g., human, mouse)")
    info_parser.add_argument("--variant", default="reviewed", help="Library variant")

    # Download command
    dl_parser = subparsers.add_parser("download", help="Download a library")
    dl_parser.add_argument("organism", help="Organism to download")
    dl_parser.add_argument("--variant", default="reviewed", help="Library variant")
    dl_parser.add_argument("--force", action="store_true", help="Force re-download")

    # Status command
    status_parser = subparsers.add_parser("status", help="Check availability of libraries in S3")
    status_parser.add_argument("--organism", help="Filter by organism")

    args = parser.parse_args()

    manager = SpectralLibraryManager()

    if args.command == "list":
        for lib in manager.list_libraries():
            if args.organism and lib.organism != args.organism:
                continue
            rec = " [RECOMMENDED]" if lib.recommended else ""
            print(f"{lib.organism}/{lib.variant}: {lib.name} ({lib.file_size_human}){rec}")

    elif args.command == "info":
        lib = manager.get_library_info(args.organism, args.variant)
        if lib:
            print(f"Name: {lib.name}")
            print(f"Organism: {lib.organism_name}")
            print(f"Proteins: {lib.proteins:,}")
            print(f"Peptides: {lib.peptides:,}")
            print(f"Size: {lib.file_size_human}")
            print(f"Enzyme: {lib.enzyme}")
            print(f"Fixed mods: {', '.join(lib.fixed_mods)}")
            print(f"Variable mods: {', '.join(lib.variable_mods)}")
            print(f"DIA-NN version: {lib.diann_version}")
            print(f"URL: {lib.url}")
        else:
            print(f"Library not found: {args.organism}/{args.variant}")

    elif args.command == "download":
        def progress(downloaded, total):
            pct = (downloaded / total * 100) if total > 0 else 0
            print(f"\rDownloading: {pct:.1f}%", end="", flush=True)

        try:
            path = manager.download_library(args.organism, args.variant, args.force, progress)
            print(f"\nDownloaded to: {path}")
        except Exception as e:
            print(f"\nError: {e}")

    elif args.command == "status":
        print("Checking library availability in S3...\n")
        for lib in manager.list_libraries():
            if args.organism and lib.organism != args.organism:
                continue
            available, size = manager.check_s3_availability(lib.organism, lib.variant)
            if available:
                size_mb = size / (1024 * 1024) if size else 0
                status = f"✓ AVAILABLE ({size_mb:.1f} MB)"
            else:
                status = "✗ PENDING GENERATION"
            rec = " [RECOMMENDED]" if lib.recommended else ""
            print(f"{lib.organism}/{lib.variant}: {status}{rec}")
            print(f"  S3 path: {manager.get_s3_path(lib.organism, lib.variant)}")

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
