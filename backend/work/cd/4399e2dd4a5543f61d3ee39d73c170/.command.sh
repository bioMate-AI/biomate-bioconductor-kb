#!/usr/bin/env python3
import json
import random
from datetime import datetime

particles_data = json.load(open('particles_extracted_r1.cs'))
num_particles = len(particles_data.get('particles', []))

# Simulate 2D classification
num_classes = 100
classes = []

for class_idx in range(num_classes):
    # Simulate class quality (some good, some bad)
    resolution = round(random.uniform(8.0, 25.0), 2)
    num_particles_in_class = random.randint(50, num_particles // num_classes * 2)

    # Good classes have better resolution and more particles
    is_good = resolution < 15.0 and num_particles_in_class > num_particles // num_classes * 0.8

    classes.append({
        'class_idx': class_idx,
        'num_particles': num_particles_in_class,
        'resolution_angstroms': resolution,
        'class_distribution': round(num_particles_in_class / num_particles, 4),
        'is_good_class': is_good
    })

num_good = sum(1 for c in classes if c['is_good_class'])

report = {
    'step': '09_classify_2d_round1',
    'timestamp': datetime.now().isoformat(),
    'num_particles': num_particles,
    'num_classes': num_classes,
    'num_good_classes': num_good,
    'avg_resolution_angstroms': round(sum(c['resolution_angstroms'] for c in classes) / num_classes, 2),
    'sample_type': 'unknown',
    'mock_mode': True
}

with open('class2d_r1.cs', 'w') as f:
    json.dump({'classes': classes}, f, indent=2)

with open('class2d_report.json', 'w') as f:
    json.dump(report, f, indent=2)

print(f"✓ 2D classified {num_particles} particles into {num_classes} classes")
print(f"  Good classes: {num_good}/{num_classes}")
