"""
Galaxy I/O functions for notebook integration.

Environment variables (set by Galaxy when launching interactive tool):
    GALAXY_URL: Galaxy server URL
    GALAXY_API_KEY: User's API key (injected by Galaxy)
    HISTORY_ID: Current Galaxy history ID
    INPUT_PATHS: Comma-separated list of input file paths
"""

import os
import json
import pandas as pd
from pathlib import Path
from typing import Union, Optional, List, Dict, Any
import logging

logger = logging.getLogger(__name__)

# Input files passed by Galaxy (mounted in container)
_INPUT_DIR = Path("/import")
_OUTPUT_DIR = Path("/export")
_INPUT_CACHE: Dict[str, Path] = {}


class GalaxyConnection:
    """Connection to Galaxy server for API operations."""

    def __init__(
        self,
        url: Optional[str] = None,
        api_key: Optional[str] = None,
        history_id: Optional[str] = None
    ):
        self.url = url or os.environ.get("GALAXY_URL", "")
        self.api_key = api_key or os.environ.get("GALAXY_API_KEY", "")
        self.history_id = history_id or os.environ.get("HISTORY_ID", "")
        self._gi = None

    @property
    def gi(self):
        """Lazy-load bioblend GalaxyInstance."""
        if self._gi is None:
            try:
                from bioblend.galaxy import GalaxyInstance
                self._gi = GalaxyInstance(self.url, self.api_key)
            except ImportError:
                raise ImportError("bioblend not installed. Run: pip install bioblend")
            except Exception as e:
                raise ConnectionError(f"Failed to connect to Galaxy: {e}")
        return self._gi

    def upload_file(self, file_path: str, name: Optional[str] = None) -> Dict:
        """Upload a file to Galaxy history."""
        if not self.history_id:
            raise ValueError("HISTORY_ID not set")

        name = name or Path(file_path).name
        result = self.gi.tools.upload_file(
            file_path,
            self.history_id,
            file_name=name
        )
        return result

    def get_dataset(self, dataset_id: str) -> Dict:
        """Get dataset metadata."""
        return self.gi.datasets.show_dataset(dataset_id)


# Global connection instance
_connection: Optional[GalaxyConnection] = None


def _get_connection() -> GalaxyConnection:
    """Get or create Galaxy connection."""
    global _connection
    if _connection is None:
        _connection = GalaxyConnection()
    return _connection


def _discover_inputs() -> Dict[str, Path]:
    """Discover input files in the import directory."""
    global _INPUT_CACHE

    if _INPUT_CACHE:
        return _INPUT_CACHE

    # Check for input files in /import (Galaxy mounts inputs here)
    if _INPUT_DIR.exists():
        for f in _INPUT_DIR.iterdir():
            if f.is_file():
                _INPUT_CACHE[f.name] = f

    # Also check INPUT_PATHS environment variable
    input_paths = os.environ.get("INPUT_PATHS", "")
    if input_paths:
        for path_str in input_paths.split(","):
            path = Path(path_str.strip())
            if path.exists():
                _INPUT_CACHE[path.name] = path

    return _INPUT_CACHE


def list_inputs() -> List[Dict[str, Any]]:
    """
    List available input files.

    Returns:
        List of dicts with 'index', 'name', 'path', 'size' keys
    """
    inputs = _discover_inputs()
    result = []
    for i, (name, path) in enumerate(inputs.items()):
        result.append({
            "index": i,
            "name": name,
            "path": str(path),
            "size": path.stat().st_size if path.exists() else 0
        })
    return result


