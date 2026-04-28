#!/usr/bin/env python3
import json
from datetime import datetime

mics_data = json.load(open('micrographs_ctf.cs'))
micrographs = mics_data.get('micrographs', [])

# Add denoising metadata
denoised = [
    {**mic, 'denoised': True, 'noise_model': 'gaussian'}
    for mic in micrographs
]

report = {
    'step': '04_micrograph_denoiser',
    'timestamp': datetime.now().isoformat(),
    'num_micrographs': len(micrographs),
    'denoiser_model': 'janni',
    'mock_mode': True
}

with open('micrographs_denoised.cs', 'w') as f:
    json.dump({'micrographs': denoised}, f, indent=2)

with open('denoise_report.json', 'w') as f:
    json.dump(report, f, indent=2)

print(f"✓ Denoised {len(micrographs)} micrographs")
