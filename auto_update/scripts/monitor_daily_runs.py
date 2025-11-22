#!/usr/bin/env python3
"""
Daily Auto-Update Monitoring Script

Monitors daily pipeline runs, generates alerts, and provides dashboard view.
Can be run manually or via cron to check pipeline health.

Usage:
    python3 monitor_daily_runs.py [--days N] [--send-alerts]
"""

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional


class DailyRunMonitor:
    """Monitor and analyze daily auto-update runs."""

    def __init__(self, base_dir: Path):
        self.base_dir = base_dir
        self.log_dir = base_dir / "logs" / "daily"
        self.report_dir = base_dir / "reports" / "daily"
        self.db_path = Path("/home/yzhang/biomate/backend/database/galaxy_ai_tools.db")

    def get_recent_runs(self, days: int = 7) -> List[Dict]:
        """Get information about recent daily runs."""
        runs = []

        if not self.log_dir.exists():
            return runs

        # Find log files from last N days
        cutoff_date = datetime.now() - timedelta(days=days)

        for log_file in sorted(self.log_dir.glob("daily_run_*.log"), reverse=True):
            # Extract timestamp from filename: daily_run_20251107_020000.log
            try:
                timestamp_str = log_file.stem.split("daily_run_")[1]
                run_date = datetime.strptime(timestamp_str, "%Y%m%d_%H%M%S")

                if run_date < cutoff_date:
                    continue

                # Parse log file for status
                status = self._parse_log_status(log_file)

                # Find corresponding report
                report_date = run_date.strftime("%Y-%m-%d")
                report_file = self.report_dir / f"summary_{report_date}.json"
                summary = self._load_summary(report_file) if report_file.exists() else None

                runs.append({
                    "timestamp": run_date,
                    "log_file": str(log_file),
                    "report_file": str(report_file) if report_file.exists() else None,
                    "status": status,
                    "summary": summary
                })

            except (ValueError, IndexError) as e:
                print(f"Warning: Could not parse log file {log_file}: {e}", file=sys.stderr)
                continue

        return runs

    def _parse_log_status(self, log_file: Path) -> Dict:
        """Parse log file to determine run status."""
        status = {
            "success": False,
            "completed": False,
            "errors": [],
            "warnings": [],
            "tools_processed": 0,
            "duration_seconds": None
        }

        try:
            with open(log_file, 'r') as f:
                lines = f.readlines()

            start_time = None
            end_time = None

            for line in lines:
                # Check for completion
                if "Daily Tool Auto-Update - Completed Successfully" in line:
                    status["success"] = True
                    status["completed"] = True
                elif "Daily Tool Auto-Update - Completed with Errors" in line:
                    status["completed"] = True

                # Extract timestamps
                if "Daily Tool Auto-Update - Starting" in line:
                    try:
                        timestamp = line.split("]")[0].strip("[")
                        start_time = datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S")
                    except:
                        pass
                if status["completed"] and end_time is None:
                    try:
                        timestamp = line.split("]")[0].strip("[")
                        end_time = datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S")
                    except:
                        pass

                # Count errors and warnings
                if " ERROR: " in line:
                    status["errors"].append(line.strip())
                elif " WARNING: " in line:
                    status["warnings"].append(line.strip())

                # Count processed tools
                if "Processing tool:" in line:
                    status["tools_processed"] += 1

            # Calculate duration
            if start_time and end_time:
                status["duration_seconds"] = (end_time - start_time).total_seconds()

        except Exception as e:
            status["errors"].append(f"Failed to parse log: {e}")

        return status

    def _load_summary(self, report_file: Path) -> Optional[Dict]:
        """Load summary report from JSON file."""
        try:
            with open(report_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"Warning: Could not load summary {report_file}: {e}", file=sys.stderr)
            return None

    def get_database_stats(self) -> Dict:
        """Get current database statistics."""
        if not self.db_path.exists():
            return {"error": "Database not found"}

        try:
            conn = sqlite3.connect(self.db_path)
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()

            # Total tools
            cursor.execute("SELECT COUNT(*) as count FROM tools")
            total_tools = cursor.fetchone()["count"]

            # Auto-discovered tools
            cursor.execute("SELECT COUNT(*) as count FROM tools WHERE auto_discovered = 1")
            auto_discovered = cursor.fetchone()["count"]

            # Tools added today
            cursor.execute("""
                SELECT COUNT(*) as count
                FROM tools
                WHERE DATE(created_at) = DATE('now')
                AND auto_discovered = 1
            """)
            added_today = cursor.fetchone()["count"]

            # Tools added in last 7 days
            cursor.execute("""
                SELECT COUNT(*) as count
                FROM tools
                WHERE DATE(created_at) >= DATE('now', '-7 days')
                AND auto_discovered = 1
            """)
            added_last_7_days = cursor.fetchone()["count"]

            # Average tools per day (last 30 days)
            cursor.execute("""
                SELECT COUNT(*) / 30.0 as avg_per_day
                FROM tools
                WHERE DATE(created_at) >= DATE('now', '-30 days')
                AND auto_discovered = 1
            """)
            avg_per_day = cursor.fetchone()["avg_per_day"] or 0

            conn.close()

            return {
                "total_tools": total_tools,
                "auto_discovered": auto_discovered,
                "added_today": added_today,
                "added_last_7_days": added_last_7_days,
                "avg_per_day": round(avg_per_day, 2)
            }

        except Exception as e:
            return {"error": f"Database query failed: {e}"}

    def generate_dashboard(self, days: int = 7) -> str:
        """Generate a text-based dashboard of recent runs."""
        runs = self.get_recent_runs(days)
        db_stats = self.get_database_stats()

        dashboard = []
        dashboard.append("=" * 80)
        dashboard.append("Daily Auto-Update Monitoring Dashboard")
        dashboard.append("=" * 80)
        dashboard.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        dashboard.append("")

        # Database Statistics
        dashboard.append("Database Statistics:")
        dashboard.append("-" * 80)
        if "error" in db_stats:
            dashboard.append(f"  ❌ {db_stats['error']}")
        else:
            dashboard.append(f"  Total tools: {db_stats['total_tools']:,}")
            dashboard.append(f"  Auto-discovered: {db_stats['auto_discovered']:,}")
            dashboard.append(f"  Added today: {db_stats['added_today']}")
            dashboard.append(f"  Added last 7 days: {db_stats['added_last_7_days']}")
            dashboard.append(f"  Average per day (30d): {db_stats['avg_per_day']}")
        dashboard.append("")

        # Recent Runs
        dashboard.append(f"Recent Daily Runs (Last {days} days):")
        dashboard.append("-" * 80)

        if not runs:
            dashboard.append("  No runs found in the specified period")
        else:
            for run in runs[:10]:  # Show max 10 most recent
                timestamp = run["timestamp"].strftime("%Y-%m-%d %H:%M")
                status = run["status"]

                # Status indicator
                if status["success"]:
                    indicator = "✅"
                elif status["completed"]:
                    indicator = "⚠️ "
                else:
                    indicator = "❌"

                dashboard.append(f"  {indicator} {timestamp}")

                # Summary info
                if run["summary"]:
                    summary = run["summary"]
                    dashboard.append(f"      Tools added: {summary.get('tools_added', 0)}")
                    dashboard.append(f"      With citations: {summary.get('tools_with_citations', 0)}")
                    dashboard.append(f"      Citation rate: {summary.get('citation_rate', 0)}%")
                    dashboard.append(f"      Avg quality: {summary.get('avg_quality_score', 0)}")

                # Errors/warnings
                if status["errors"]:
                    dashboard.append(f"      Errors: {len(status['errors'])}")
                if status["warnings"]:
                    dashboard.append(f"      Warnings: {len(status['warnings'])}")

                # Duration
                if status["duration_seconds"]:
                    minutes = int(status["duration_seconds"] // 60)
                    dashboard.append(f"      Duration: {minutes} minutes")

                dashboard.append("")

        dashboard.append("=" * 80)

        return "\n".join(dashboard)

    def check_health(self) -> Dict:
        """Check overall health of the daily update system."""
        health = {
            "status": "healthy",
            "issues": [],
            "warnings": []
        }

        # Check if runs are happening
        runs = self.get_recent_runs(days=2)
        if not runs:
            health["status"] = "critical"
            health["issues"].append("No daily runs found in last 2 days")
        else:
            latest_run = runs[0]
            run_age = datetime.now() - latest_run["timestamp"]

            if run_age > timedelta(hours=30):  # Should run daily
                health["status"] = "warning"
                health["warnings"].append(f"Latest run is {run_age.days} days old")

            if not latest_run["status"]["success"]:
                health["status"] = "warning"
                health["warnings"].append("Latest run did not complete successfully")

        # Check database
        db_stats = self.get_database_stats()
        if "error" in db_stats:
            health["status"] = "critical"
            health["issues"].append(f"Database error: {db_stats['error']}")
        elif db_stats.get("added_today", 0) == 0 and datetime.now().hour > 3:
            # After 3 AM, we should have added tools if there are any
            health["warnings"].append("No tools added today yet")

        # Check log directory
        if not self.log_dir.exists():
            health["status"] = "warning"
            health["warnings"].append("Log directory does not exist")

        return health

    def send_alert(self, health: Dict):
        """Send alert notification (email/Slack)."""
        # TODO: Implement actual notification
        # For now, just print to stdout
        print("\n" + "=" * 80)
        print("ALERT NOTIFICATION")
        print("=" * 80)
        print(f"Status: {health['status'].upper()}")

        if health["issues"]:
            print("\nIssues:")
            for issue in health["issues"]:
                print(f"  ❌ {issue}")

        if health["warnings"]:
            print("\nWarnings:")
            for warning in health["warnings"]:
                print(f"  ⚠️  {warning}")

        print("=" * 80 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Monitor BioMate daily auto-update pipeline"
    )
    parser.add_argument(
        "--days",
        type=int,
        default=7,
        help="Number of days to look back (default: 7)"
    )
    parser.add_argument(
        "--send-alerts",
        action="store_true",
        help="Send alerts if issues detected"
    )
    parser.add_argument(
        "--health-check",
        action="store_true",
        help="Check health and exit with status code"
    )

    args = parser.parse_args()

    # Determine base directory
    script_dir = Path(__file__).parent
    base_dir = script_dir.parent

    monitor = DailyRunMonitor(base_dir)

    # Health check mode
    if args.health_check:
        health = monitor.check_health()
        print(json.dumps(health, indent=2))

        if health["status"] == "critical":
            if args.send_alerts:
                monitor.send_alert(health)
            sys.exit(2)
        elif health["status"] == "warning":
            if args.send_alerts:
                monitor.send_alert(health)
            sys.exit(1)
        else:
            sys.exit(0)

    # Dashboard mode
    dashboard = monitor.generate_dashboard(days=args.days)
    print(dashboard)

    # Check health and send alerts if requested
    if args.send_alerts:
        health = monitor.check_health()
        if health["status"] in ["warning", "critical"]:
            monitor.send_alert(health)


if __name__ == "__main__":
    main()
