"""
Kubernetes storage implementation using Persistent Volumes.
"""

import asyncio
import base64
from typing import Dict, Any, Optional, AsyncIterator
from pathlib import Path
from urllib.parse import urlparse

from kubernetes_asyncio import client, config
from kubernetes_asyncio.client import ApiClient, V1PersistentVolume, V1PersistentVolumeClaim, V1Pod
from kubernetes_asyncio.client.rest import ApiException

from galaxy_cloud.core.storage import CloudStorage, CloudPath
from galaxy_cloud.registry import cloud_storage
from galaxy_cloud.providers.k8s.auth import K8sAuth


@cloud_storage("k8s-pv", {
    "description": "Kubernetes Persistent Volume storage provider",
    "supported_features": [
        "persistent_volumes", "dynamic_provisioning", "storage_classes",
        "volume_snapshots", "volume_cloning", "expansion"
    ],
    "version": "1.0.0"
})
class K8sPVStorage(CloudStorage):
    """Kubernetes Persistent Volume storage implementation."""
    
    def __init__(self, config: Dict[str, Any], **kwargs):
        super().__init__(config, **kwargs)
        
        # Kubernetes configuration
        self.namespace = config.get('namespace', 'default')
        self.kubeconfig_path = config.get('kubeconfig_path')
        self.context = config.get('context')
        
        # Storage configuration
        self.storage_class = config.get('storage_class', 'standard')
        self.access_modes = config.get('access_modes', ['ReadWriteOnce'])
        self.volume_mode = config.get('volume_mode', 'Filesystem')
        
        # PVC configuration
        self.pvc_name_prefix = config.get('pvc_name_prefix', 'galaxy-data')
        self.default_volume_size = config.get('default_volume_size', '10Gi')
        
        # Helper pod configuration for file operations
        self.helper_image = config.get('helper_image', 'busybox:latest')
        self.helper_pod_prefix = config.get('helper_pod_prefix', 'galaxy-storage-helper')
        
        # Labels and annotations
        self.default_labels = config.get('labels', {})
        self.default_annotations = config.get('annotations', {})
        
        # Internal state
        self.api_client: Optional[ApiClient] = None
        self.core_v1: Optional[client.CoreV1Api] = None
        self.storage_v1: Optional[client.StorageV1Api] = None
        self.auth_provider: Optional[K8sAuth] = None
        
    async def initialize(self) -> None:
        """Initialize Kubernetes client and authentication."""
        self.auth_provider = K8sAuth(self.config)
        await self.auth_provider.initialize()
        
        # Load Kubernetes configuration
        if self.kubeconfig_path:
            await config.load_kube_config(config_file=self.kubeconfig_path, context=self.context)
        else:
            try:
                # Try in-cluster config first
                config.load_incluster_config()
                self.logger.info("Using in-cluster Kubernetes configuration")
            except config.ConfigException:
                # Fall back to default kubeconfig
                await config.load_kube_config(context=self.context)
                self.logger.info("Using default kubeconfig")
        
        # Initialize API clients
        self.api_client = ApiClient()
        self.core_v1 = client.CoreV1Api(self.api_client)
        self.storage_v1 = client.StorageV1Api(self.api_client)
        
        self._initialized = True
        self.logger.info(f"K8s PV Storage initialized for namespace: {self.namespace}")
    
    async def cleanup(self) -> None:
        """Clean up Kubernetes resources."""
        if self.api_client:
            await self.api_client.close()
            
        if self.auth_provider:
            await self.auth_provider.cleanup()
        
        self._initialized = False
        self.logger.info("K8s PV Storage cleaned up")
    
    @property
    def scheme(self) -> str:
        return "k8s-pv"
    
    def parse_uri(self, uri: str) -> Optional[CloudPath]:
        """Parse Kubernetes PV URI."""
        if not uri.startswith('k8s-pv://'):
            return None
        
        return CloudPath(uri, self)
    
    def _parse_k8s_uri(self, uri: str) -> tuple[str, str]:
        """Parse k8s-pv URI into PVC name and path."""
        if not uri.startswith('k8s-pv://'):
            raise ValueError(f"Invalid K8s PV URI format: {uri}")
        
        path = uri[9:]  # Remove k8s-pv://
        
        if '/' not in path:
            return path, ''
        
        parts = path.split('/', 1)
        return parts[0], parts[1]
    
    async def exists(self, uri: str) -> bool:
        """Check if PVC or file exists."""
        try:
            pvc_name, file_path = self._parse_k8s_uri(uri)
            
            if not file_path:
                # Check if PVC exists
                try:
                    await self.core_v1.read_namespaced_persistent_volume_claim(
                        name=pvc_name,
                        namespace=self.namespace
                    )
                    return True
                except ApiException as e:
                    if e.status == 404:
                        return False
                    raise
            else:
                # Check if file exists in PVC
                return await self._file_exists_in_pvc(pvc_name, file_path)
                
        except Exception as e:
            self.logger.error(f"Failed to check existence of {uri}: {e}")
            return False
    
    async def stat(self, uri: str) -> Dict[str, Any]:
        """Get PVC or file metadata and properties."""
        try:
            pvc_name, file_path = self._parse_k8s_uri(uri)
            
            if not file_path:
                # Get PVC properties
                pvc = await self.core_v1.read_namespaced_persistent_volume_claim(
                    name=pvc_name,
                    namespace=self.namespace
                )
                
                return {
                    'type': 'pvc',
                    'name': pvc_name,
                    'namespace': self.namespace,
                    'created': pvc.metadata.creation_timestamp,
                    'storage_class': pvc.spec.storage_class_name,
                    'access_modes': pvc.spec.access_modes,
                    'volume_mode': pvc.spec.volume_mode,
                    'capacity': pvc.status.capacity.get('storage') if pvc.status.capacity else None,
                    'phase': pvc.status.phase,
                    'volume_name': pvc.spec.volume_name,
                    'labels': pvc.metadata.labels or {},
                    'annotations': pvc.metadata.annotations or {}
                }
            else:
                # Get file properties from PVC
                file_info = await self._get_file_info_in_pvc(pvc_name, file_path)
                return file_info
                
        except Exception as e:
            self.logger.error(f"Failed to get properties for {uri}: {e}")
            raise
    
    async def read_bytes(self, uri: str) -> bytes:
        """Read file content from PVC as bytes."""
        try:
            pvc_name, file_path = self._parse_k8s_uri(uri)
            
            if not file_path:
                raise ValueError("Cannot read bytes from PVC root - specify a file path")
            
            return await self._read_file_from_pvc(pvc_name, file_path)
            
        except Exception as e:
            self.logger.error(f"Failed to read {uri}: {e}")
            raise
    
    async def write_bytes(self, uri: str, data: bytes) -> None:
        """Write bytes to file in PVC."""
        try:
            pvc_name, file_path = self._parse_k8s_uri(uri)
            
            if not file_path:
                raise ValueError("Cannot write bytes to PVC root - specify a file path")
            
            # Ensure PVC exists
            await self._ensure_pvc(pvc_name)
            
            # Write file to PVC
            await self._write_file_to_pvc(pvc_name, file_path, data)
            
            self.logger.debug(f"Wrote {len(data)} bytes to {uri}")
            
        except Exception as e:
            self.logger.error(f"Failed to write to {uri}: {e}")
            raise
    
    async def upload_file(self, local_path: str, remote_uri: str, **kwargs) -> None:
        """Upload file to PVC."""
        try:
            local_file = Path(local_path)
            if not local_file.exists():
                raise FileNotFoundError(f"Local file not found: {local_path}")
            
            pvc_name, file_path = self._parse_k8s_uri(remote_uri)
            
            if not file_path:
                # Use local filename if no remote path specified
                file_path = local_file.name
            
            # Ensure PVC exists
            await self._ensure_pvc(pvc_name)
            
            # Read local file and upload
            with open(local_path, 'rb') as f:
                data = f.read()
            
            await self._write_file_to_pvc(pvc_name, file_path, data)
            
            file_size = local_file.stat().st_size
            self.logger.info(f"Uploaded {local_path} ({file_size} bytes) to {remote_uri}")
            
        except Exception as e:
            self.logger.error(f"Failed to upload {local_path} to {remote_uri}: {e}")
            raise
    
    async def download_file(self, remote_uri: str, local_path: str, **kwargs) -> None:
        """Download file from PVC."""
        try:
            pvc_name, file_path = self._parse_k8s_uri(remote_uri)
            
            if not file_path:
                raise ValueError("Cannot download PVC root - specify a file path")
            
            # Ensure local directory exists
            local_file = Path(local_path)
            local_file.parent.mkdir(parents=True, exist_ok=True)
            
            # Download file from PVC
            data = await self._read_file_from_pvc(pvc_name, file_path)
            
            with open(local_path, 'wb') as f:
                f.write(data)
            
            file_size = local_file.stat().st_size
            self.logger.info(f"Downloaded {remote_uri} to {local_path} ({file_size} bytes)")
            
        except Exception as e:
            self.logger.error(f"Failed to download {remote_uri} to {local_path}: {e}")
            raise
    
    async def delete(self, uri: str) -> None:
        """Delete PVC or file."""
        try:
            pvc_name, file_path = self._parse_k8s_uri(uri)
            
            if not file_path:
                # Delete PVC
                await self.core_v1.delete_namespaced_persistent_volume_claim(
                    name=pvc_name,
                    namespace=self.namespace
                )
                self.logger.info(f"Deleted PVC: {pvc_name}")
            else:
                # Delete file in PVC
                await self._delete_file_in_pvc(pvc_name, file_path)
                self.logger.info(f"Deleted file: {uri}")
                
        except Exception as e:
            self.logger.error(f"Failed to delete {uri}: {e}")
            raise
    
    async def list_files(self, prefix_uri: str, recursive: bool = True) -> AsyncIterator[str]:
        """List files in PVC with given prefix."""
        try:
            pvc_name, path_prefix = self._parse_k8s_uri(prefix_uri)
            
            files = await self._list_files_in_pvc(pvc_name, path_prefix, recursive)
            
            for file_path in files:
                yield f"k8s-pv://{pvc_name}/{file_path}"
                
        except Exception as e:
            self.logger.error(f"Failed to list files with prefix {prefix_uri}: {e}")
            raise
    
    async def copy_file(self, source_uri: str, dest_uri: str, **kwargs) -> None:
        """Copy file within or between PVCs."""
        try:
            source_pvc, source_path = self._parse_k8s_uri(source_uri)
            dest_pvc, dest_path = self._parse_k8s_uri(dest_uri)
            
            if not source_path or not dest_path:
                raise ValueError("Both source and destination must specify file paths")
            
            # Ensure destination PVC exists
            await self._ensure_pvc(dest_pvc)
            
            # Copy file
            await self._copy_file_between_pvcs(source_pvc, source_path, dest_pvc, dest_path)
            
            self.logger.info(f"Copied {source_uri} to {dest_uri}")
                
        except Exception as e:
            self.logger.error(f"Failed to copy {source_uri} to {dest_uri}: {e}")
            raise
    
    async def sync_upload(self, local_dir: Path, remote_prefix: str, **kwargs) -> None:
        """Synchronize local directory to PVC."""
        try:
            local_path = Path(local_dir)
            if not local_path.is_dir():
                raise ValueError(f"Local path is not a directory: {local_dir}")
            
            pvc_name, path_prefix = self._parse_k8s_uri(remote_prefix)
            
            # Ensure PVC exists
            await self._ensure_pvc(pvc_name)
            
            # Get all local files
            local_files = []
            for file_path in local_path.rglob('*'):
                if file_path.is_file():
                    relative_path = file_path.relative_to(local_path)
                    local_files.append((file_path, relative_path))
            
            # Upload files
            for local_file_path, relative_path in local_files:
                remote_path = f"{path_prefix}/{relative_path}".strip('/')
                remote_uri = f"k8s-pv://{pvc_name}/{remote_path}"
                await self.upload_file(str(local_file_path), remote_uri)
            
            self.logger.info(f"Synchronized {len(local_files)} files from {local_dir} to {remote_prefix}")
            
        except Exception as e:
            self.logger.error(f"Failed to sync upload {local_dir} to {remote_prefix}: {e}")
            raise
    
    async def sync_download(self, remote_prefix: str, local_dir: Path, **kwargs) -> None:
        """Synchronize PVC to local directory."""
        try:
            local_path = Path(local_dir)
            local_path.mkdir(parents=True, exist_ok=True)
            
            pvc_name, path_prefix = self._parse_k8s_uri(remote_prefix)
            
            # List all remote files
            remote_files = []
            async for file_uri in self.list_files(remote_prefix):
                _, file_path = self._parse_k8s_uri(file_uri)
                if file_path.startswith(path_prefix):
                    relative_path = file_path[len(path_prefix):].lstrip('/')
                    remote_files.append((file_uri, relative_path))
            
            # Download files
            for remote_uri, relative_path in remote_files:
                local_file_path = local_path / relative_path
                await self.download_file(remote_uri, str(local_file_path))
            
            self.logger.info(f"Synchronized {len(remote_files)} files from {remote_prefix} to {local_dir}")
            
        except Exception as e:
            self.logger.error(f"Failed to sync download {remote_prefix} to {local_dir}: {e}")
            raise
    
    # PVC management methods
    
    async def create_pvc(self, pvc_name: str, size: str = None, storage_class: str = None) -> None:
        """Create a new PVC."""
        try:
            size = size or self.default_volume_size
            storage_class = storage_class or self.storage_class
            
            pvc = client.V1PersistentVolumeClaim(
                api_version='v1',
                kind='PersistentVolumeClaim',
                metadata=client.V1ObjectMeta(
                    name=pvc_name,
                    namespace=self.namespace,
                    labels=self._merge_labels({}),
                    annotations=self._merge_annotations({})
                ),
                spec=client.V1PersistentVolumeClaimSpec(
                    access_modes=self.access_modes,
                    storage_class_name=storage_class,
                    volume_mode=self.volume_mode,
                    resources=client.V1ResourceRequirements(
                        requests={'storage': size}
                    )
                )
            )
            
            await self.core_v1.create_namespaced_persistent_volume_claim(
                namespace=self.namespace,
                body=pvc
            )
            
            self.logger.info(f"Created PVC: {pvc_name} ({size})")
            
        except Exception as e:
            self.logger.error(f"Failed to create PVC {pvc_name}: {e}")
            raise
    
    async def expand_pvc(self, pvc_name: str, new_size: str) -> None:
        """Expand an existing PVC."""
        try:
            # Get current PVC
            pvc = await self.core_v1.read_namespaced_persistent_volume_claim(
                name=pvc_name,
                namespace=self.namespace
            )
            
            # Update storage request
            pvc.spec.resources.requests['storage'] = new_size
            
            # Patch PVC
            await self.core_v1.patch_namespaced_persistent_volume_claim(
                name=pvc_name,
                namespace=self.namespace,
                body=pvc
            )
            
            self.logger.info(f"Expanded PVC {pvc_name} to {new_size}")
            
        except Exception as e:
            self.logger.error(f"Failed to expand PVC {pvc_name}: {e}")
            raise
    
    # Helper methods for file operations using helper pods
    
    async def _ensure_pvc(self, pvc_name: str) -> None:
        """Ensure PVC exists, create if it doesn't."""
        try:
            await self.core_v1.read_namespaced_persistent_volume_claim(
                name=pvc_name,
                namespace=self.namespace
            )
            self.logger.debug(f"Using existing PVC: {pvc_name}")
            
        except ApiException as e:
            if e.status == 404:
                await self.create_pvc(pvc_name)
            else:
                raise
    
    async def _create_helper_pod(self, pvc_name: str, operation: str) -> str:
        """Create a helper pod for file operations."""
        pod_name = f"{self.helper_pod_prefix}-{operation}-{pvc_name}-{int(asyncio.get_event_loop().time())}"
        
        pod = client.V1Pod(
            api_version='v1',
            kind='Pod',
            metadata=client.V1ObjectMeta(
                name=pod_name,
                namespace=self.namespace,
                labels=self._merge_labels({'operation': operation, 'pvc': pvc_name})
            ),
            spec=client.V1PodSpec(
                restart_policy='Never',
                containers=[
                    client.V1Container(
                        name='helper',
                        image=self.helper_image,
                        command=['/bin/sh'],
                        args=['-c', 'sleep 3600'],  # Keep pod alive
                        volume_mounts=[
                            client.V1VolumeMount(
                                name='data',
                                mount_path='/data'
                            )
                        ]
                    )
                ],
                volumes=[
                    client.V1Volume(
                        name='data',
                        persistent_volume_claim=client.V1PersistentVolumeClaimVolumeSource(
                            claim_name=pvc_name
                        )
                    )
                ]
            )
        )
        
        await self.core_v1.create_namespaced_pod(
            namespace=self.namespace,
            body=pod
        )
        
        # Wait for pod to be ready
        await self._wait_for_pod_ready(pod_name)
        
        return pod_name
    
    async def _wait_for_pod_ready(self, pod_name: str, timeout: int = 300) -> None:
        """Wait for pod to be ready."""
        start_time = asyncio.get_event_loop().time()
        
        while True:
            if asyncio.get_event_loop().time() - start_time > timeout:
                raise TimeoutError(f"Pod {pod_name} did not become ready within {timeout} seconds")
            
            try:
                pod = await self.core_v1.read_namespaced_pod(
                    name=pod_name,
                    namespace=self.namespace
                )
                
                if pod.status.phase == 'Running':
                    # Check if containers are ready
                    if pod.status.container_statuses:
                        all_ready = all(cs.ready for cs in pod.status.container_statuses)
                        if all_ready:
                            break
                elif pod.status.phase in ['Failed', 'Succeeded']:
                    raise RuntimeError(f"Pod {pod_name} failed to start: {pod.status.phase}")
                
            except ApiException:
                pass
            
            await asyncio.sleep(2)
    
    async def _delete_helper_pod(self, pod_name: str) -> None:
        """Delete helper pod."""
        try:
            await self.core_v1.delete_namespaced_pod(
                name=pod_name,
                namespace=self.namespace
            )
        except ApiException:
            pass  # Pod might already be deleted
    
    async def _execute_in_pod(self, pod_name: str, command: List[str]) -> str:
        """Execute command in pod and return output."""
        from kubernetes_asyncio.stream import stream
        
        try:
            exec_response = await stream(
                self.core_v1.connect_get_namespaced_pod_exec,
                pod_name,
                self.namespace,
                command=command,
                stderr=True,
                stdin=False,
                stdout=True,
                tty=False
            )
            
            return exec_response
            
        except Exception as e:
            self.logger.error(f"Failed to execute command in pod {pod_name}: {e}")
            raise
    
    async def _file_exists_in_pvc(self, pvc_name: str, file_path: str) -> bool:
        """Check if file exists in PVC."""
        pod_name = None
        try:
            pod_name = await self._create_helper_pod(pvc_name, 'check')
            
            command = ['test', '-f', f'/data/{file_path}']
            
            try:
                await self._execute_in_pod(pod_name, command)
                return True
            except:
                return False
                
        finally:
            if pod_name:
                await self._delete_helper_pod(pod_name)
    
    async def _get_file_info_in_pvc(self, pvc_name: str, file_path: str) -> Dict[str, Any]:
        """Get file information from PVC."""
        pod_name = None
        try:
            pod_name = await self._create_helper_pod(pvc_name, 'stat')
            
            command = ['stat', '-c', '%s,%Y,%A', f'/data/{file_path}']
            output = await self._execute_in_pod(pod_name, command)
            
            size, mtime, permissions = output.strip().split(',')
            
            return {
                'type': 'file',
                'name': file_path,
                'pvc': pvc_name,
                'size': int(size),
                'modified': datetime.fromtimestamp(int(mtime)),
                'permissions': permissions
            }
            
        finally:
            if pod_name:
                await self._delete_helper_pod(pod_name)
    
    async def _read_file_from_pvc(self, pvc_name: str, file_path: str) -> bytes:
        """Read file content from PVC."""
        pod_name = None
        try:
            pod_name = await self._create_helper_pod(pvc_name, 'read')
            
            command = ['cat', f'/data/{file_path}']
            output = await self._execute_in_pod(pod_name, command)
            
            return output.encode('utf-8')
            
        finally:
            if pod_name:
                await self._delete_helper_pod(pod_name)
    
    async def _write_file_to_pvc(self, pvc_name: str, file_path: str, data: bytes) -> None:
        """Write file content to PVC."""
        pod_name = None
        try:
            pod_name = await self._create_helper_pod(pvc_name, 'write')
            
            # Encode data as base64 to safely pass through shell
            encoded_data = base64.b64encode(data).decode('ascii')
            
            # Create directory if needed
            dir_path = str(Path(file_path).parent)
            if dir_path != '.':
                mkdir_command = ['mkdir', '-p', f'/data/{dir_path}']
                await self._execute_in_pod(pod_name, mkdir_command)
            
            # Write file
            command = ['sh', '-c', f'echo "{encoded_data}" | base64 -d > /data/{file_path}']
            await self._execute_in_pod(pod_name, command)
            
        finally:
            if pod_name:
                await self._delete_helper_pod(pod_name)
    
    async def _delete_file_in_pvc(self, pvc_name: str, file_path: str) -> None:
        """Delete file in PVC."""
        pod_name = None
        try:
            pod_name = await self._create_helper_pod(pvc_name, 'delete')
            
            command = ['rm', '-f', f'/data/{file_path}']
            await self._execute_in_pod(pod_name, command)
            
        finally:
            if pod_name:
                await self._delete_helper_pod(pod_name)
    
    async def _list_files_in_pvc(self, pvc_name: str, path_prefix: str, recursive: bool) -> List[str]:
        """List files in PVC."""
        pod_name = None
        try:
            pod_name = await self._create_helper_pod(pvc_name, 'list')
            
            if recursive:
                command = ['find', f'/data/{path_prefix}', '-type', 'f']
            else:
                command = ['ls', '-1', f'/data/{path_prefix}']
            
            output = await self._execute_in_pod(pod_name, command)
            
            files = []
            for line in output.strip().split('\n'):
                if line:
                    # Remove /data/ prefix
                    file_path = line[6:] if line.startswith('/data/') else line
                    files.append(file_path)
            
            return files
            
        finally:
            if pod_name:
                await self._delete_helper_pod(pod_name)
    
    async def _copy_file_between_pvcs(self, source_pvc: str, source_path: str, dest_pvc: str, dest_path: str) -> None:
        """Copy file between PVCs."""
        pod_name = None
        try:
            # Create pod with both PVCs mounted
            pod_name = await self._create_copy_helper_pod(source_pvc, dest_pvc)
            
            # Create destination directory if needed
            dest_dir = str(Path(dest_path).parent)
            if dest_dir != '.':
                mkdir_command = ['mkdir', '-p', f'/dest/{dest_dir}']
                await self._execute_in_pod(pod_name, mkdir_command)
            
            # Copy file
            command = ['cp', f'/source/{source_path}', f'/dest/{dest_path}']
            await self._execute_in_pod(pod_name, command)
            
        finally:
            if pod_name:
                await self._delete_helper_pod(pod_name)
    
    async def _create_copy_helper_pod(self, source_pvc: str, dest_pvc: str) -> str:
        """Create helper pod for copying between PVCs."""
        pod_name = f"{self.helper_pod_prefix}-copy-{int(asyncio.get_event_loop().time())}"
        
        volumes = [
            client.V1Volume(
                name='source',
                persistent_volume_claim=client.V1PersistentVolumeClaimVolumeSource(
                    claim_name=source_pvc
                )
            )
        ]
        
        volume_mounts = [
            client.V1VolumeMount(
                name='source',
                mount_path='/source',
                read_only=True
            )
        ]
        
        if source_pvc != dest_pvc:
            volumes.append(
                client.V1Volume(
                    name='dest',
                    persistent_volume_claim=client.V1PersistentVolumeClaimVolumeSource(
                        claim_name=dest_pvc
                    )
                )
            )
            volume_mounts.append(
                client.V1VolumeMount(
                    name='dest',
                    mount_path='/dest'
                )
            )
        else:
            # Same PVC, mount as both source and dest
            volume_mounts.append(
                client.V1VolumeMount(
                    name='source',
                    mount_path='/dest'
                )
            )
        
        pod = client.V1Pod(
            api_version='v1',
            kind='Pod',
            metadata=client.V1ObjectMeta(
                name=pod_name,
                namespace=self.namespace,
                labels=self._merge_labels({'operation': 'copy'})
            ),
            spec=client.V1PodSpec(
                restart_policy='Never',
                containers=[
                    client.V1Container(
                        name='helper',
                        image=self.helper_image,
                        command=['/bin/sh'],
                        args=['-c', 'sleep 3600'],
                        volume_mounts=volume_mounts
                    )
                ],
                volumes=volumes
            )
        )
        
        await self.core_v1.create_namespaced_pod(
            namespace=self.namespace,
            body=pod
        )
        
        await self._wait_for_pod_ready(pod_name)
        
        return pod_name
    
    def _merge_labels(self, job_labels: Dict[str, str]) -> Dict[str, str]:
        """Merge job labels with default labels."""
        labels = self.default_labels.copy()
        labels.update(job_labels)
        
        labels.update({
            'created-by': 'galaxy-cloud-executor',
            'provider': 'k8s-pv'
        })
        
        return labels
    
    def _merge_annotations(self, job_annotations: Dict[str, str]) -> Dict[str, str]:
        """Merge job annotations with default annotations."""
        annotations = self.default_annotations.copy()
        annotations.update(job_annotations)
        return annotations