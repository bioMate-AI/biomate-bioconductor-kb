#!/usr/bin/env python3
"""
AWS Cost Analysis for LC-MS Tool Installation

Analyzes resource usage from tool installation and calculates AWS costs
for different instance types and deployment scenarios.
"""

import json
import sys
from pathlib import Path
from typing import Dict, List


# AWS EC2 Instance Pricing (us-east-1, On-Demand, as of 2024)
AWS_INSTANCES = {
    # General Purpose
    't3.medium': {'vcpu': 2, 'ram_gb': 4, 'price_hourly': 0.0416, 'category': 'Burstable'},
    't3.large': {'vcpu': 2, 'ram_gb': 8, 'price_hourly': 0.0832, 'category': 'Burstable'},
    't3.xlarge': {'vcpu': 4, 'ram_gb': 16, 'price_hourly': 0.1664, 'category': 'Burstable'},
    't3.2xlarge': {'vcpu': 8, 'ram_gb': 32, 'price_hourly': 0.3328, 'category': 'Burstable'},

    # Compute Optimized
    'c6i.large': {'vcpu': 2, 'ram_gb': 4, 'price_hourly': 0.085, 'category': 'Compute Optimized'},
    'c6i.xlarge': {'vcpu': 4, 'ram_gb': 8, 'price_hourly': 0.17, 'category': 'Compute Optimized'},
    'c6i.2xlarge': {'vcpu': 8, 'ram_gb': 16, 'price_hourly': 0.34, 'category': 'Compute Optimized'},
    'c6i.4xlarge': {'vcpu': 16, 'ram_gb': 32, 'price_hourly': 0.68, 'category': 'Compute Optimized'},

    # Memory Optimized
    'r6i.large': {'vcpu': 2, 'ram_gb': 16, 'price_hourly': 0.126, 'category': 'Memory Optimized'},
    'r6i.xlarge': {'vcpu': 4, 'ram_gb': 32, 'price_hourly': 0.252, 'category': 'Memory Optimized'},
    'r6i.2xlarge': {'vcpu': 8, 'ram_gb': 64, 'price_hourly': 0.504, 'category': 'Memory Optimized'},
}


# AWS Storage Pricing (us-east-1)
AWS_STORAGE = {
    'ebs_gp3': 0.08,  # per GB-month
    'ebs_gp2': 0.10,  # per GB-month
    'ebs_io2': 0.125, # per GB-month
    's3_standard': 0.023,  # per GB-month
}

# AWS Data Transfer Pricing (us-east-1)
AWS_TRANSFER = {
    'in': 0.0,  # Inbound free
    'out_first_10tb': 0.09,  # per GB
    'out_next_40tb': 0.085,  # per GB
}


