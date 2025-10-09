#!/usr/bin/env python3
"""
Parallel Installation of Top 20 LC-MS Tools with Resource Monitoring

This script installs the top 20 LC-MS/Metabolomics tools in parallel
and monitors time and resource usage.

Usage:
    cd /private/tmp/lcms-platform-galaxy
    python3 scripts/install_top_20_tools_parallel.py

Features:
    - Parallel installation (configurable concurrency)
    - Real-time resource monitoring (CPU, memory, disk)
    - Detailed timing statistics
    - Progress tracking
    - Installation summary report
"""

import os
import sys
import yaml
import time
import logging
import psutil
import threading
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
from typing import Dict, List, Tuple
from dataclasses import dataclass, field

# Add Galaxy lib to path
GALAXY_ROOT = Path(__file__).parent.parent
sys.path.insert(1, str(GALAXY_ROOT / "lib"))

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - [%(threadName)-10s] - %(levelname)s - %(message)s'
)
log = logging.getLogger(__name__)


@dataclass
class InstallationResult:
    """Track installation results and metrics"""
    tool_name: str
    owner: str
    repo_name: str
    success: bool
    duration: float = 0.0
    error_message: str = ""
    start_time: datetime = None
    end_time: datetime = None

    def __post_init__(self):
        if self.start_time is None:
            self.start_time = datetime.now()


@dataclass
class ResourceMetrics:
    """Track system resource usage"""
    timestamp: datetime
    cpu_percent: float
    memory_percent: float
    memory_used_gb: float
    disk_used_gb: float
    disk_free_gb: float


class ResourceMonitor:
    """Monitor system resources during installation"""

    def __init__(self, interval: float = 5.0):
        self.interval = interval
        self.metrics: List[ResourceMetrics] = []
        self.monitoring = False
        self.thread = None
        self.start_time = None

    def start(self):
        """Start monitoring"""
        self.monitoring = True
        self.start_time = datetime.now()
        self.thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self.thread.start()
        log.info("Resource monitoring started")

    def stop(self):
        """Stop monitoring"""
        self.monitoring = False
        if self.thread:
            self.thread.join(timeout=2)
        log.info("Resource monitoring stopped")

    def _monitor_loop(self):
        """Monitoring loop"""
        while self.monitoring:
            try:
                cpu = psutil.cpu_percent(interval=1)
                mem = psutil.virtual_memory()
                disk = psutil.disk_usage('/')

                metric = ResourceMetrics(
                    timestamp=datetime.now(),
                    cpu_percent=cpu,
                    memory_percent=mem.percent,
                    memory_used_gb=mem.used / (1024**3),
                    disk_used_gb=disk.used / (1024**3),
                    disk_free_gb=disk.free / (1024**3)
                )
                self.metrics.append(metric)

                time.sleep(self.interval)
            except Exception as e:
                log.error(f"Error in resource monitoring: {e}")

    def get_summary(self) -> Dict:
        """Get resource usage summary"""
        if not self.metrics:
            return {}

        cpu_values = [m.cpu_percent for m in self.metrics]
        mem_values = [m.memory_percent for m in self.metrics]
        mem_gb_values = [m.memory_used_gb for m in self.metrics]

        return {
            'duration_seconds': (datetime.now() - self.start_time).total_seconds(),
            'cpu': {
                'min': min(cpu_values),
                'max': max(cpu_values),
                'avg': sum(cpu_values) / len(cpu_values)
            },
            'memory_percent': {
                'min': min(mem_values),
                'max': max(mem_values),
                'avg': sum(mem_values) / len(mem_values)
            },
            'memory_gb': {
                'min': min(mem_gb_values),
                'max': max(mem_gb_values),
                'avg': sum(mem_gb_values) / len(mem_gb_values)
            },
            'disk_start_free_gb': self.metrics[0].disk_free_gb,
            'disk_end_free_gb': self.metrics[-1].disk_free_gb,
            'disk_used_gb': self.metrics[0].disk_free_gb - self.metrics[-1].disk_free_gb
        }


