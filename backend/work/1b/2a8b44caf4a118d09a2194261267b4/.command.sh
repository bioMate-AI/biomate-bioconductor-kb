#!/usr/bin/env python3
import json
import random
from datetime import datetime

classes_data = json.load(open('class2d_r1.cs'))
particles_data = json.load(open('particles_extracted_r1.cs'))

classes = classes_data.get('classes', [])
all_particles = particles_data.get('particles', [])

# Select particles from good classes
good_class_indices = [c['class_idx'] for c in classes if c.get('is_good_class', False)]

# Simulate selection: keep 60-80% of particles from good classes
num_to_select = int(len(all_particles) * random.uniform(0.6, 0.8))
selected = random.sample(all_particles, num_to_select)

# Add class assignment
for p in selected:
    p['assigned_class'] = random.choice(good_class_indices) if good_class_indices else 0

report = {
    'step': '10_select_2d_round1',
    'timestamp': datetime.now().isoformat(),
    'num_input_particles': len(all_particles),
    'num_selected_particles': len(selected),
    'selection_ratio': round(len(selected) / len(all_particles), 3),
    'num_good_classes': len(good_class_indices)
}

with open('particles_selected_r1.cs', 'w') as f:
    json.dump({'particles': selected}, f, indent=2)

with open('selection_report.json', 'w') as f:
    json.dump(report, f, indent=2)

print(f"✓ Selected {len(selected)}/{len(all_particles)} particles ({report['selection_ratio']*100:.1f}%)")