def analyze_installation_metrics(report_file: Path) -> Dict:
    """Parse installation report for resource metrics"""

    if not report_file.exists():
        print(f"⚠️  Report file not found: {report_file}")
        return None

    with open(report_file, 'r') as f:
        lines = f.readlines()

    metrics = {
        'total_tools': 0,
        'successful': 0,
        'failed': 0,
        'total_time_seconds': 0,
        'avg_time_per_tool': 0,
        'cpu': {'min': 0, 'max': 0, 'avg': 0},
        'memory_percent': {'min': 0, 'max': 0, 'avg': 0},
        'memory_gb': {'min': 0, 'max': 0, 'avg': 0},
        'disk_used_gb': 0,
    }

    # Parse report file
    for line in lines:
        line = line.strip()

        # Total tools
        if 'Total tools:' in line:
            metrics['total_tools'] = int(line.split(':')[1].strip())
        elif 'Successful:' in line:
            metrics['successful'] = int(line.split(':')[1].strip())
        elif 'Failed:' in line:
            metrics['failed'] = int(line.split(':')[1].strip())

        # Timing
        elif 'Total time:' in line and 's' in line:
            # Extract seconds from "Total time: 1847.3s (30.8 minutes)"
            time_str = line.split(':')[1].strip().split('s')[0]
            metrics['total_time_seconds'] = float(time_str)
        elif 'Average per tool:' in line and 's' in line:
            time_str = line.split(':')[1].strip().split('s')[0]
            metrics['avg_time_per_tool'] = float(time_str)

        # CPU
        elif 'CPU Usage:' in line:
            pass  # Header
        elif 'Min:' in line and '%' in line and 'cpu' in '\n'.join(lines[max(0, lines.index(line+'\n')-5):lines.index(line+'\n')]).lower():
            metrics['cpu']['min'] = float(line.split(':')[1].strip().replace('%', ''))
        elif 'Max:' in line and '%' in line and 'cpu' in '\n'.join(lines[max(0, lines.index(line+'\n')-5):lines.index(line+'\n')]).lower():
            metrics['cpu']['max'] = float(line.split(':')[1].strip().replace('%', ''))
        elif 'Avg:' in line and '%' in line and 'cpu' in '\n'.join(lines[max(0, lines.index(line+'\n')-5):lines.index(line+'\n')]).lower():
            metrics['cpu']['avg'] = float(line.split(':')[1].strip().replace('%', ''))

        # Memory GB
        elif 'Memory (GB):' in line:
            pass  # Header
        elif 'Min:' in line and 'GB' in line:
            try:
                metrics['memory_gb']['min'] = float(line.split(':')[1].strip().split('GB')[0].strip())
            except:
                pass
        elif 'Max:' in line and 'GB' in line:
            try:
                metrics['memory_gb']['max'] = float(line.split(':')[1].strip().split('GB')[0].strip())
            except:
                pass
        elif 'Avg:' in line and 'GB' in line:
            try:
                metrics['memory_gb']['avg'] = float(line.split(':')[1].strip().split('GB')[0].strip())
            except:
                pass

        # Disk
        elif 'Used:' in line and 'GB' in line and 'Disk' in '\n'.join(lines[max(0, lines.index(line+'\n')-3):lines.index(line+'\n')]):
            try:
                metrics['disk_used_gb'] = float(line.split(':')[1].strip().split('GB')[0].strip())
            except:
                pass

    return metrics


def recommend_instance(metrics: Dict) -> List[Dict]:
    """Recommend AWS instances based on resource usage"""

    if not metrics:
        return []

    avg_cpu_percent = metrics['cpu']['avg']
    max_memory_gb = metrics['memory_gb']['max']
    avg_memory_gb = metrics['memory_gb']['avg']

    recommendations = []

    for instance_name, instance_spec in AWS_INSTANCES.items():
        # Check if instance can handle the workload
        vcpu_utilization = (avg_cpu_percent / 100.0) / instance_spec['vcpu'] if instance_spec['vcpu'] > 0 else 999
        memory_utilization = max_memory_gb / instance_spec['ram_gb'] if instance_spec['ram_gb'] > 0 else 999

        # Only recommend if instance can handle the load (with some headroom)
        if memory_utilization <= 0.85 and vcpu_utilization <= 0.9:
            recommendations.append({
                'instance': instance_name,
                'vcpu': instance_spec['vcpu'],
                'ram_gb': instance_spec['ram_gb'],
                'price_hourly': instance_spec['price_hourly'],
                'category': instance_spec['category'],
                'cpu_utilization': vcpu_utilization * 100,
                'memory_utilization': memory_utilization * 100,
                'suitable': True
            })
        else:
            recommendations.append({
                'instance': instance_name,
                'vcpu': instance_spec['vcpu'],
                'ram_gb': instance_spec['ram_gb'],
                'price_hourly': instance_spec['price_hourly'],
                'category': instance_spec['category'],
                'cpu_utilization': vcpu_utilization * 100,
                'memory_utilization': memory_utilization * 100,
                'suitable': False
            })

    # Sort by price
    recommendations.sort(key=lambda x: x['price_hourly'])

    return recommendations


