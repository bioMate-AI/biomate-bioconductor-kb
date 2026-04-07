nextflow.enable.dsl = 2

// IMPORT_MOVIES — Step 1 of CryoSPARC Standard SPA
// Shared with helical_spa_pipeline

process IMPORT_MOVIES {
    tag "import"
    publishDir "${params.outdir}/01_import_movies", mode: 'copy'

    input:
    path movies

    output:
    path "movies.cs", emit: movies_cs
    path "import_report.json", emit: report

    script:
    """
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
        'pixel_size_angstroms': ${params.pixel_size},
        'voltage_kv': ${params.voltage},
        'spherical_aberration_mm': ${params.spherical_aberration},
        'gain_reference': '${params.gain_ref}' if '${params.gain_ref}' != 'null' else None
    }

    # Create CryoSPARC-style .cs file
    cs_data = {
        'movies': [
            {
                'movie_path': str(m),
                'movie_idx': i,
                'num_frames': 40,
                'total_dose': ${params.total_dose}
            } for i, m in enumerate(movies)
        ]
    }

    with open('movies.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)

    with open('import_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Imported {len(movies)} movies")
    """
}
