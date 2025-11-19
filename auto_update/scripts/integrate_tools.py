#!/usr/bin/env python3
"""
Tool Integrator - Add auto-discovered tools to Galaxy database

Integrates:
- Tool metadata into galaxy_ai_tools.db
- Tool wrappers into tool repository
- Generate embeddings for semantic search
- Update RAG system

Usage:
    python integrate_tools.py --wrapper data/wrappers/tool.xml --metadata tool_meta.json
    python integrate_tools.py --directory data/wrappers/ --batch
"""

import argparse
import json
import logging
import sqlite3
from pathlib import Path
from typing import Dict, List, Optional
from xml.etree import ElementTree as ET

# Import comprehensive metadata extractor
from metadata_extractor_comprehensive import ComprehensiveMetadataExtractor

# Import duplication detector
from duplication_detector import DuplicationDetector

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class DatabaseIntegrator:
    """
    Integrates tools into Galaxy AI tools database.
    """

    def __init__(self, db_path: Path, enable_duplicate_check: bool = True):
        self.db_path = db_path
        self.conn = None
        self.enable_duplicate_check = enable_duplicate_check

        # Initialize duplication detector
        if enable_duplicate_check:
            self.dup_detector = DuplicationDetector(db_path)
        else:
            self.dup_detector = None

    def connect(self):
        """Connect to database"""
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row

    def close(self):
        """Close database connection"""
        if self.conn:
            self.conn.close()

    def tool_exists(self, tool_id: str) -> bool:
        """Check if tool already exists in database"""
        cursor = self.conn.cursor()
        cursor.execute(
            "SELECT tool_id FROM tools WHERE tool_id = ?",
            (tool_id,)
        )
        return cursor.fetchone() is not None

    def add_tool(self, complete_metadata: Dict, source_metadata: Dict = None) -> bool:
        """
        Add tool to database with complete metadata (all 38 fields).

        Args:
            complete_metadata: Complete metadata dictionary from ComprehensiveMetadataExtractor
            source_metadata: Original metadata from detector (for duplication checking)

        Returns:
            True if successful
        """
        try:
            cursor = self.conn.cursor()

            tool_id = complete_metadata['tool_id']

            # Check if tool already exists by tool_id
            if self.tool_exists(tool_id):
                logger.warning(f"Tool {tool_id} already exists, skipping")
                return "duplicate"

            # Check for duplicates using duplication detector
            if self.dup_detector and source_metadata:
                is_duplicate, existing_tools = self.dup_detector.check_duplicate(source_metadata)

                if is_duplicate:
                    # Get suggested action
                    action = self.dup_detector.suggest_action(existing_tools, source_metadata)

                    best_match = existing_tools[0]
                    logger.warning(
                        f"Potential duplicate detected for {complete_metadata['name']}: "
                        f"similar to {best_match['name']} ({best_match['tool_id']}) "
                        f"- similarity: {best_match['similarity']:.0%}, "
                        f"match_type: {best_match['match_type']}"
                    )

                    if action == "skip":
                        logger.info(f"Skipping {tool_id} due to duplication")
                        return "duplicate"
                    elif action == "update":
                        logger.info(f"Tool {tool_id} should be updated (not implemented yet)")
                        return "duplicate"  # For now, skip updates
                    # If action == "add_as_new", continue with insertion

            # Insert tool with ALL fields from galaxy_ai_tools.db schema
            cursor.execute('''
                INSERT INTO tools (
                    tool_id, name, version, description,
                    repo_owner, repo_name, url, category,
                    rawText, htmlContent,
                    created_at, updated_at, data_version,
                    is_dataset, dataset_metadata,
                    parameters, help_text, inputs, outputs, requirements, tool_state_template,
                    citations, edam_operations, edam_topics, tags, examples, usage_guide, scientific_context,
                    nfcore_metadata,
                    auto_discovered, discovery_date, quality_score, github_url, wrapper_path, topics, language, stars
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                # Basic identification (1-4)
                complete_metadata['tool_id'],
                complete_metadata['name'],
                complete_metadata['version'],
                complete_metadata['description'],

                # Repository information (5-8)
                complete_metadata['repo_owner'],
                complete_metadata['repo_name'],
                complete_metadata['url'],
                complete_metadata['category'],

                # RAG content (9-10)
                complete_metadata['rawText'],
                complete_metadata['htmlContent'],

                # Timestamps (11-13)
                complete_metadata['created_at'],
                complete_metadata['updated_at'],
                complete_metadata['data_version'],

                # Dataset flags (14-15)
                complete_metadata['is_dataset'],
                complete_metadata['dataset_metadata'],

                # Critical tool metadata (16-21)
                complete_metadata['parameters'],
                complete_metadata['help_text'],
                complete_metadata['inputs'],
                complete_metadata['outputs'],
                complete_metadata['requirements'],
                complete_metadata['tool_state_template'],

                # Documentation (22-29)
                complete_metadata['citations'],
                complete_metadata['edam_operations'],
                complete_metadata['edam_topics'],
                complete_metadata['tags'],
                complete_metadata['examples'],
                complete_metadata['usage_guide'],
                complete_metadata['scientific_context'],
                complete_metadata['nfcore_metadata'],

                # Auto-discovery fields (30-37)
                complete_metadata['auto_discovered'],
                complete_metadata['discovery_date'],
                complete_metadata['quality_score'],
                complete_metadata['github_url'],
                complete_metadata['wrapper_path'],
                complete_metadata['topics'],
                complete_metadata['language'],
                complete_metadata['stars']
            ))

            self.conn.commit()
            logger.info(f"Added tool {tool_id} to database with complete metadata (38 fields)")
            return "success"

        except sqlite3.IntegrityError as e:
            logger.error(f"Database integrity error: {e}")
            return "error"
        except Exception as e:
            logger.error(f"Error adding tool to database: {e}")
            logger.error(f"Tool ID: {complete_metadata.get('tool_id', 'unknown')}")
            self.conn.rollback()
            return "error"

    def _parse_wrapper(self, wrapper_path: Path) -> tuple:
        """Extract version and command from wrapper"""
        try:
            tree = ET.parse(wrapper_path)
            root = tree.getroot()

            version = root.get('version', '1.0.0')

            command_elem = root.find('command')
            command = command_elem.text if command_elem is not None else ''

            return version, command
        except Exception as e:
            logger.warning(f"Could not parse wrapper: {e}")
            return '1.0.0', ''

    def ensure_schema(self):
        """Ensure database has required schema for auto-discovered tools"""
        try:
            cursor = self.conn.cursor()

            # Check if auto_discovered column exists
            cursor.execute("PRAGMA table_info(tools)")
            columns = [row[1] for row in cursor.fetchall()]

            if 'auto_discovered' not in columns:
                logger.info("Adding auto_discovered columns to tools table")

                cursor.execute('''
                    ALTER TABLE tools ADD COLUMN auto_discovered BOOLEAN DEFAULT 0
                ''')
                cursor.execute('''
                    ALTER TABLE tools ADD COLUMN discovery_date TIMESTAMP
                ''')
                cursor.execute('''
                    ALTER TABLE tools ADD COLUMN quality_score REAL
                ''')
                cursor.execute('''
                    ALTER TABLE tools ADD COLUMN github_url TEXT
                ''')
                cursor.execute('''
                    ALTER TABLE tools ADD COLUMN wrapper_path TEXT
                ''')
                cursor.execute('''
                    ALTER TABLE tools ADD COLUMN topics TEXT
                ''')
                cursor.execute('''
                    ALTER TABLE tools ADD COLUMN language TEXT
                ''')
                cursor.execute('''
                    ALTER TABLE tools ADD COLUMN stars INTEGER
                ''')

                self.conn.commit()
                logger.info("Schema updated successfully")

        except sqlite3.OperationalError as e:
            if 'duplicate column name' in str(e):
                logger.info("Schema already up to date")
            else:
                raise


class WrapperInstaller:
    """
    Installs tool wrappers into Galaxy tool repository.
    """

    def __init__(self, tools_dir: Path):
        self.tools_dir = tools_dir

    def install_wrapper(self, wrapper_path: Path, tool_id: str) -> bool:
        """
        Install wrapper into Galaxy tools directory.

        Args:
            wrapper_path: Source wrapper XML file
            tool_id: Tool identifier

        Returns:
            True if successful
        """
        try:
            # Create tool directory
            tool_dir = self.tools_dir / 'auto_discovered' / tool_id
            tool_dir.mkdir(parents=True, exist_ok=True)

            # Copy wrapper
            dest_wrapper = tool_dir / f"{tool_id}.xml"

            # Read and write wrapper (to ensure proper formatting)
            tree = ET.parse(wrapper_path)
            tree.write(dest_wrapper, encoding='utf-8', xml_declaration=True)

            logger.info(f"Installed wrapper to: {dest_wrapper}")
            return True

        except Exception as e:
            logger.error(f"Error installing wrapper: {e}")
            return False


class EmbeddingGenerator:
    """
    Generates embeddings for semantic search.

    Note: This is a stub. In production, would use sentence-transformers.
    """

    def generate_embedding(self, text: str) -> Optional[List[float]]:
        """
        Generate embedding for text.

        Args:
            text: Input text

        Returns:
            Embedding vector or None
        """
        # Stub implementation
        # In production, would use:
        # from sentence_transformers import SentenceTransformer
        # model = SentenceTransformer('all-MiniLM-L6-v2')
        # embedding = model.encode(text)
        # return embedding.tolist()

        logger.warning("Embedding generation not implemented (stub)")
        return None


class ToolIntegrator:
    """
    Main integrator coordinating all integration steps.
    """

    def __init__(
        self,
        db_path: Path,
        tools_dir: Path,
        enable_llm: bool = False,
        anthropic_api_key: str = None,
        github_token: str = None
    ):
        self.db_integrator = DatabaseIntegrator(db_path)
        self.wrapper_installer = WrapperInstaller(tools_dir)
        self.embedding_generator = EmbeddingGenerator()
        self.metadata_extractor = ComprehensiveMetadataExtractor(
            enable_llm=enable_llm,
            anthropic_api_key=anthropic_api_key,
            github_token=github_token
        )

    def integrate_tool(
        self,
        wrapper_path: Path,
        metadata: Dict,
        documentation: Dict,
        test_result: Optional[Dict] = None
    ) -> bool:
        """
        Integrate tool into Galaxy system with complete metadata extraction.

        Args:
            wrapper_path: Path to Galaxy XML wrapper
            metadata: Tool metadata from detector
            documentation: Documentation from documentation_fetcher
            test_result: Test results (optional)

        Returns:
            True if successful
        """
        logger.info(f"Integrating tool: {metadata.get('name')}")

        # Verify test passed (if provided)
        if test_result and not test_result.get('success'):
            logger.error("Tool test failed, not integrating")
            return False

        try:
            # Connect to database
            self.db_integrator.connect()

            # Ensure schema is up to date
            self.db_integrator.ensure_schema()

            # Extract complete metadata using comprehensive extractor
            logger.info("Extracting complete metadata (38 fields)...")
            complete_metadata = self.metadata_extractor.extract_complete_metadata(
                wrapper_path=wrapper_path,
                documentation=documentation,
                metadata=metadata
            )

            tool_id = complete_metadata['tool_id']

            # Log extracted metadata statistics
            logger.info(f"Extracted metadata for {tool_id}:")
            logger.info(f"  - Parameters: {len(json.loads(complete_metadata['parameters']))} defined")
            logger.info(f"  - Inputs: {len(json.loads(complete_metadata['inputs']))} formats")
            logger.info(f"  - Outputs: {len(json.loads(complete_metadata['outputs']))} formats")
            logger.info(f"  - Requirements: {len(json.loads(complete_metadata['requirements']))} items")
            logger.info(f"  - Citations: {len(json.loads(complete_metadata['citations']))} found")
            logger.info(f"  - EDAM operations: {len(json.loads(complete_metadata['edam_operations']))}")
            logger.info(f"  - Category: {complete_metadata['category']}")

            # Add to database with complete metadata (pass source metadata for duplication check)
            success = self.db_integrator.add_tool(complete_metadata, source_metadata=metadata)

            if not success:
                return False

            # Install wrapper
            wrapper_installed = self.wrapper_installer.install_wrapper(
                wrapper_path,
                tool_id
            )

            if not wrapper_installed:
                logger.error("Failed to install wrapper")
                return False

            # Generate embeddings (optional)
            text = complete_metadata['rawText'][:1000]  # Use first 1000 chars
            embedding = self.embedding_generator.generate_embedding(text)
            if embedding:
                logger.info("Generated embedding for semantic search")

            logger.info(f"✓ Successfully integrated tool: {tool_id} with complete metadata")
            return True

        except Exception as e:
            logger.error(f"Integration error: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return False
        finally:
            self.db_integrator.close()

    def integrate_batch(
        self,
        wrappers_dir: Path,
        metadata_file: Path,
        test_results_dir: Optional[Path] = None
    ) -> Dict[str, int]:
        """
        Integrate multiple tools in batch.

        Args:
            wrappers_dir: Directory containing wrapper XML files
            metadata_file: JSON file with all tool metadata
            test_results_dir: Directory with test results (optional)

        Returns:
            Statistics dictionary
        """
        stats = {
            'total': 0,
            'success': 0,
            'failed': 0,
            'skipped': 0
        }

        # Load metadata
        with open(metadata_file) as f:
            all_metadata = json.load(f)

        # Create lookup by tool name
        metadata_lookup = {m['name']: m for m in all_metadata}

        # Process each wrapper
        for wrapper_path in wrappers_dir.glob('*.xml'):
            stats['total'] += 1

            tool_name = wrapper_path.stem

            # Find metadata
            metadata = metadata_lookup.get(tool_name)
            if not metadata:
                logger.warning(f"No metadata found for {tool_name}")
                stats['skipped'] += 1
                continue

            # Load test results if available
            test_result = None
            if test_results_dir:
                test_result_file = test_results_dir / f"{tool_name}_test.json"
                if test_result_file.exists():
                    with open(test_result_file) as f:
                        test_result = json.load(f)

            # Integrate
            success = self.integrate_tool(wrapper_path, metadata, test_result)

            if success:
                stats['success'] += 1
            else:
                stats['failed'] += 1

        return stats


def main():
    parser = argparse.ArgumentParser(
        description='Integrate auto-discovered tools into Galaxy'
    )
    parser.add_argument(
        '--wrapper',
        type=str,
        help='Path to wrapper XML file'
    )
    parser.add_argument(
        '--metadata',
        type=str,
        help='Path to tool metadata JSON file'
    )
    parser.add_argument(
        '--test-result',
        type=str,
        help='Path to test result JSON file (optional)'
    )
    parser.add_argument(
        '--directory',
        type=str,
        help='Directory containing wrapper XML files (batch mode)'
    )
    parser.add_argument(
        '--metadata-file',
        type=str,
        help='JSON file with all tool metadata (batch mode)'
    )
    parser.add_argument(
        '--test-results-dir',
        type=str,
        help='Directory with test results (batch mode, optional)'
    )
    parser.add_argument(
        '--db',
        type=str,
        default='../backend/database/galaxy_ai_tools.db',
        help='Path to Galaxy AI tools database'
    )
    parser.add_argument(
        '--tools-dir',
        type=str,
        default='../backend/tools',
        help='Galaxy tools directory'
    )

    args = parser.parse_args()

    # Initialize integrator
    integrator = ToolIntegrator(
        db_path=Path(args.db),
        tools_dir=Path(args.tools_dir)
    )

    # Single tool mode
    if args.wrapper and args.metadata:
        wrapper_path = Path(args.wrapper)
        with open(args.metadata) as f:
            metadata = json.load(f)

        test_result = None
        if args.test_result:
            with open(args.test_result) as f:
                test_result = json.load(f)

        success = integrator.integrate_tool(wrapper_path, metadata, test_result)

        if success:
            print(f"\n✓ Successfully integrated tool")
            return 0
        else:
            print(f"\n✗ Failed to integrate tool")
            return 1

    # Batch mode
    elif args.directory and args.metadata_file:
        wrappers_dir = Path(args.directory)
        metadata_file = Path(args.metadata_file)
        test_results_dir = Path(args.test_results_dir) if args.test_results_dir else None

        stats = integrator.integrate_batch(
            wrappers_dir,
            metadata_file,
            test_results_dir
        )

        print(f"\n{'='*60}")
        print(f"Batch Integration Summary")
        print(f"{'='*60}")
        print(f"Total tools: {stats['total']}")
        print(f"Successfully integrated: {stats['success']}")
        print(f"Failed: {stats['failed']}")
        print(f"Skipped: {stats['skipped']}")
        print(f"{'='*60}")

        return 0 if stats['failed'] == 0 else 1

    else:
        logger.error("Either --wrapper and --metadata, or --directory and --metadata-file required")
        return 1


if __name__ == '__main__':
    exit(main())