class ParallelToolInstaller:
    """Install tools in parallel with monitoring"""

    def __init__(self, max_workers: int = 3):
        self.max_workers = max_workers
        self.results: List[InstallationResult] = []
        self.lock = threading.Lock()

    def install_single_tool(self, tool: Dict, app) -> InstallationResult:
        """Install a single tool"""
        result = InstallationResult(
            tool_name=tool['name'],
            owner=tool['owner'],
            repo_name=tool['repo_name'],
            success=False
        )

        try:
            from galaxy.tool_shed.galaxy_install.install_manager import (
                InstallRepositoryManager,
                get_install_info_from_tool_shed
            )
            from galaxy.util.tool_shed.tool_shed_registry import Registry

            owner = tool['owner']
            repo_name = tool['repo_name']
            changeset = tool['changeset_revision']
            tool_shed_url = tool['tool_shed_url']

            log.info(f"Starting installation: {tool['name']}")

            # Check if already installed
            with self.lock:
                existing = app.install_model.context.query(app.install_model.ToolShedRepository).filter(
                    app.install_model.ToolShedRepository.name == repo_name,
                    app.install_model.ToolShedRepository.owner == owner,
                    app.install_model.ToolShedRepository.changeset_revision == changeset
                ).first()

            if existing:
                log.info(f"Already installed: {tool['name']}")
                result.success = True
                result.duration = 0.0
                result.end_time = datetime.now()
                return result

            # Get installation info
            tool_shed_registry = Registry(app.config.tool_sheds_config_file)
            repo_info_dict, extra_info = get_install_info_from_tool_shed(
                tool_shed_url=tool_shed_url,
                tool_shed_registry=tool_shed_registry,
                name=repo_name,
                owner=owner,
                changeset_revision=changeset
            )

            # Create installation dict
            installation_dict = {
                'install_repository_dependencies': True,
                'install_resolver_dependencies': True,
                'install_tool_dependencies': False,
                'new_tool_panel_section_label': tool.get('tool_panel_section_label', 'LC-MS Metabolomics'),
                'tool_panel_section_id': '',
                'shed_tool_conf': app.config.shed_tool_config_file,
                'tool_path': app.config.tool_path,
                'tool_shed_url': tool_shed_url,
                'repo_info_dicts': [extra_info],
                'no_changes_checked': False,
                'has_repository_dependencies': False,
                'includes_tool_dependencies': False,
                'includes_tools': True,
                'includes_tools_for_display_in_tool_panel': True,
                'message': '',
                'status': 'ok'
            }

            # Install
            irm = InstallRepositoryManager(app)
            created_repos, tool_panel_section_keys, repo_info_dicts, filtered_repo_info_dicts = \
                irm.handle_tool_shed_repositories(installation_dict)

            if not created_repos:
                raise Exception("Failed to create repository record")

            installation_dict.update({
                'created_or_updated_tool_shed_repositories': created_repos,
                'tool_panel_section_keys': tool_panel_section_keys,
                'filtered_repo_info_dicts': filtered_repo_info_dicts,
                'tool_panel_section_mapping': {}
            })

            encoded_repo_ids = irm.initiate_repository_installation(installation_dict)

            # Wait for toolbox reload
            old_toolbox = app.toolbox
            app.wait_for_toolbox_reload(old_toolbox)

            result.success = True
            result.end_time = datetime.now()
            result.duration = (result.end_time - result.start_time).total_seconds()

            log.info(f"✅ Installed {tool['name']} in {result.duration:.1f}s")

        except Exception as e:
            result.success = False
            result.error_message = str(e)
            result.end_time = datetime.now()
            result.duration = (result.end_time - result.start_time).total_seconds()
            log.error(f"❌ Failed to install {tool['name']}: {e}")

        return result

    def install_tools_parallel(self, tools: List[Dict], app) -> List[InstallationResult]:
        """Install tools in parallel"""
        log.info(f"Starting parallel installation with {self.max_workers} workers")

        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            futures = {
                executor.submit(self.install_single_tool, tool, app): tool
                for tool in tools
            }

            for future in as_completed(futures):
                result = future.result()
                self.results.append(result)

        return self.results


