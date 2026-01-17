"""
Galaxy Notebook Integration

Provides simple get/put interface for Galaxy datasets within Jupyter notebooks.

Usage in notebook:
    from galaxy_notebook import get, put, list_inputs

    # Get input dataset (by index or name)
    df = get(0)  # First input
    df = get("counts.tsv")  # By name

    # Put output back to Galaxy
    put(df, name="results.tsv")
    put("figure.png", name="Volcano Plot")
"""

from .galaxy_io import get, put, list_inputs, get_metadata, GalaxyConnection

__version__ = "1.0.0"
__all__ = ["get", "put", "list_inputs", "get_metadata", "GalaxyConnection"]
