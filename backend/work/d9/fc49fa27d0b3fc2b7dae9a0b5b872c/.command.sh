#!/usr/bin/env python3
import json
import random
from datetime import datetime

particles_data = json.load(open('particles_blob.cs'))
particles = particles_data.get('particles', [])

# Simulate junk filtering (remove ~10-20% of particles)
filtered = [
    {**p, 'junk_score': round(random.uniform(0.0, 0.3), 3)}
    for p in particles
    if random.random() > 0.15  # Keep 85%
]

report = {
    'step': '06_junk_2d_detector',
    'timestamp': datetime.now().isoformat(),
    'num_input_particles': len(particles),
    'num_output_particles': len(filtered),
    'num_rejected': len(particles) - len(filtered),
    'rejection_rate': round((len(particles) - len(filtered)) / len(particles), 3),
    'mock_mode': True
}

with open('particles_filtered.cs', 'w') as f:
    json.dump({'particles': filtered}, f, indent=2)

with open('junk_report.json', 'w') as f:
    json.dump(report, f, indent=2)

print(f"✓ Filtered particles: {len(particles)} → {len(filtered)} ({report['rejection_rate']*100:.1f}% rejected)")
