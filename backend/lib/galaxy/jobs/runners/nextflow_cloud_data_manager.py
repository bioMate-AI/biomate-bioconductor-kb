"""
Cloud-Native Data Manager for Galaxy-Nextflow Integration

This module implements cloud-native data management where:
1. Data stays in S3 throughout the workflow execution
2. Galaxy only stores metadata (S3 URIs, not actual data)
3. Users access results via S3 presigned URLs (direct access, no download to Galaxy)
4. Fallback to local download only for small files (<100MB) if requested

Architecture:
    User → Galaxy UI → Display S3 metadata
             ↓
         Click Download
             ↓
     Generate Presigned URL → Redirect to S3 (direct access)

Author: Galaxy Cloud Executor Team
"""

import logging
import boto3
import json
import os
from typing import Dict, List, Optional, Any
from pathlib import Path
from datetime import datetime, timedelta


class CloudDataManager:
    """
    Cloud-native data manager for Galaxy workflows.

    Manages workflow outputs that remain in cloud storage (S3) without
    downloading to the Galaxy server.
    """

    def __init__(self, app, s3_client=None, bucket=None):
        """
        Initialize cloud data manager.

        Args:
            app: Galaxy app instance
            s3_client: boto3 S3 client (optional, will create if not provided)
            bucket: S3 bucket name (optional, will read from config)
        """
        self.app = app
        self.logger = logging.getLogger(__name__)

        # S3 configuration
        if s3_client is None:
            try:
                self.s3_client = boto3.client('s3')
            except Exception as e:
                self.logger.warning(f"Failed to create S3 client: {e}")
                self.s3_client = None
        else:
            self.s3_client = s3_client

        # S3 bucket
        if bucket is None:
            self.bucket = os.environ.get('AWS_S3_BUCKET', 'galaxy-cloud-data-1760241377')
        else:
            self.bucket = bucket

        self.logger.info(f"✅ CloudDataManager initialized (bucket: {self.bucket})")

    def create_workflow_output_metadata(
        self,
        workflow_invocation_id: int,
        workflow_dir: str,
        history
    ) -> Dict[str, Any]:
        """
        Create metadata for workflow outputs WITHOUT downloading data.

        This method:
        1. Lists S3 objects in the workflow output directory
        2. Creates Galaxy dataset records with cloud_uri
        3. Returns metadata for UI display

        Args:
            workflow_invocation_id: Galaxy workflow invocation ID
            workflow_dir: Nextflow workflow directory path
            history: Galaxy history object

        Returns:
            Dict with output metadata:
            {
                'outputs': [
                    {
                        'name': 'output1.txt',
                        's3_uri': 's3://bucket/path/output1.txt',
                        'size': 12345,
                        'dataset_id': 456
                    },
                    ...
                ],
                'total_size': 67890,
                'total_files': 5
            }
        """
        self.logger.info(f"Creating output metadata for workflow {workflow_invocation_id}")

        if not self.s3_client:
            self.logger.error("S3 client not available")
            return {'outputs': [], 'total_size': 0, 'total_files': 0}

        try:
            # Parse S3 path from workflow directory
            # workflow_dir might be: /path/to/galaxy/database/jobs_directory/nextflow_workflows/workflow_243
            workflow_id = workflow_dir.split('/')[-1].replace('workflow_', '')

            # List S3 outputs
            s3_prefix = f"nextflow_workflows/{workflow_id}/outputs/"
            s3_outputs = self._list_s3_outputs(s3_prefix)

            # Create Galaxy datasets for each output (metadata only, no download)
            outputs = []
            total_size = 0

            for s3_obj in s3_outputs:
                s3_uri = f"s3://{self.bucket}/{s3_obj['Key']}"
                filename = os.path.basename(s3_obj['Key'])
                size = s3_obj['Size']

                # Create cloud dataset (no download!)
                dataset = self._create_cloud_dataset(
                    history=history,
                    s3_uri=s3_uri,
                    filename=filename,
                    size=size
                )

                outputs.append({
                    'name': filename,
                    's3_uri': s3_uri,
                    'size': size,
                    'dataset_id': dataset.id if dataset else None,
                    'created': s3_obj.get('LastModified', datetime.now()).isoformat()
                })

                total_size += size

            result = {
                'outputs': outputs,
                'total_size': total_size,
                'total_files': len(outputs),
                's3_prefix': f"s3://{self.bucket}/{s3_prefix}",
                'workflow_invocation_id': workflow_invocation_id
            }

            self.logger.info(f"✅ Created metadata for {len(outputs)} outputs (total: {self._format_size(total_size)})")
            return result

        except Exception as e:
            self.logger.error(f"Failed to create output metadata: {e}", exc_info=True)
            return {'outputs': [], 'total_size': 0, 'total_files': 0, 'error': str(e)}

    def _list_s3_outputs(self, prefix: str) -> List[Dict]:
        """
        List S3 objects under a prefix.

        Args:
            prefix: S3 key prefix (e.g., 'nextflow_workflows/243/outputs/')

        Returns:
            List of S3 object metadata dicts
        """
        try:
            response = self.s3_client.list_objects_v2(
                Bucket=self.bucket,
                Prefix=prefix
            )

            if 'Contents' not in response:
                self.logger.warning(f"No outputs found in S3 at {prefix}")
                return []

            # Filter out directories (keys ending with '/')
            objects = [
                obj for obj in response['Contents']
                if not obj['Key'].endswith('/')
            ]

            self.logger.debug(f"Found {len(objects)} output files in S3")
            return objects

        except Exception as e:
            self.logger.error(f"Failed to list S3 outputs: {e}")
            return []

    def _create_cloud_dataset(
        self,
        history,
        s3_uri: str,
        filename: str,
        size: int = 0
    ):
        """
        Create a Galaxy dataset that references S3 data WITHOUT downloading.

        This creates a "cloud-backed" dataset where:
        - dataset.dataset.cloud_uri = s3_uri
        - dataset.state = 'ok'
        - No actual file is downloaded to Galaxy server

        Args:
            history: Galaxy history object
            s3_uri: S3 URI (e.g., 's3://bucket/path/file.txt')
            filename: Display filename
            size: File size in bytes

        Returns:
            Galaxy HistoryDatasetAssociation object or None
        """
        try:
            from galaxy.model import HistoryDatasetAssociation

            # Create dataset
            hda = self.app.model.HistoryDatasetAssociation(
                history=history,
                name=filename,
                extension='auto',  # Auto-detect extension
                state='ok',  # Mark as complete (data is in S3)
                blurb='Cloud dataset (S3)',
                info='Data stored in S3, access via presigned URL'
            )

            # Set cloud URI (this is the key!)
            # Store S3 location instead of downloading
            hda.dataset.cloud_uri = s3_uri

            # Set file size (for display purposes)
            hda.dataset.total_size = size

            # Persist to database
            self.app.sa_session.add(hda)
            self.app.sa_session.flush()

            self.logger.info(f"✅ Created cloud dataset: {filename} ({s3_uri})")
            return hda

        except Exception as e:
            self.logger.error(f"Failed to create cloud dataset for {filename}: {e}", exc_info=True)
            return None

    def generate_presigned_url(
        self,
        s3_uri: str,
        expiration: int = 3600,
        response_content_disposition: Optional[str] = None
    ) -> Optional[str]:
        """
        Generate S3 presigned URL for direct user access.

        This allows users to download files directly from S3 without
        routing through the Galaxy server.

        Args:
            s3_uri: S3 URI (e.g., 's3://bucket/path/file.txt')
            expiration: URL expiration time in seconds (default: 1 hour)
            response_content_disposition: Optional Content-Disposition header
                (e.g., 'attachment; filename="myfile.txt"')

        Returns:
            Presigned URL string or None if failed
        """
        if not self.s3_client:
            self.logger.error("S3 client not available")
            return None

        try:
            # Parse S3 URI
            if not s3_uri.startswith('s3://'):
                self.logger.error(f"Invalid S3 URI: {s3_uri}")
                return None

            # Extract bucket and key
            s3_uri_parts = s3_uri.replace('s3://', '').split('/', 1)
            if len(s3_uri_parts) != 2:
                self.logger.error(f"Invalid S3 URI format: {s3_uri}")
                return None

            bucket, key = s3_uri_parts

            # Generate presigned URL
            params = {
                'Bucket': bucket,
                'Key': key
            }

            if response_content_disposition:
                params['ResponseContentDisposition'] = response_content_disposition

            url = self.s3_client.generate_presigned_url(
                'get_object',
                Params=params,
                ExpiresIn=expiration
            )

            self.logger.debug(f"Generated presigned URL for {key} (expires in {expiration}s)")
            return url

        except Exception as e:
            self.logger.error(f"Failed to generate presigned URL for {s3_uri}: {e}")
            return None

    def get_dataset_download_url(self, dataset, expiration: int = 3600) -> Optional[str]:
        """
        Get download URL for a cloud-backed dataset.

        Args:
            dataset: Galaxy HistoryDatasetAssociation object
            expiration: URL expiration in seconds

        Returns:
            Presigned S3 URL or None
        """
        try:
            # Check if dataset has cloud URI
            if hasattr(dataset.dataset, 'cloud_uri') and dataset.dataset.cloud_uri:
                s3_uri = dataset.dataset.cloud_uri

                # Generate filename for download
                filename = dataset.name or 'download'

                # Generate presigned URL with content disposition
                url = self.generate_presigned_url(
                    s3_uri,
                    expiration=expiration,
                    response_content_disposition=f'attachment; filename="{filename}"'
                )

                return url
            else:
                self.logger.debug(f"Dataset {dataset.id} is not cloud-backed")
                return None

        except Exception as e:
            self.logger.error(f"Failed to get download URL for dataset {dataset.id}: {e}")
            return None

    def should_download_locally(self, size: int, threshold: int = 100 * 1024 * 1024) -> bool:
        """
        Determine if a file should be downloaded locally instead of staying in S3.

        Small files (<100MB by default) can be downloaded to Galaxy for faster access.

        Args:
            size: File size in bytes
            threshold: Size threshold in bytes (default: 100MB)

        Returns:
            True if file should be downloaded locally
        """
        return size < threshold

    def download_from_s3(self, s3_uri: str, local_path: str) -> bool:
        """
        Download a file from S3 to local path.

        This is a fallback method for small files or when local access is needed.

        Args:
            s3_uri: S3 URI (e.g., 's3://bucket/path/file.txt')
            local_path: Local filesystem path

        Returns:
            True if download succeeded
        """
        if not self.s3_client:
            self.logger.error("S3 client not available")
            return False

        try:
            # Parse S3 URI
            s3_uri_parts = s3_uri.replace('s3://', '').split('/', 1)
            if len(s3_uri_parts) != 2:
                self.logger.error(f"Invalid S3 URI format: {s3_uri}")
                return False

            bucket, key = s3_uri_parts

            # Create directory if needed
            os.makedirs(os.path.dirname(local_path), exist_ok=True)

            # Download file
            self.logger.info(f"Downloading {s3_uri} to {local_path}")
            self.s3_client.download_file(bucket, key, local_path)

            self.logger.info(f"✅ Downloaded {key} ({self._format_size(os.path.getsize(local_path))})")
            return True

        except Exception as e:
            self.logger.error(f"Failed to download {s3_uri}: {e}")
            return False

    def get_output_summary(self, workflow_invocation_id: int) -> Dict:
        """
        Get summary of workflow outputs for UI display.

        Args:
            workflow_invocation_id: Workflow invocation ID

        Returns:
            Dict with summary info
        """
        try:
            # Query datasets for this workflow invocation
            # This would typically query the database for HDAs associated with the invocation
            from galaxy.model import WorkflowInvocation

            invocation = self.app.sa_session.query(WorkflowInvocation).get(workflow_invocation_id)
            if not invocation:
                return {'error': 'Workflow invocation not found'}

            # Get output datasets
            outputs = []
            total_size = 0

            for step_output in invocation.output_values:
                if hasattr(step_output, 'dataset') and step_output.dataset:
                    dataset = step_output.dataset

                    # Check if cloud-backed
                    is_cloud = hasattr(dataset.dataset, 'cloud_uri') and dataset.dataset.cloud_uri

                    outputs.append({
                        'dataset_id': dataset.id,
                        'name': dataset.name,
                        'extension': dataset.extension,
                        'state': dataset.state,
                        'size': dataset.dataset.total_size,
                        'is_cloud': is_cloud,
                        's3_uri': dataset.dataset.cloud_uri if is_cloud else None
                    })

                    total_size += dataset.dataset.total_size

            return {
                'outputs': outputs,
                'total_size': total_size,
                'total_files': len(outputs),
                'formatted_size': self._format_size(total_size)
            }

        except Exception as e:
            self.logger.error(f"Failed to get output summary: {e}")
            return {'error': str(e)}

    @staticmethod
    def _format_size(size: int) -> str:
        """Format byte size as human-readable string."""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if size < 1024.0:
                return f"{size:.2f} {unit}"
            size /= 1024.0
        return f"{size:.2f} PB"