def calculate_aws_costs(metrics: Dict, instance_type: str = 't3.xlarge') -> Dict:
    """Calculate AWS costs for tool installation"""

    if not metrics or instance_type not in AWS_INSTANCES:
        return {}

    instance = AWS_INSTANCES[instance_type]
    total_time_hours = metrics['total_time_seconds'] / 3600.0
    disk_gb = metrics['disk_used_gb']

    # Compute cost
    compute_cost = instance['price_hourly'] * total_time_hours

    # Storage cost (monthly, but prorated to installation time)
    storage_cost_monthly = disk_gb * AWS_STORAGE['ebs_gp3']
    storage_cost_install = storage_cost_monthly * (total_time_hours / 730.0)  # 730 hours/month

    # Data transfer cost (assume ~1GB download per tool)
    data_transfer_gb = metrics['total_tools'] * 1.0  # 1 GB per tool average
    transfer_cost = data_transfer_gb * AWS_TRANSFER['out_first_10tb']

    # Total one-time installation cost
    total_one_time = compute_cost + storage_cost_install + transfer_cost

    # Monthly cost if keeping instance running
    monthly_compute = instance['price_hourly'] * 730  # hours/month
    monthly_storage = disk_gb * AWS_STORAGE['ebs_gp3']
    monthly_total = monthly_compute + monthly_storage

    return {
        'instance_type': instance_type,
        'instance_specs': instance,
        'installation_time_hours': total_time_hours,
        'installation_time_minutes': total_time_hours * 60,
        'costs': {
            'compute_install': compute_cost,
            'storage_install': storage_cost_install,
            'data_transfer': transfer_cost,
            'total_one_time': total_one_time,
            'monthly_compute': monthly_compute,
            'monthly_storage': monthly_storage,
            'monthly_total': monthly_total,
            'yearly_total': monthly_total * 12
        },
        'resource_usage': {
            'disk_gb': disk_gb,
            'avg_cpu_percent': metrics['cpu']['avg'],
            'avg_memory_gb': metrics['memory_gb']['avg'],
            'max_memory_gb': metrics['memory_gb']['max'],
        }
    }


