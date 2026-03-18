"""
Dataset ID Resolver

Converts Galaxy dataset IDs to physical file paths for workflow execution.

Supports multiple path formats:
1. dataset_id:xxx - Galaxy dataset ID (converted to physical path)
2. s3://bucket/path - S3 path (passed through)
3. /absolute/path - Absolute path (passed through)
4. Relative paths - Passed through as-is

Safety:
- User-isolated: Only resolves datasets owned by the requesting user
- Read-only: Never modifies datasets
- Auditable: All resolutions are logged
"""

import logging
import re
from typing import Any, Optional

log = logging.getLogger(__name__)


class DatasetResolver:
    """
    Resolves dataset references to physical file paths

    Usage:
        resolver = DatasetResolver(trans)
        path = resolver.resolve("dataset_id:f2db41e1fa331b3e")
        # Returns: /path/to/database/objects/f/2/d/dataset_xxx.dat
    """

    # Regex pattern for dataset_id: format
    DATASET_ID_PATTERN = re.compile(r'^dataset_id:([a-zA-Z0-9]+)$')

    def __init__(self, trans):
        """
        Initialize resolver

        Args:
            trans: Galaxy transaction context (ProvidesUserContext)
        """
        self.trans = trans
        self.app = trans.app
        self.sa_session = trans.sa_session
        self.security = trans.security

    def resolve(self, path_or_id: str) -> str:
        """
        Resolve a path/ID to a physical file path

        Args:
            path_or_id: Path string in one of the supported formats

        Returns:
            Physical file path

        Raises:
            ValueError: If dataset_id is invalid or not found
        """
        if not path_or_id:
            raise ValueError("Empty path or dataset ID")

        # Check if it's a dataset_id: format
        match = self.DATASET_ID_PATTERN.match(path_or_id.strip())
        if match:
            dataset_id = match.group(1)
            return self._resolve_dataset_id(dataset_id)

        # Check if it's an S3 path
        if path_or_id.startswith('s3://'):
            log.debug(f"S3 path detected, passing through: {path_or_id}")
            return path_or_id

        # Check if it's an absolute path
        if path_or_id.startswith('/'):
            log.debug(f"Absolute path detected, passing through: {path_or_id}")
            return path_or_id

        # Otherwise, treat as relative path or other format
        log.debug(f"Relative path or other format, passing through: {path_or_id}")
        return path_or_id

    def _resolve_dataset_id(self, encoded_id: str) -> str:
        """
        Resolve Galaxy dataset ID to physical path

        Args:
            encoded_id: Encoded Galaxy dataset ID

        Returns:
            Physical file path

        Raises:
            ValueError: If dataset not found or user doesn't have access
        """
        from galaxy.model import HistoryDatasetAssociation

        try:
            # Decode the dataset ID
            decoded_id = self.security.decode_id(encoded_id)

            # Query the dataset
            hda = self.sa_session.query(HistoryDatasetAssociation).get(decoded_id)

            if not hda:
                raise ValueError(f"Dataset not found: {encoded_id}")

            # Security check: Verify user owns this dataset
            if hda.history.user_id != self.trans.user.id:
                raise ValueError(f"Access denied: Dataset {encoded_id} does not belong to current user")

            # Check dataset state
            if hda.deleted:
                raise ValueError(f"Dataset {encoded_id} is deleted")

            if hda.state != 'ok':
                log.warning(f"Dataset {encoded_id} state is '{hda.state}', may not be ready")

            # Get physical file path
            file_path = hda.get_file_name()

            if not file_path:
                raise ValueError(f"Dataset {encoded_id} has no file path")

            log.info(f"✅ Resolved dataset_id:{encoded_id} → {file_path}")
            log.info(f"   Dataset name: {hda.name}")
            log.info(f"   Dataset extension: {hda.extension}")
            log.info(f"   Dataset state: {hda.state}")

            return file_path

        except Exception as e:
            log.error(f"Failed to resolve dataset ID {encoded_id}: {e}", exc_info=True)
            raise ValueError(f"Failed to resolve dataset {encoded_id}: {str(e)}")

    def resolve_dict(self, params: dict) -> dict:
        """
        Resolve all dataset_id: references in a parameter dictionary

        Args:
            params: Dictionary of workflow parameters

        Returns:
            New dictionary with resolved paths
        """
        resolved = {}

        for key, value in params.items():
            if isinstance(value, str):
                try:
                    resolved[key] = self.resolve(value)
                except Exception as e:
                    log.error(f"Failed to resolve parameter '{key}': {e}")
                    # Keep original value if resolution fails
                    resolved[key] = value
            elif isinstance(value, dict):
                # Recursively resolve nested dictionaries
                resolved[key] = self.resolve_dict(value)
            elif isinstance(value, list):
                # Resolve items in lists
                resolved[key] = [
                    self.resolve(item) if isinstance(item, str) else item
                    for item in value
                ]
            else:
                # Keep non-string values as-is
                resolved[key] = value

        return resolved


def resolve_dataset_paths(trans, params: dict) -> dict:
    """
    Convenience function to resolve dataset paths in workflow parameters

    Usage:
        from galaxy.ai.workflow_ops.dataset_resolver import resolve_dataset_paths

        # In your API endpoint:
        resolved_params = resolve_dataset_paths(trans, user_params)

    Args:
        trans: Galaxy transaction context
        params: Workflow parameters

    Returns:
        Parameters with resolved dataset paths
    """
    resolver = DatasetResolver(trans)
    return resolver.resolve_dict(params)
