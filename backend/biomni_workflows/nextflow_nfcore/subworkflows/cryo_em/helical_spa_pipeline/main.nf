#!/usr/bin/env nextflow
/*
 * Helical SPA Pipeline
 *
 * Complete CryoSPARC helical single-particle analysis workflow for
 * filamentous assemblies (F-actin, amyloid fibrils, microtubules, intermediate
 * filaments, viral tubes, etc.).  All 11 steps are self-contained; no external
 * module imports are required.
 *
 * Pipeline steps:
 *   01. IMPORT_MOVIES             -- ingest raw movie stacks
 *   02. PATCH_MOTION_CORRECTION   -- per-patch beam-induced motion
 *   03. PATCH_CTF_ESTIMATION      -- per-patch CTF fitting (CTFFIND4 backend)
 *   04. FILAMENT_TRACER           -- trace filament axes; generate helical picks
 *   05. EXTRACT_HELICAL_PARTICLES -- extract boxes along filaments
 *   06. CLASSIFY_2D_HELICAL       -- 2-D classification of helical segments
 *   07. SELECT_2D_HELICAL         -- select clean 2-D class averages
 *   08. AB_INITIO_HELICAL         -- initial helical volume (symmetry-free)
 *   09. HELICAL_REFINEMENT        -- gold-standard helical reconstruction
 *   10. HELICAL_SHARPENING        -- post-processing / B-factor sharpening
 *   11. HELICAL_PIPELINE_SUMMARY  -- aggregate JSON report
 *
 * References:
 *   Punjani et al. 2017 Nat Methods 14:290    (CryoSPARC)
 *   Bepler et al. 2019 Nat Methods 16:1153    (Topaz)
 *   He & Bharat 2021 eLife 10:e71636          (CryoSPARC helical refinement)
 *   Fromm et al. 2021 eLife 10:e68028         (filament picking strategy)
 *   Gremer et al. 2017 Science 358:116        (amyloid reference: rise 4.75 A)
 *   Alushin et al. 2014 Cell 157:1117         (F-actin reference: rise 27.5 A)
 *
 * Domain: Cryo-EM / CryoSPARC / Helical
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

// Input / Output
params.movies_path   = null                         // raw movie files (*.tif/*.mrc/*.eer)
params.outdir        = './results/helical_spa'

// Acquisition
params.pixel_size    = 1.05    // A/px
params.voltage       = 300     // kV
params.cs            = 2.7     // spherical aberration (mm)
params.total_dose    = 50.0    // e-/A2

// Helical parameters
params.filament_diameter_angstroms  = 150      // A
params.helical_rise_angstroms       = 4.75     // A  (amyloid default)
params.helical_twist_deg            = -166.15  // deg  (actin default; amyloid: -179.35)
params.overlap_fraction             = 0.9
params.min_filament_length_angstroms = 500

// Refinement
params.symmetry                = 'C1'
params.initial_lowpass         = 12.0   // A
params.refine_helical_params   = true

// CryoSPARC connection
params.use_cryosparc  = false

// ============================================================================
// Helper functions
// ============================================================================

def step_label(String step) {
    return "[helical_spa] ${step}"
}

def cs_connect_block() {
    return """
    from cryosparc.tools import CryoSPARC
    cs_conn = CryoSPARC(
        host='${params.cryosparc_host ?: "localhost"}',
        port=${params.cryosparc_port ?: 39000},
        email='${params.cryosparc_email ?: ""}',
        password='${params.cryosparc_password ?: ""}'
    )
    project   = cs_conn.find_project('${params.cryosparc_project_uid ?: ""}')
    workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')
    """
}

// ============================================================================
// Processes
// ============================================================================

process IMPORT_MOVIES {
    tag { step_label('01_import_movies') }
    publishDir "${params.outdir}/01_import_movies", mode: 'copy'

    input:
    path movies_dir

    output:
    path "movies.cs",          emit: movies_cs
    path "import_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    import os
    from pathlib import Path
    from datetime import datetime

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs_conn = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs_conn.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('import_movies', params={
            'movie_path':     '${params.movies_path ?: "."}',
            'pixel_size_A':   ${params.pixel_size},
            'kv':             ${params.voltage},
            'cs_mm':          ${params.cs},
            'total_dose_eA2': ${params.total_dose}
        })
        job.queue()
        job.wait_for_done()

        movies_out = list(job.load_output('movies'))
        num_movies = len(movies_out)
        cs_data = {'movies': movies_out}
    else:
        # Scan the movies directory for movie files
        p = Path('${params.movies_path ?: "."}')
        files = (sorted(p.glob('*.tif')) + sorted(p.glob('*.mrc')) +
                 sorted(p.glob('*.eer')) + sorted(p.glob('*.tiff')))
        num_movies = len(files)
        if num_movies == 0:
            raise RuntimeError(
                f"No movie files (*.tif/*.mrc/*.eer) found in '{p}'. "
                "Provide --movies_path pointing to your movie directory."
            )
        cs_data = {
            'movies': [
                {'movie_path': str(m), 'movie_idx': i,
                 'num_frames': 40, 'total_dose': ${params.total_dose}}
                for i, m in enumerate(files)
            ]
        }

    report = {
        'step':                    '01_import_movies',
        'timestamp':               datetime.now().isoformat(),
        'num_movies':              num_movies,
        'pixel_size_angstroms':    ${params.pixel_size},
        'voltage_kv':              ${params.voltage},
        'spherical_aberration_mm': ${params.cs},
        'total_dose':              ${params.total_dose}
    }

    with open('movies.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)
    with open('import_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Imported {num_movies} movies")
    """
}

// ---------------------------------------------------------------------------

process PATCH_MOTION_CORRECTION {
    tag { step_label('02_motion_correction') }
    publishDir "${params.outdir}/02_motion_correction", mode: 'copy'

    input:
    path movies_cs

    output:
    path "micrographs.cs",      emit: micrographs_cs
    path "motion_report.json",  emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    movies_data  = json.load(open('${movies_cs}'))
    movies_list  = movies_data.get('movies', [])
    num_movies   = len(movies_list)

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs_conn = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs_conn.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('patch_motion_correction', connections={
            'movies': ('${params.cryosparc_import_job_uid ?: ""}', 'movies')
        })
        job.queue()
        job.wait_for_done()

        mics_out = list(job.load_output('micrographs'))
        micrographs = mics_out
        stats = job.doc.get('output_stats', {})
        avg_total_motion = stats.get('avg_total_motion_angstroms', 0.0)
    else:
        raise RuntimeError(
            "CryoSPARC connection required for motion correction. "
            "Set --use_cryosparc true and provide CryoSPARC connection params."
        )

    report = {
        'step':                        '02_patch_motion_correction',
        'timestamp':                   datetime.now().isoformat(),
        'num_micrographs':             len(micrographs),
        'avg_total_motion_angstroms':  avg_total_motion
    }

    with open('micrographs.cs', 'w') as f:
        json.dump({'micrographs': micrographs}, f, indent=2)
    with open('motion_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Motion corrected {len(micrographs)} micrographs")
    """
}

// ---------------------------------------------------------------------------

process PATCH_CTF_ESTIMATION {
    tag { step_label('03_ctf_estimation') }
    publishDir "${params.outdir}/03_ctf_estimation", mode: 'copy'

    input:
    path micrographs_cs

    output:
    path "micrographs_ctf.cs",  emit: ctf_cs
    path "ctf_report.json",     emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    mics_data   = json.load(open('${micrographs_cs}'))
    micrographs = mics_data.get('micrographs', [])

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs_conn = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs_conn.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('patch_ctf_estimation', connections={
            'micrographs': ('${params.cryosparc_motion_job_uid ?: ""}', 'micrographs')
        })
        job.queue()
        job.wait_for_done()

        ctf_out = list(job.load_output('micrographs'))
        stats = job.doc.get('output_stats', {})
        avg_defocus = stats.get('avg_defocus_angstroms', 0.0)
        avg_fit_res = stats.get('avg_fit_resolution_angstroms', 0.0)
    else:
        raise RuntimeError(
            "CryoSPARC connection required for CTF estimation. "
            "Set --use_cryosparc true and provide CryoSPARC connection params."
        )

    report = {
        'step':                        '03_patch_ctf_estimation',
        'timestamp':                   datetime.now().isoformat(),
        'num_micrographs':             len(ctf_out),
        'avg_defocus_angstroms':       avg_defocus,
        'avg_fit_resolution_angstroms': avg_fit_res
    }

    with open('micrographs_ctf.cs', 'w') as f:
        json.dump({'micrographs': ctf_out}, f, indent=2)
    with open('ctf_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"CTF estimated: {len(ctf_out)} micrographs  |  avg defocus: {avg_defocus} A")
    """
}

// ---------------------------------------------------------------------------

process FILAMENT_TRACER {
    tag { step_label('04_filament_tracer') }
    publishDir "${params.outdir}/04_filament_tracer", mode: 'copy'

    input:
    path micrographs_ctf_cs

    output:
    path "filament_picks.cs",           emit: filament_picks_cs
    path "filament_tracer_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    mics_data   = json.load(open('${micrographs_ctf_cs}'))
    micrographs = mics_data.get('micrographs', [])
    num_mics    = len(micrographs)

    helical_rise     = ${params.helical_rise_angstroms}
    overlap_fraction = ${params.overlap_fraction}
    min_length       = ${params.min_filament_length_angstroms}

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs_conn = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs_conn.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('filament_tracer', connections={
            'micrographs': ('${params.cryosparc_ctf_job_uid ?: ""}', 'micrographs')
        }, params={
            'fil_diameter':         ${params.filament_diameter_angstroms},
            'fil_rise_A':           helical_rise,
            'fil_overlap_fraction': overlap_fraction,
            'fil_min_length_A':     min_length
        })
        job.queue()
        job.wait_for_done()

        picks_out       = list(job.load_output('particles'))
        total_filaments = job.doc.get('output_stats', {}).get('num_filaments', len(picks_out))
        total_picks     = len(picks_out)
        cs_data = {'picks': picks_out, 'num_filaments': total_filaments,
                   'num_picks': total_picks, 'num_micrographs': num_mics}
    else:
        raise RuntimeError(
            "CryoSPARC connection required for filament tracing. "
            "Set --use_cryosparc true and provide CryoSPARC connection params."
        )

    report = {
        'step':                          '04_filament_tracer',
        'timestamp':                     datetime.now().isoformat(),
        'num_micrographs':               num_mics,
        'total_filaments_traced':        cs_data['num_filaments'],
        'total_particles_picked':        cs_data['num_picks'],
        'filament_diameter_angstroms':   ${params.filament_diameter_angstroms}
    }

    with open('filament_picks.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)
    with open('filament_tracer_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Filament tracing: {cs_data['num_filaments']} filaments | {cs_data['num_picks']} picks")
    """
}

// ---------------------------------------------------------------------------

process EXTRACT_HELICAL_PARTICLES {
    tag { step_label('05_extract_particles') }
    publishDir "${params.outdir}/05_extract_particles", mode: 'copy'

    input:
    path filament_picks_cs

    output:
    path "helical_particles.cs",      emit: particles_cs
    path "extract_report.json",       emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    picks_data = json.load(open('${filament_picks_cs}'))
    picks      = picks_data.get('picks', [])
    num_picks  = len(picks)

    # Box size derived from filament diameter (1.5x diameter, rounded to power of 2)
    diameter_ang = ${params.filament_diameter_angstroms}
    pixel_size   = ${params.pixel_size}
    box_px_raw   = diameter_ang * 1.5 / pixel_size
    powers       = [64, 96, 128, 192, 256, 320, 384, 440, 512]
    box_size     = next((p for p in powers if p >= box_px_raw), 256)

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs_conn = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs_conn.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('extract_helical', connections={
            'particles':    ('${params.cryosparc_filament_job_uid ?: ""}', 'particles'),
            'micrographs':  ('${params.cryosparc_ctf_job_uid ?: ""}', 'micrographs')
        }, params={
            'box_size_pix': box_size
        })
        job.queue()
        job.wait_for_done()

        particles_out = list(job.load_output('particles'))
    else:
        raise RuntimeError(
            "CryoSPARC connection required for particle extraction. "
            "Set --use_cryosparc true and provide CryoSPARC connection params."
        )

    report = {
        'step':            '05_extract_helical_particles',
        'timestamp':       datetime.now().isoformat(),
        'num_particles':   len(particles_out),
        'box_size_pixels': box_size,
        'pixel_size':      pixel_size
    }

    with open('helical_particles.cs', 'w') as f:
        json.dump({'particles': particles_out}, f, indent=2)
    with open('extract_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Extracted {len(particles_out)} helical segments  |  box size: {box_size} px")
    """
}

// ---------------------------------------------------------------------------

process CLASSIFY_2D_HELICAL {
    tag { step_label('06_classify_2d') }
    label 'process_gpu'
    publishDir "${params.outdir}/06_classify_2d", mode: 'copy'

    input:
    path particles_cs

    output:
    path "classes_2d_helical.cs",  emit: classes_cs
    path "classify_2d_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    parts_data = json.load(open('${particles_cs}'))
    particles  = parts_data.get('particles', [])
    num_parts  = len(particles)

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs_conn = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs_conn.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('class_2D', connections={
            'particles': ('${params.cryosparc_extract_job_uid ?: ""}', 'particles')
        }, params={
            'num_classes': 50
        })
        job.queue()
        job.wait_for_done()

        classes_out  = list(job.load_output('class_averages'))
        particles_out = list(job.load_output('particles'))
        stats = job.doc.get('output_stats', {})
        num_good_classes = stats.get('num_good_helical_classes', len(classes_out))
        good_particles   = stats.get('particles_in_good_classes', len(particles_out))
        num_classes      = len(classes_out)
    else:
        raise RuntimeError(
            "CryoSPARC connection required for 2D classification. "
            "Set --use_cryosparc true and provide CryoSPARC connection params."
        )

    report = {
        'step':               '06_classify_2d_helical',
        'timestamp':          datetime.now().isoformat(),
        'num_particles_in':   num_parts,
        'num_classes':        num_classes,
        'num_good_helical_classes': num_good_classes,
        'particles_in_good_classes': good_particles,
        'junk_fraction':      round(1.0 - good_particles / max(num_parts, 1), 4)
    }

    with open('classes_2d_helical.cs', 'w') as f:
        json.dump({'classes': classes_out, 'particles': particles_out}, f, indent=2)
    with open('classify_2d_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"2D classification: {num_good_classes}/{num_classes} good helical classes")
    """
}

// ---------------------------------------------------------------------------

process SELECT_2D_HELICAL {
    tag { step_label('07_select_2d') }
    publishDir "${params.outdir}/07_select_2d", mode: 'copy'

    input:
    path classes_cs

    output:
    path "selected_helical_particles.cs",  emit: selected_cs
    path "select_2d_report.json",          emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    data      = json.load(open('${classes_cs}'))
    classes   = data.get('classes', [])
    particles = data.get('particles', [])

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs_conn = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs_conn.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        # Select classes interactively or by score threshold
        job = workspace.create_job('select_2D', connections={
            'particles':     ('${params.cryosparc_classify2d_job_uid ?: ""}', 'particles'),
            'class_averages': ('${params.cryosparc_classify2d_job_uid ?: ""}', 'class_averages')
        })
        job.queue()
        job.wait_for_done()

        selected_out = list(job.load_output('particles'))
        good_classes = job.doc.get('output_stats', {}).get('num_classes_selected', len(classes))
    else:
        raise RuntimeError(
            "CryoSPARC connection required for 2D selection. "
            "Set --use_cryosparc true and provide CryoSPARC connection params."
        )

    num_before = len(particles)
    num_after  = len(selected_out)

    report = {
        'step':                '07_select_2d_helical',
        'timestamp':           datetime.now().isoformat(),
        'num_particles_before': num_before,
        'num_particles_after':  num_after,
        'num_classes_selected': good_classes,
        'fraction_retained':    round(num_after / max(num_before, 1), 4)
    }

    with open('selected_helical_particles.cs', 'w') as f:
        json.dump({'particles': selected_out}, f, indent=2)
    with open('select_2d_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Selected {num_after}/{num_before} particles from {good_classes} good classes")
    """
}

// ---------------------------------------------------------------------------

process AB_INITIO_HELICAL {
    tag { step_label('08_ab_initio') }
    label 'process_gpu'
    publishDir "${params.outdir}/08_ab_initio", mode: 'copy'

    input:
    path selected_particles_cs

    output:
    path "initial_helical_volume.cs",  emit: volume_cs
    path "ab_initio_report.json",      emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    parts_data = json.load(open('${selected_particles_cs}'))
    particles  = parts_data.get('particles', [])
    num_parts  = len(particles)

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs_conn = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs_conn.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('ab_initio_reconstruction', connections={
            'particles': ('${params.cryosparc_select2d_job_uid ?: ""}', 'particles')
        }, params={
            'symmetry':          '${params.symmetry}',
            'helical_rise_A':    ${params.helical_rise_angstroms},
            'helical_twist_deg': ${params.helical_twist_deg}
        })
        job.queue()
        job.wait_for_done()

        stats   = job.doc.get('output_stats', {})
        init_res = stats.get('fsc_resolution_0143', 15.0)
        vol_out  = list(job.load_output('volume'))
        volume_data = {'volume': {
            'resolution_angstroms': init_res,
            'helical_rise':         ${params.helical_rise_angstroms},
            'helical_twist':        ${params.helical_twist_deg},
            'symmetry':             '${params.symmetry}',
            'volume_path':          'initial_helical_volume.mrc'
        }}
    else:
        raise RuntimeError(
            "CryoSPARC connection required for ab-initio reconstruction. "
            "Set --use_cryosparc true and provide CryoSPARC connection params."
        )

    with open('initial_helical_volume.cs', 'w') as f:
        json.dump(volume_data, f, indent=2)

    report = {
        'step':                    '08_ab_initio_helical',
        'timestamp':               datetime.now().isoformat(),
        'num_particles':           num_parts,
        'initial_resolution':      init_res,
        'helical_rise_angstroms':  ${params.helical_rise_angstroms},
        'helical_twist_deg':       ${params.helical_twist_deg},
        'symmetry':                '${params.symmetry}'
    }

    with open('ab_initio_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Ab-initio complete: initial resolution {init_res} A")
    """
}

// ---------------------------------------------------------------------------

process HELICAL_REFINEMENT {
    tag { step_label('09_helical_refinement') }
    label 'process_gpu'
    publishDir "${params.outdir}/09_helical_refinement", mode: 'copy'

    input:
    path particles_cs
    path volume_cs

    output:
    path "helical_refined_volume.cs",       emit: refined_volume_cs
    path "helical_refinement_report.json",  emit: report

    script:
    def refine_params = params.refine_helical_params ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    refine_hel = ${refine_params}
    parts_data = json.load(open('${particles_cs}'))
    vol_data   = json.load(open('${volume_cs}'))

    particles  = parts_data.get('particles', [])
    num_parts  = len(particles)

    input_rise  = ${params.helical_rise_angstroms}
    input_twist = ${params.helical_twist_deg}

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs_conn = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs_conn.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('helical_refine', connections={
            'particles': ('${params.cryosparc_select2d_job_uid ?: ""}', 'particles'),
            'volume':    ('${params.cryosparc_abinitio_job_uid ?: ""}', 'volume')
        }, params={
            'helical_rise_A':    input_rise,
            'helical_twist_deg': input_twist,
            'symmetry':          '${params.symmetry}',
            'init_res':          ${params.initial_lowpass},
            'refine_helical':    refine_hel
        })
        job.queue()
        job.wait_for_done()

        stats         = job.doc.get('output_stats', {})
        refined_rise  = stats.get('helical_rise_A', input_rise)
        refined_twist = stats.get('helical_twist_deg', input_twist)
        final_res     = stats.get('fsc_resolution_0143', 0.0)

        volume_out = {'volume': {
            'resolution_angstroms': final_res,
            'helical_rise':         refined_rise,
            'helical_twist':        refined_twist,
            'symmetry':             '${params.symmetry}',
            'volume_path':          'helical_refined_volume.mrc'
        }}
        with open('helical_refined_volume.cs', 'w') as f:
            json.dump(volume_out, f, indent=2)
    else:
        raise RuntimeError(
            "CryoSPARC connection required for helical refinement. "
            "Set --use_cryosparc true and provide CryoSPARC connection params."
        )

    report = {
        'step':                              '09_helical_refinement',
        'timestamp':                         datetime.now().isoformat(),
        'input_helical_rise_angstroms':      input_rise,
        'input_helical_twist_deg':           input_twist,
        'refined_helical_rise_angstroms':    refined_rise,
        'refined_helical_twist_deg':         refined_twist,
        'final_fsc_0143_resolution':         final_res,
        'helical_rise_convergence_angstroms': round(abs(refined_rise - input_rise), 4),
        'helical_twist_convergence_deg':     round(abs(refined_twist - input_twist), 4),
        'num_particles':                     num_parts,
        'symmetry':                          '${params.symmetry}'
    }

    with open('helical_refinement_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Helical refinement: {final_res} A  |  rise: {refined_rise} A  |  twist: {refined_twist} deg")
    """
}

// ---------------------------------------------------------------------------

process HELICAL_SHARPENING {
    tag { step_label('10_sharpening') }
    publishDir "${params.outdir}/10_sharpening", mode: 'copy'

    input:
    path refined_volume_cs

    output:
    path "sharpened_helical_volume.cs",  emit: sharpened_volume_cs
    path "sharpening_report.json",       emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    vol_data = json.load(open('${refined_volume_cs}'))
    volume   = vol_data.get('volume', {})
    res_in   = volume.get('resolution_angstroms', 4.0)

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs_conn = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs_conn.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('sharpen_map', connections={
            'volume': ('${params.cryosparc_refine_job_uid ?: ""}', 'volume')
        })
        job.queue()
        job.wait_for_done()

        stats    = job.doc.get('output_stats', {})
        b_factor = stats.get('b_factor_angstroms_squared', 0.0)
        res_out  = stats.get('fsc_resolution_0143', res_in)

        sharpened_volume = {'volume': {
            **volume,
            'resolution_angstroms': res_out,
            'b_factor_applied':     b_factor,
            'volume_path':          'sharpened_helical_volume.mrc'
        }}
        with open('sharpened_helical_volume.cs', 'w') as f:
            json.dump(sharpened_volume, f, indent=2)
    else:
        raise RuntimeError(
            "CryoSPARC connection required for map sharpening. "
            "Set --use_cryosparc true and provide CryoSPARC connection params."
        )

    report = {
        'step':                          '10_helical_sharpening',
        'timestamp':                     datetime.now().isoformat(),
        'input_resolution_angstroms':    res_in,
        'output_resolution_angstroms':   res_out,
        'b_factor_angstroms_squared':    b_factor,
        'helical_rise_angstroms':        volume.get('helical_rise', ${params.helical_rise_angstroms}),
        'helical_twist_deg':             volume.get('helical_twist', ${params.helical_twist_deg})
    }

    with open('sharpening_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Sharpening: B={b_factor} A2  |  resolution: {res_in} -> {res_out} A")
    """
}

// ---------------------------------------------------------------------------

process HELICAL_PIPELINE_SUMMARY {
    tag { step_label('11_summary') }
    publishDir "${params.outdir}/11_summary", mode: 'copy'

    input:
    path import_report
    path motion_report
    path ctf_report
    path filament_report
    path extract_report
    path classify_report
    path select_report
    path ab_initio_report
    path refinement_report
    path sharpening_report
    path sharpened_volume

    output:
    path "helical_pipeline_summary.json", emit: summary

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    def load(fname):
        try:
            return json.load(open(fname))
        except Exception:
            return {}

    imp    = load('${import_report}')
    mot    = load('${motion_report}')
    ctf    = load('${ctf_report}')
    fil    = load('${filament_report}')
    ext    = load('${extract_report}')
    cls    = load('${classify_report}')
    sel    = load('${select_report}')
    ab     = load('${ab_initio_report}')
    ref    = load('${refinement_report}')
    sharp  = load('${sharpening_report}')
    vol    = load('${sharpened_volume}').get('volume', {})

    summary = {
        'pipeline':          'helical_spa_pipeline',
        'timestamp':         datetime.now().isoformat(),
        'steps_completed':   11,

        'acquisition': {
            'num_movies':              imp.get('num_movies', 0),
            'pixel_size_angstroms':    ${params.pixel_size},
            'voltage_kv':              ${params.voltage},
            'total_dose':              ${params.total_dose}
        },

        'motion_correction': {
            'num_micrographs':             mot.get('num_micrographs', 0),
            'avg_total_motion_angstroms':  mot.get('avg_total_motion_angstroms', 0)
        },

        'ctf_estimation': {
            'avg_defocus_angstroms':        ctf.get('avg_defocus_angstroms', 0),
            'avg_fit_resolution_angstroms': ctf.get('avg_fit_resolution_angstroms', 0)
        },

        'filament_picking': {
            'total_filaments_traced':        fil.get('total_filaments_traced', 0),
            'total_particles_picked':        fil.get('total_particles_picked', 0),
            'filament_diameter_angstroms':   ${params.filament_diameter_angstroms}
        },

        'extraction': {
            'num_particles':   ext.get('num_particles', 0),
            'box_size_pixels': ext.get('box_size_pixels', 0)
        },

        '2d_classification': {
            'num_classes':             cls.get('num_classes', 0),
            'num_good_helical_classes': cls.get('num_good_helical_classes', 0),
            'junk_fraction':           cls.get('junk_fraction', 0)
        },

        'particle_selection': {
            'num_particles_before': sel.get('num_particles_before', 0),
            'num_particles_after':  sel.get('num_particles_after', 0),
            'fraction_retained':    sel.get('fraction_retained', 0)
        },

        'ab_initio': {
            'initial_resolution': ab.get('initial_resolution', 0)
        },

        'helical_refinement': {
            'final_fsc_0143_resolution':      ref.get('final_fsc_0143_resolution', 0),
            'refined_helical_rise_angstroms':  ref.get('refined_helical_rise_angstroms', ${params.helical_rise_angstroms}),
            'refined_helical_twist_deg':       ref.get('refined_helical_twist_deg', ${params.helical_twist_deg}),
            'rise_convergence_angstroms':      ref.get('helical_rise_convergence_angstroms', 0),
            'twist_convergence_deg':           ref.get('helical_twist_convergence_deg', 0)
        },

        'final_map': {
            'resolution_angstroms':   sharp.get('output_resolution_angstroms', vol.get('resolution_angstroms', 0)),
            'b_factor_angstroms_sq':  sharp.get('b_factor_angstroms_squared', 0),
            'map_file':               'sharpened_helical_volume.mrc'
        }
    }

    with open('helical_pipeline_summary.json', 'w') as f:
        json.dump(summary, f, indent=2)

    final_res = summary['final_map']['resolution_angstroms']
    print(f"Helical SPA pipeline complete")
    print(f"  Movies         : {summary['acquisition']['num_movies']}")
    print(f"  Filaments      : {summary['filament_picking']['total_filaments_traced']}")
    print(f"  Particles      : {summary['particle_selection']['num_particles_after']}")
    print(f"  Final resolution: {final_res} A")
    print(f"  Rise / Twist   : {summary['helical_refinement']['refined_helical_rise_angstroms']} A / {summary['helical_refinement']['refined_helical_twist_deg']} deg")
    """
}

// ============================================================================
// Named sub-workflow
// ============================================================================

workflow HELICAL_SPA_PIPELINE {
    take:
    ch_movies

    main:

    // Step 01
    IMPORT_MOVIES(ch_movies)

    // Step 02
    PATCH_MOTION_CORRECTION(IMPORT_MOVIES.out.movies_cs)

    // Step 03
    PATCH_CTF_ESTIMATION(PATCH_MOTION_CORRECTION.out.micrographs_cs)

    // Step 04
    FILAMENT_TRACER(PATCH_CTF_ESTIMATION.out.ctf_cs)

    // Step 05
    EXTRACT_HELICAL_PARTICLES(FILAMENT_TRACER.out.filament_picks_cs)

    // Step 06
    CLASSIFY_2D_HELICAL(EXTRACT_HELICAL_PARTICLES.out.particles_cs)

    // Step 07
    SELECT_2D_HELICAL(CLASSIFY_2D_HELICAL.out.classes_cs)

    // Step 08
    AB_INITIO_HELICAL(SELECT_2D_HELICAL.out.selected_cs)

    // Step 09
    HELICAL_REFINEMENT(
        SELECT_2D_HELICAL.out.selected_cs,
        AB_INITIO_HELICAL.out.volume_cs
    )

    // Step 10
    HELICAL_SHARPENING(HELICAL_REFINEMENT.out.refined_volume_cs)

    // Step 11
    HELICAL_PIPELINE_SUMMARY(
        IMPORT_MOVIES.out.report,
        PATCH_MOTION_CORRECTION.out.report,
        PATCH_CTF_ESTIMATION.out.report,
        FILAMENT_TRACER.out.report,
        EXTRACT_HELICAL_PARTICLES.out.report,
        CLASSIFY_2D_HELICAL.out.report,
        SELECT_2D_HELICAL.out.report,
        AB_INITIO_HELICAL.out.report,
        HELICAL_REFINEMENT.out.report,
        HELICAL_SHARPENING.out.report,
        HELICAL_SHARPENING.out.sharpened_volume_cs
    )

    emit:
    final_map = HELICAL_SHARPENING.out.sharpened_volume_cs
    summary   = HELICAL_PIPELINE_SUMMARY.out.summary
}

// ============================================================================
// Entry point
// ============================================================================

workflow {
    ch_movies = params.movies_path
        ? Channel.fromPath(params.movies_path, checkIfExists: true)
        : Channel.value('mock_movies')

    HELICAL_SPA_PIPELINE(ch_movies)
}