def print_cost_analysis(report_file: Path):
    """Print comprehensive AWS cost analysis"""

    print("="*80)
    print("AWS COST ANALYSIS FOR LC-MS TOOL INSTALLATION")
    print("="*80)

    # Parse metrics
    metrics = analyze_installation_metrics(report_file)

    if not metrics:
        print("❌ Could not parse installation metrics")
        return

    # Print resource summary
    print(f"\n📊 Resource Usage Summary:")
    print(f"  Tools installed: {metrics['successful']}/{metrics['total_tools']}")
    print(f"  Total time: {metrics['total_time_seconds']:.1f}s ({metrics['total_time_seconds']/60:.1f} min)")
    print(f"  Avg time/tool: {metrics['avg_time_per_tool']:.1f}s")
    print(f"\n  CPU Usage: {metrics['cpu']['min']:.1f}% - {metrics['cpu']['max']:.1f}% (avg: {metrics['cpu']['avg']:.1f}%)")
    print(f"  Memory: {metrics['memory_gb']['min']:.2f} - {metrics['memory_gb']['max']:.2f} GB (avg: {metrics['memory_gb']['avg']:.2f} GB)")
    print(f"  Disk used: {metrics['disk_used_gb']:.2f} GB")

    # Instance recommendations
    print(f"\n💡 AWS Instance Recommendations:")
    recommendations = recommend_instance(metrics)

    suitable = [r for r in recommendations if r['suitable']]
    unsuitable = [r for r in recommendations if not r['suitable']]

    print(f"\n✅ Suitable Instances (sorted by price):")
    for i, rec in enumerate(suitable[:5], 1):
        print(f"  {i}. {rec['instance']:15} - ${rec['price_hourly']:.4f}/hr - "
              f"{rec['vcpu']} vCPU, {rec['ram_gb']} GB RAM - "
              f"CPU: {rec['cpu_utilization']:.1f}%, Mem: {rec['memory_utilization']:.1f}%")

    if not suitable:
        print("  ⚠️  None of the analyzed instances can handle this workload safely")
        print("     Consider larger instances or optimizing the installation process")

    # Detailed cost breakdown for recommended instance
    if suitable:
        recommended = suitable[0]
        print(f"\n💰 Detailed Cost Analysis ({recommended['instance']}):")

        costs = calculate_aws_costs(metrics, recommended['instance'])

        print(f"\n  One-Time Installation Costs:")
        print(f"    Compute (EC2): ${costs['costs']['compute_install']:.4f}")
        print(f"    Storage (EBS): ${costs['costs']['storage_install']:.4f}")
        print(f"    Data Transfer: ${costs['costs']['data_transfer']:.4f}")
        print(f"    ─────────────────────────────")
        print(f"    TOTAL ONE-TIME: ${costs['costs']['total_one_time']:.2f}")

        print(f"\n  Ongoing Monthly Costs (if keeping instance running 24/7):")
        print(f"    Compute (EC2): ${costs['costs']['monthly_compute']:.2f}/month")
        print(f"    Storage (EBS): ${costs['costs']['monthly_storage']:.2f}/month")
        print(f"    ─────────────────────────────")
        print(f"    TOTAL MONTHLY: ${costs['costs']['monthly_total']:.2f}/month")
        print(f"    TOTAL YEARLY: ${costs['costs']['yearly_total']:.2f}/year")

        print(f"\n  💡 Cost Optimization Tips:")
        print(f"    - Use Spot Instances: Save up to 90% on compute costs")
        print(f"    - Stop instance when not in use: Save ${costs['costs']['monthly_compute']:.2f}/month")
        print(f"    - Use EBS snapshots: Reduce storage to ~${costs['costs']['monthly_storage']/5:.2f}/month")
        print(f"    - Cache installed tools: Avoid re-installation costs")

    # Cost comparison table
    print(f"\n📈 Cost Comparison Across Instance Types:")
    print(f"{'Instance':<15} {'$/hour':<10} {'One-Time':<12} {'Monthly':<12} {'Yearly':<12} {'Suitable':<10}")
    print("-" * 80)

    for rec in suitable[:5]:
        costs = calculate_aws_costs(metrics, rec['instance'])
        if costs:
            print(f"{rec['instance']:<15} "
                  f"${rec['price_hourly']:<9.4f} "
                  f"${costs['costs']['total_one_time']:<11.2f} "
                  f"${costs['costs']['monthly_total']:<11.2f} "
                  f"${costs['costs']['yearly_total']:<11.2f} "
                  f"{'✅' if rec['suitable'] else '❌':<10}")

    print("\n" + "="*80)

    # Save detailed JSON
    output_file = report_file.parent / 'aws_cost_analysis.json'
    with open(output_file, 'w') as f:
        json.dump({
            'metrics': metrics,
            'recommendations': recommendations,
            'detailed_costs': [calculate_aws_costs(metrics, r['instance']) for r in suitable[:5]]
        }, f, indent=2)

    print(f"\n✅ Detailed cost analysis saved to: {output_file}")


def main():
    """Main entry point"""
    report_file = Path('/private/tmp/lcms-platform-galaxy/tool_installation_report.txt')

    if len(sys.argv) > 1:
        report_file = Path(sys.argv[1])

    if not report_file.exists():
        print(f"❌ Report file not found: {report_file}")
        print(f"   Waiting for installation to complete...")
        print(f"   Usage: python3 {sys.argv[0]} [report_file]")
        return

    print_cost_analysis(report_file)


if __name__ == '__main__':
    main()
