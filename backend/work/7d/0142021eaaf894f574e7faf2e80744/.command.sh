#!/usr/bin/env python3
import json
from datetime import datetime

particles_data = json.load(open('particles_inspected.cs'))
particles = particles_data.get('particles', [])

# Add extraction metadata
extracted = [
    {**p, 'box_size_pixels': 320, 'extracted': True}
    for p in particles
]

report = {
    'step': '08_extract_particles_round1',
    'timestamp': datetime.now().isoformat(),
    'num_particles': len(extracted),
    'box_size_pixels': 320,
    'pixel_size_angstroms': 1.05,
    'mock_mode': True
}

with open('particles_extracted_r1.cs', 'w') as f:
    json.dump({'particles': extracted}, f, indent=2)

with open('extract_report.json', 'w') as f:
    json.dump(report, f, indent=2)

print(f"✓ Extracted {len(extracted)} particles (box size: 320 px)")
