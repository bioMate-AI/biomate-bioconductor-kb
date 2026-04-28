#!/usr/bin/env python3
import json
import random
from datetime import datetime

classes_data = json.load(open('class2d_r2.cs'))
particles_data = json.load(open('particles_extracted_r2.cs'))

all_particles = particles_data.get('particles', [])

# Select ~70% for 3D reconstruction
num_to_select = int(len(all_particles) * 0.7)
selected = random.sample(all_particles, num_to_select)

report = {
    'step': '15_select_2d_round2',
    'timestamp': datetime.now().isoformat(),
    'num_input_particles': len(all_particles),
    'num_selected_particles': len(selected),
    'selection_ratio': round(len(selected) / len(all_particles), 3)
}

with open('particles_selected_r2.cs', 'w') as f:
    json.dump({'particles': selected}, f, indent=2)

with open('selection_report.json', 'w') as f:
    json.dump(report, f, indent=2)

print(f"✓ Selected {len(selected)} particles for 3D reconstruction")
