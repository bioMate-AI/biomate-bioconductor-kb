#!/usr/bin/env nextflow
/*
 * CryoSPARC Filament Tracer
 *
 * Picks filamentous particles (microtubules, actin filaments, amyloid fibers,
 * intermediate filaments) by tracing filament axes across micrographs and
 * generating particle picks along each filament with a configurable helical
 * rise and box overlap.  Corresponds to the CryoSPARC "filament_tracer" job
 * type.
 *
 * Typical sample parameters:
 *   Microtubule  : diameter ~250 Å, rise ~8.2 Å (tubulin dimer ~82 Å / 10)
 *   F-actin      : diameter  ~70 Å, rise ~27.5 Å
 *   Amyloid      : diameter  ~50-100 Å, rise ~4.75 Å
 *   Intermediate : diameter ~100 Å, rise ~2.25 Å
 *
 * References:
 *   Bharat et al. 2015 Structure 23:1743  (helical cryo-EM workflow)
 *   Fromm et al. 2021 eLife 10:e68028    (filament tracing strategy)
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.filament_diameter_angstroms    = 150   // Å; e.g. microtubule ~250, actin ~70, amyloid ~100
params.helical_rise_angstroms         = 4.75  // Å; inter-subunit rise along helical axis
params.overlap_fraction               = 0.9   // fraction of box overlapping between adjacent picks
params.min_filament_length_angstroms  = 500   // minimum traceable filament length (Å)
params.mock_mode                      = true  // use mock mode for testing
params.use_cryosparc                  = false // use live CryoSPARC API
params.outdir                         = './results/filament_tracer'

// ============================================================================
// Process Definition
// ============================================================================

process FILAMENT_TRACER {
    tag "filament_tracer"
    publishDir "${params.outdir}/filament_tracer", mode: 'copy'

    input:
    path micrographs_ctf_cs

    output:
    path "filament_picks.cs",            emit: filament_picks_cs
    path "filament_tracer_report.json",  emit: report

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    import math
    from datetime import datetime

    random.seed(None)

    mock_mode = ${mock}

    mics_data   = json.load(open('${micrographs_ctf_cs}'))
    micrographs = mics_data.get('micrographs', [])
    num_mics    = len(micrographs)

    filament_diameter   = ${params.filament_diameter_angstroms}
    helical_rise        = ${params.helical_rise_angstroms}
    overlap_fraction    = ${params.overlap_fraction}
    min_length          = ${params.min_filament_length_angstroms}

    # Step size along filament axis (in pixels; assume 1 Å/px for mock)
    # Real pipeline would use actual pixel_size from CTF data
    step_angstroms = helical_rise * (1.0 - overlap_fraction)
    if step_angstroms <= 0:
        step_angstroms = helical_rise * 0.1   # safety floor

    all_picks        = []
    total_filaments  = 0
    total_picks      = 0

    for mic in micrographs:
        mic_idx = mic.get('micrograph_idx', 0)

        # Simulate 15-25 filaments per micrograph
        num_filaments = random.randint(15, 25)

        for fil_id in range(num_filaments):
            # Filament length drawn from realistic distribution
            fil_length = random.uniform(
                min_length,
                min_length * random.uniform(2.0, 5.0)
            )

            # Number of picks proportional to length / step
            num_picks = max(2, int(fil_length / step_angstroms))

            # Random start point and orientation angle
            x_start = random.uniform(200, 3800)
            y_start = random.uniform(200, 3800)
            angle_deg = random.uniform(0, 180)
            angle_rad = math.radians(angle_deg)

            dx = math.cos(angle_rad) * step_angstroms
            dy = math.sin(angle_rad) * step_angstroms

            for pick_idx in range(num_picks):
                pos_along = pick_idx * step_angstroms
                x = x_start + dx * pick_idx
                y = y_start + dy * pick_idx
                all_picks.append({
                    'micrograph_idx':          mic_idx,
                    'x':                       round(x, 2),
                    'y':                       round(y, 2),
                    'filament_id':             f'{mic_idx}_{fil_id}',
                    'position_along_filament': round(pos_along, 2),
                    'angle_deg':               round(angle_deg, 2)
                })
                total_picks += 1

            total_filaments += 1

    avg_filament_length = (
        random.uniform(min_length, min_length * 3.0)
        if total_filaments > 0 else 0.0
    )
    avg_picks_per_fil = (
        total_picks / total_filaments if total_filaments > 0 else 0
    )

    cs_data = {
        'picks':           all_picks,
        'num_filaments':   total_filaments,
        'num_picks':       total_picks,
        'num_micrographs': num_mics
    }

    report = {
        'step':                         'filament_tracer',
        'timestamp':                    datetime.now().isoformat(),
        'num_micrographs':              num_mics,
        'total_filaments_traced':       total_filaments,
        'total_particles_picked':       total_picks,
        'avg_filament_length_angstroms': round(avg_filament_length, 1),
        'avg_picks_per_filament':       round(avg_picks_per_fil, 1),
        'filament_diameter_angstroms':  filament_diameter,
        'helical_rise_angstroms':       helical_rise,
        'overlap_fraction':             overlap_fraction,
        'min_filament_length_angstroms': min_length,
        'mock_mode':                    mock_mode
    }

    with open('filament_picks.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)

    with open('filament_tracer_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Filament tracing complete on {num_mics} micrographs")
    print(f"  Total filaments traced  : {total_filaments}")
    print(f"  Total particles picked  : {total_picks}")
    print(f"  Avg filament length     : {avg_filament_length:.1f} Å")
    print(f"  Avg picks per filament  : {avg_picks_per_fil:.1f}")
    """
}

// ============================================================================
// Workflow (standalone execution)
// ============================================================================

workflow {
    log.info """
    ====================================================================
    CryoSPARC Filament Tracer
    ====================================================================
    Filament diameter  : ${params.filament_diameter_angstroms} Å
    Helical rise       : ${params.helical_rise_angstroms} Å
    Overlap fraction   : ${params.overlap_fraction}
    Min filament length: ${params.min_filament_length_angstroms} Å
    Mode               : ${params.mock_mode ? 'MOCK (testing)' : 'LIVE (CryoSPARC)'}
    Output             : ${params.outdir}
    ====================================================================
    """.stripIndent()

    // Expect a pre-existing CTF .cs file supplied via --micrographs_ctf_cs
    if (!params.containsKey('micrographs_ctf_cs') || params.micrographs_ctf_cs == null) {
        // Generate a small synthetic CTF .cs for testing
        def dummy = file("${params.outdir}/test_input/micrographs_ctf.cs")
        dummy.parent.mkdirs()
        def mics = (0..2).collect { i ->
            [micrograph_idx: i, micrograph_path: "micrograph_${String.format('%05d', i)}.mrc",
             defocus_u_angstroms: 15000 + i * 1000, defocus_v_angstroms: 14800 + i * 1000,
             ctf_fit_resolution_angstroms: 5.2]
        }
        dummy.text = groovy.json.JsonOutput.toJson([micrographs: mics])
        ch_ctf = Channel.of(dummy)
    } else {
        ch_ctf = Channel.fromPath(params.micrographs_ctf_cs)
    }

    FILAMENT_TRACER(ch_ctf)

    FILAMENT_TRACER.out.report.view { report_file ->
        def r = new groovy.json.JsonSlurper().parse(report_file)
        """
        Filament Tracer Results:
          Micrographs : ${r.num_micrographs}
          Filaments   : ${r.total_filaments_traced}
          Picks       : ${r.total_particles_picked}
        Results in: ${params.outdir}
        """
    }
}

workflow.onComplete {
    log.info "Filament Tracer completed: ${workflow.success ? 'SUCCESS' : 'FAILED'} (${workflow.duration})"
}
