#!/usr/bin/env python3
import json
import random
from datetime import datetime

volumes_data = json.load(open('volumes_ab_initio.cs'))
particles_data = json.load(open('particles_selected_r2.cs'))

best_volume = volumes_data.get('best_volume', volumes_data['volumes'][0])
num_particles = len(particles_data.get('particles', []))

# Simulate refinement improving resolution
initial_res = best_volume['resolution_angstroms']
final_res = round(initial_res * random.uniform(0.4, 0.7), 2)  # Improve by 30-60%

refined = {
    'volume_idx': 0,
    'resolution_angstroms': final_res,
    'num_particles': num_particles,
    'fsc_0143_resolution': round(final_res * 1.05, 2)
}

# Simulate orientation anisotropy (3DFSC-style best:worst view ratio)
# Typical good datasets: 1.5-3×; problematic: > 5×
anisotropy = round(random.uniform(1.5, 4.0), 2)

report = {
    'step': '17_homogeneous_refinement',
    'timestamp': datetime.now().isoformat(),
    'num_particles': num_particles,
    'initial_resolution_angstroms': initial_res,
    'final_resolution_angstroms': final_res,
    'resolution_improvement': round((initial_res - final_res) / initial_res * 100, 1),
    'symmetry': 'C1',
    'orientation_anisotropy_ratio': anisotropy,
}

with open('refined_volume.cs', 'w') as f:
    json.dump({'volume': refined}, f, indent=2)

with open('refinement_report.json', 'w') as f:
    json.dump(report, f, indent=2)

print(f"✓ Homogeneous refinement: {initial_res} Å → {final_res} Å")
