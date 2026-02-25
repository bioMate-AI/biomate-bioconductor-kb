"""
Nextflow Tool Synchronizer

同步Galaxy工具定义到S3,供galaxy-tool-runner容器使用
"""

import os
import logging
import hashlib
from pathlib import Path
from typing import Dict, Optional, List
import glob

logger = logging.getLogger(__name__)


class NextflowToolSynchronizer:
    """同步Galaxy工具定义到S3"""

    def __init__(self, s3_client, bucket: str, galaxy_root: str = None):
        """
        初始化工具同步器

        Args:
            s3_client: boto3 S3 client
            bucket: S3 bucket名称
            galaxy_root: Galaxy根目录路径
        """
        self.s3_client = s3_client
        self.bucket = bucket
        self.galaxy_root = galaxy_root or os.environ.get('GALAXY_ROOT', '/galaxy')

        # 缓存已同步的工具,避免重复上传
        self._sync_cache: Dict[str, str] = {}

        logger.info(f"Initialized NextflowToolSynchronizer with bucket={bucket}, galaxy_root={galaxy_root}")

    def _calculate_file_hash(self, file_path: str) -> str:
        """计算文件MD5哈希"""
        hash_md5 = hashlib.md5()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()

    def _upload_file(self, local_path: str, s3_key: str) -> bool:
        """上传单个文件到S3"""
        try:
            logger.info(f"Uploading {local_path} -> s3://{self.bucket}/{s3_key}")
            self.s3_client.upload_file(local_path, self.bucket, s3_key)
            return True
        except Exception as e:
            logger.error(f"Failed to upload {local_path}: {e}")
            return False

    def _find_tool_xml(self, tool_id: str) -> Optional[str]:
        """
        查找工具XML定义文件

        Args:
            tool_id: 工具ID,例如 "cat1" 或 "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73"

        Returns:
            工具XML文件路径,如果未找到返回None
        """
        # 策略1: 从工具ID直接映射
        # 简化的工具名称(例如 cat1, filter1)
        simple_tool_paths = [
            f"{self.galaxy_root}/tools/{tool_id}/{tool_id}.xml",
            f"{self.galaxy_root}/tools/{tool_id}.xml",
        ]

        for path in simple_tool_paths:
            if os.path.exists(path):
                logger.info(f"Found tool XML for {tool_id}: {path}")
                return path

        # 策略2: Tool Shed格式
        # toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73
        if "toolshed" in tool_id and "/" in tool_id:
            parts = tool_id.split("/")
            if len(parts) >= 4:
                owner = parts[2]
                repo = parts[3]
                tool_name = parts[4] if len(parts) > 4 else repo

                shed_paths = [
                    f"{self.galaxy_root}/shed_tools/{owner}/{repo}/{tool_name}.xml",
                    f"{self.galaxy_root}/tool_deps/{owner}/{repo}/{tool_name}.xml",
                ]

                for path in shed_paths:
                    if os.path.exists(path):
                        logger.info(f"Found tool XML for {tool_id}: {path}")
                        return path

        # 策略3: 全局搜索(最后手段)
        logger.warning(f"Tool XML not found in standard locations for {tool_id}, trying global search...")
        search_pattern = f"{self.galaxy_root}/**/*.xml"
        for xml_path in glob.glob(search_pattern, recursive=True):
            # 读取XML文件检查tool id
            try:
                import xml.etree.ElementTree as ET
                tree = ET.parse(xml_path)
                root = tree.getroot()
                if root.get('id') == tool_id or root.get('id', '').endswith(tool_id):
                    logger.info(f"Found tool XML via global search: {xml_path}")
                    return xml_path
            except Exception:
                continue

        logger.error(f"Failed to find tool XML for {tool_id}")
        return None

    def sync_tool_to_s3(self, tool_id: str, tool_xml_path: Optional[str] = None) -> Optional[str]:
        """
        同步工具定义到S3

        Args:
            tool_id: Galaxy工具ID
            tool_xml_path: 工具XML路径(可选,如果不提供则自动查找)

        Returns:
            S3 URI (s3://bucket/tools/tool_id/tool.xml) 或 None表示失败
        """
        # 检查缓存
        if tool_id in self._sync_cache:
            logger.info(f"Tool {tool_id} already synced: {self._sync_cache[tool_id]}")
            return self._sync_cache[tool_id]

        # 查找工具XML
        if tool_xml_path is None:
            tool_xml_path = self._find_tool_xml(tool_id)
            if tool_xml_path is None:
                # 无法找到工具定义,使用占位符
                logger.warning(f"Creating placeholder tool definition for {tool_id}")
                return self._create_placeholder_tool(tool_id)

        # 验证文件存在
        if not os.path.exists(tool_xml_path):
            logger.error(f"Tool XML not found: {tool_xml_path}")
            return None

        # 计算安全的S3 key (处理特殊字符)
        safe_tool_id = tool_id.replace('/', '_').replace(':', '_')
        s3_base = f"tools/{safe_tool_id}"

        # 上传工具XML
        s3_xml_key = f"{s3_base}/tool.xml"
        if not self._upload_file(tool_xml_path, s3_xml_key):
            return None

        s3_uri = f"s3://{self.bucket}/{s3_xml_key}"

        # 上传相关的脚本文件和数据文件
        tool_dir = os.path.dirname(tool_xml_path)
        self._sync_tool_dependencies(tool_dir, s3_base)

        # 缓存结果
        self._sync_cache[tool_id] = s3_uri

        logger.info(f"Successfully synced tool {tool_id} to {s3_uri}")
        return s3_uri

    def _sync_tool_dependencies(self, tool_dir: str, s3_base: str) -> None:
        """同步工具的依赖文件(Python脚本、R脚本等)"""
        if not os.path.isdir(tool_dir):
            return

        # 需要同步的文件扩展名
        dependency_patterns = ['*.py', '*.R', '*.pl', '*.sh', '*.rb']

        for pattern in dependency_patterns:
            for file_path in glob.glob(os.path.join(tool_dir, pattern)):
                filename = os.path.basename(file_path)
                s3_key = f"{s3_base}/{filename}"
                self._upload_file(file_path, s3_key)

    def _create_placeholder_tool(self, tool_id: str) -> str:
        """
        为找不到定义的工具创建占位符

        Args:
            tool_id: 工具ID

        Returns:
            S3 URI
        """
        import tempfile
        import xml.etree.ElementTree as ET

        # 创建简单的占位符工具XML
        tool_elem = ET.Element('tool', {
            'id': tool_id,
            'name': f'Placeholder for {tool_id}',
            'version': '1.0.0'
        })

        command_elem = ET.SubElement(tool_elem, 'command')
        command_elem.text = "echo 'Placeholder execution for tool {tool_id}' > $output"

        inputs_elem = ET.SubElement(tool_elem, 'inputs')
        outputs_elem = ET.SubElement(tool_elem, 'outputs')

        output_elem = ET.SubElement(outputs_elem, 'data', {
            'name': 'output',
            'format': 'txt'
        })

        # 写入临时文件
        tree = ET.ElementTree(tool_elem)
        with tempfile.NamedTemporaryFile(mode='w', suffix='.xml', delete=False) as f:
            tree.write(f, encoding='unicode')
            temp_path = f.name

        try:
            # 上传到S3
            safe_tool_id = tool_id.replace('/', '_').replace(':', '_')
            s3_key = f"tools/{safe_tool_id}/tool.xml"
            self._upload_file(temp_path, s3_key)

            s3_uri = f"s3://{self.bucket}/{s3_key}"
            self._sync_cache[tool_id] = s3_uri

            logger.info(f"Created placeholder tool definition for {tool_id}: {s3_uri}")
            return s3_uri
        finally:
            os.unlink(temp_path)

    def batch_sync_tools(self, tool_ids: List[str]) -> Dict[str, Optional[str]]:
        """
        批量同步多个工具

        Args:
            tool_ids: 工具ID列表

        Returns:
            字典: {tool_id: s3_uri or None}
        """
        results = {}
        for tool_id in tool_ids:
            results[tool_id] = self.sync_tool_to_s3(tool_id)

        synced = sum(1 for uri in results.values() if uri is not None)
        logger.info(f"Batch sync completed: {synced}/{len(tool_ids)} tools synced successfully")

        return results

    def clear_cache(self):
        """清除同步缓存"""
        self._sync_cache.clear()
        logger.info("Sync cache cleared")

    def get_synced_tools(self) -> Dict[str, str]:
        """获取已同步的工具列表"""
        return self._sync_cache.copy()