def get(
    identifier: Union[int, str],
    format: Optional[str] = None
) -> Union[pd.DataFrame, str, bytes, Path]:
    """
    Get an input dataset from Galaxy.

    Args:
        identifier: Index (0-based) or filename of the input
        format: Force specific format ('df', 'text', 'bytes', 'path')
                If None, auto-detect based on file extension

    Returns:
        - DataFrame for tabular files (.tsv, .csv, .txt)
        - String for text files
        - Bytes for binary files
        - Path if format='path'

    Examples:
        df = get(0)  # Get first input as DataFrame
        df = get("counts.tsv")  # Get by name
        path = get(0, format='path')  # Get file path
    """
    inputs = _discover_inputs()

    # Resolve identifier to path
    if isinstance(identifier, int):
        if identifier >= len(inputs):
            raise IndexError(f"Input index {identifier} out of range. "
                           f"Available: {len(inputs)} inputs")
        path = list(inputs.values())[identifier]
    else:
        # Search by name (exact or partial match)
        path = inputs.get(identifier)
        if path is None:
            # Try partial match
            for name, p in inputs.items():
                if identifier in name:
                    path = p
                    break
        if path is None:
            raise FileNotFoundError(f"Input '{identifier}' not found. "
                                   f"Available: {list(inputs.keys())}")

    # Return path if requested
    if format == 'path':
        return path

    # Auto-detect format based on extension
    suffix = path.suffix.lower()

    if format == 'df' or suffix in ['.tsv', '.csv', '.txt', '.tab', '.tabular']:
        # Tabular data -> DataFrame
        sep = ',' if suffix == '.csv' else '\t'
        try:
            return pd.read_csv(path, sep=sep)
        except Exception:
            # Try with different separators
            return pd.read_csv(path, sep=None, engine='python')

    elif format == 'text' or suffix in ['.fasta', '.fa', '.fastq', '.fq', '.gff', '.gtf', '.bed', '.vcf', '.sam']:
        # Text files
        return path.read_text()

    elif format == 'bytes' or suffix in ['.bam', '.h5', '.hdf5', '.h5ad', '.gz', '.zip']:
        # Binary files
        return path.read_bytes()

    else:
        # Default: try as DataFrame, fallback to text
        try:
            return pd.read_csv(path, sep='\t')
        except Exception:
            return path.read_text()


def put(
    data: Union[pd.DataFrame, str, bytes, Path],
    name: str,
    format: Optional[str] = None,
    upload_to_galaxy: bool = True
) -> Path:
    """
    Save output data and optionally upload to Galaxy history.

    Args:
        data: Data to save (DataFrame, string, bytes, or path to existing file)
        name: Output filename
        format: For DataFrames, 'tsv' or 'csv' (default: tsv)
        upload_to_galaxy: Whether to upload to Galaxy history

    Returns:
        Path to the saved file

    Examples:
        put(df, "results.tsv")
        put(fig, "volcano.png")  # matplotlib figure
        put("report.html", "Analysis Report")
    """
    # Ensure output directory exists
    _OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    output_path = _OUTPUT_DIR / name

    # Handle different data types
    if isinstance(data, pd.DataFrame):
        # DataFrame -> TSV/CSV
        sep = ',' if (format == 'csv' or name.endswith('.csv')) else '\t'
        data.to_csv(output_path, sep=sep, index=False)

    elif isinstance(data, bytes):
        # Binary data
        output_path.write_bytes(data)

    elif isinstance(data, str):
        if Path(data).exists():
            # It's a file path - copy it
            import shutil
            shutil.copy(data, output_path)
        else:
            # It's text content
            output_path.write_text(data)

    elif isinstance(data, Path):
        # Copy existing file
        import shutil
        shutil.copy(data, output_path)

    elif hasattr(data, 'savefig'):
        # Matplotlib figure
        data.savefig(output_path, dpi=150, bbox_inches='tight')

    else:
        raise TypeError(f"Unsupported data type: {type(data)}")

    logger.info(f"Saved output: {output_path}")

    # Upload to Galaxy if requested and connection available
    if upload_to_galaxy:
        try:
            conn = _get_connection()
            if conn.url and conn.api_key and conn.history_id:
                conn.upload_file(str(output_path), name)
                logger.info(f"Uploaded to Galaxy: {name}")
        except Exception as e:
            logger.warning(f"Failed to upload to Galaxy: {e}")

    return output_path


def get_metadata(identifier: Union[int, str]) -> Dict[str, Any]:
    """
    Get metadata for an input dataset.

    Returns dict with 'name', 'format', 'size', 'path' etc.
    """
    inputs = _discover_inputs()

    if isinstance(identifier, int):
        if identifier >= len(inputs):
            raise IndexError(f"Input index {identifier} out of range")
        name = list(inputs.keys())[identifier]
        path = list(inputs.values())[identifier]
    else:
        name = identifier
        path = inputs.get(identifier)
        if path is None:
            raise FileNotFoundError(f"Input '{identifier}' not found")

    stat = path.stat()
    return {
        "name": name,
        "path": str(path),
        "size": stat.st_size,
        "format": path.suffix.lstrip('.'),
        "modified": stat.st_mtime,
    }
