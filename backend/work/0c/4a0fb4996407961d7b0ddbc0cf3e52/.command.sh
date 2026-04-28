#!/usr/bin/env python3
import json
import os
from pathlib import Path
from datetime import datetime

movies = sorted(Path('.').glob('*.tif')) + sorted(Path('.').glob('*.mrc')) + sorted(Path('.').glob('*.eer'))

report = {
    'step': '01_import_movies',
    'timestamp': datetime.now().isoformat(),
    'num_movies': len(movies),
    'pixel_size_angstroms': 1.05,
    'voltage_kv': 300,
    'spherical_aberration_mm': 2.7,
    'gain_reference': 'null' if 'null' != 'null' else None,
    'mock_mode': True
}

# Create CryoSPARC-style .cs file (mock format)
cs_data = {
    'movies': [
        {
            'movie_path': str(m),
            'movie_idx': i,
            'num_frames': 40,
            'total_dose': 50.0
        } for i, m in enumerate(movies)
    ]
}

with open('movies.cs', 'w') as f:
    json.dump(cs_data, f, indent=2)

with open('import_report.json', 'w') as f:
    json.dump(report, f, indent=2)

print(f"✓ Imported {len(movies)} movies")