def print_summary(results: List[InstallationResult], resource_summary: Dict):
    """Print installation summary"""
    print("\n" + "=" * 80)
    print("INSTALLATION SUMMARY")
    print("=" * 80)

    # Overall stats
    total = len(results)
    successful = sum(1 for r in results if r.success)
    failed = total - successful

    print(f"\n📊 Overall Statistics:")
    print(f"  Total tools: {total}")
    print(f"  ✅ Successful: {successful}")
    print(f"  ❌ Failed: {failed}")
    print(f"  Success rate: {successful/total*100:.1f}%")

    # Timing
    if results:
        durations = [r.duration for r in results if r.duration > 0]
        if durations:
            total_time = sum(durations)
            avg_time = total_time / len(durations)
            min_time = min(durations)
            max_time = max(durations)

            print(f"\n⏱️  Installation Timing:")
            print(f"  Total time: {total_time:.1f}s ({total_time/60:.1f} minutes)")
            print(f"  Average per tool: {avg_time:.1f}s")
            print(f"  Fastest: {min_time:.1f}s")
            print(f"  Slowest: {max_time:.1f}s")

    # Resource usage
    if resource_summary:
        print(f"\n💻 Resource Usage:")
        print(f"  CPU Usage:")
        print(f"    Min: {resource_summary['cpu']['min']:.1f}%")
        print(f"    Max: {resource_summary['cpu']['max']:.1f}%")
        print(f"    Avg: {resource_summary['cpu']['avg']:.1f}%")
        print(f"  Memory Usage:")
        print(f"    Min: {resource_summary['memory_percent']['min']:.1f}%")
        print(f"    Max: {resource_summary['memory_percent']['max']:.1f}%")
        print(f"    Avg: {resource_summary['memory_percent']['avg']:.1f}%")
        print(f"  Memory (GB):")
        print(f"    Min: {resource_summary['memory_gb']['min']:.2f} GB")
        print(f"    Max: {resource_summary['memory_gb']['max']:.2f} GB")
        print(f"    Avg: {resource_summary['memory_gb']['avg']:.2f} GB")
        print(f"  Disk Space:")
        print(f"    Used: {resource_summary['disk_used_gb']:.2f} GB")
        print(f"    Free (start): {resource_summary['disk_start_free_gb']:.2f} GB")
        print(f"    Free (end): {resource_summary['disk_end_free_gb']:.2f} GB")

    # Failed installations
    failed_results = [r for r in results if not r.success and r.error_message]
    if failed_results:
        print(f"\n❌ Failed Installations:")
        for r in failed_results:
            print(f"  - {r.tool_name} ({r.owner}/{r.repo_name})")
            print(f"    Error: {r.error_message[:100]}")

    # Top 5 slowest installations
    sorted_results = sorted([r for r in results if r.duration > 0],
                           key=lambda x: x.duration, reverse=True)
    if sorted_results:
        print(f"\n🐌 Top 5 Slowest Installations:")
        for i, r in enumerate(sorted_results[:5], 1):
            print(f"  {i}. {r.tool_name}: {r.duration:.1f}s ({r.duration/60:.1f} min)")

    print("\n" + "=" * 80)


def main():
    """Main entry point"""
    try:
        from galaxy.app import UniverseApplication
        from galaxy.config import GalaxyAppConfiguration

        # Check we're in Galaxy root
        if not (GALAXY_ROOT / "lib" / "galaxy").exists():
            log.error("Error: Must be run from Galaxy root directory")
            sys.exit(1)

        # Load tool configuration
        config_path = GALAXY_ROOT / "config" / "top_20_lcms_tools.yml"
        if not config_path.exists():
            log.error(f"Error: Configuration file not found: {config_path}")
            sys.exit(1)

        with open(config_path, 'r') as f:
            tool_config = yaml.safe_load(f)

        tools = tool_config['tools']

        print("=" * 80)
        print("PARALLEL LC-MS TOOL INSTALLATION WITH RESOURCE MONITORING")
        print("=" * 80)
        print(f"\nConfiguration:")
        print(f"  Tools to install: {len(tools)}")
        print(f"  Parallel workers: 3")
        print(f"  Resource monitoring: Enabled (5s interval)")
        print(f"\n⚠️  NOTE: This may take 30-60 minutes depending on system performance")
        print(f"Press Ctrl+C to cancel, or wait 5 seconds to continue...\n")

        try:
            time.sleep(5)
        except KeyboardInterrupt:
            print("\nInstallation cancelled")
            sys.exit(0)

        # Initialize Galaxy
        log.info("Initializing Galaxy application...")
        config_file = GALAXY_ROOT / "config" / "galaxy.yml"
        if not config_file.exists():
            config_file = GALAXY_ROOT / "config" / "galaxy.yml.sample"

        config = GalaxyAppConfiguration(config_file=str(config_file))
        app = UniverseApplication(config=config)

        # Start resource monitoring
        monitor = ResourceMonitor(interval=5.0)
        monitor.start()

        # Start installation
        overall_start = time.time()
        installer = ParallelToolInstaller(max_workers=3)

        try:
            results = installer.install_tools_parallel(tools, app)
        finally:
            # Stop monitoring
            monitor.stop()

        overall_duration = time.time() - overall_start

        # Get resource summary
        resource_summary = monitor.get_summary()
        resource_summary['total_wall_time'] = overall_duration

        # Print summary
        print_summary(results, resource_summary)

        # Save detailed report
        report_path = GALAXY_ROOT / "tool_installation_report.txt"
        with open(report_path, 'w') as f:
            f.write(f"Tool Installation Report\n")
            f.write(f"Generated: {datetime.now()}\n")
            f.write(f"\nTotal wall time: {overall_duration:.1f}s ({overall_duration/60:.1f} minutes)\n")
            f.write(f"\nDetailed Results:\n")
            for r in results:
                f.write(f"\n{r.tool_name} ({r.owner}/{r.repo_name})\n")
                f.write(f"  Success: {r.success}\n")
                f.write(f"  Duration: {r.duration:.1f}s\n")
                if r.error_message:
                    f.write(f"  Error: {r.error_message}\n")

        log.info(f"Detailed report saved to: {report_path}")

    except ImportError as e:
        log.error(f"Failed to import Galaxy modules: {e}")
        sys.exit(1)
    except Exception as e:
        log.error(f"Unexpected error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == '__main__':
    main()
