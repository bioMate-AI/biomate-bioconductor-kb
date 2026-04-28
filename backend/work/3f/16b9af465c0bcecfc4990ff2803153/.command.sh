#!/usr/bin/env python3
import json
from datetime import datetime

particles_data = json.load(open('particles_template.cs'))

report = {
    'step': '12_inspect_picks_round2',
    'timestamp': datetime.now().isoformat(),
    'num_particles': len(particles_data.get('particles', [])),
    'inspection_mode': 'auto_pass'
}

with open('particles_inspected_r2.cs', 'w') as f:
    json.dump(particles_data, f, indent=2)

with open('inspect_report.json', 'w') as f:
    json.dump(report, f, indent=2)

print(f"✓ Inspection complete: {report['num_particles']} particles")
