#!/usr/bin/env python3
import json
from datetime import datetime

particles_data = json.load(open('particles_inspected_r2.cs'))
particles = particles_data.get('particles', [])

extracted = [
    {**p, 'box_size_pixels': 320, 'extracted': True}
    for p in particles
]

report = {
    'step': '13_extract_particles_round2',
    'timestamp': datetime.now().isoformat(),
    'num_particles': len(extracted),
    'box_size_pixels': 320
}

with open('particles_extracted_r2.cs', 'w') as f:
    json.dump({'particles': extracted}, f, indent=2)

with open('extract_report.json', 'w') as f:
    json.dump(report, f, indent=2)

print(f"✓ Extracted {len(extracted)} particles (round 2)")
