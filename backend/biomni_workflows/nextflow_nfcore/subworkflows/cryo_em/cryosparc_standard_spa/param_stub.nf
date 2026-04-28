// cryosparc_standard_spa — user-facing parameter stub
// Single Particle Analysis: movies → motion correction → CTF → picking → reconstruction

params.movies_path              = null      // Path to raw movie files (*.mrc, *.tif, *.eer)
params.gain_ref                 = null      // Gain reference file (optional)
params.micrograph_pixel_size    = null      // Pixel size in Å/pixel (e.g. 0.83 | 1.05 | 1.2)
params.accelerating_voltage     = 300       // kV: 300 | 200 | 120
params.spherical_aberration     = 2.7       // Cs in mm (2.7 for Titan Krios)
params.total_dose               = 50.0      // Total electron dose in e-/Å²
params.dose_per_frame           = null      // e-/Å²/frame (auto-calculated if null)
params.particle_diameter_angstroms = null   // Particle diameter in Å (null = auto-estimate)
params.symmetry                 = 'C1'      // Point group: C1 | C2 | C3 | D2 | O | T | I
params.defocus_min_um           = 1.0       // Minimum defocus for CTF search (µm)
params.defocus_max_um           = 3.0       // Maximum defocus for CTF search (µm)
params.phase_plate              = false     // true = Volta Phase Plate data
params.sample_type              = 'unknown' // membrane_protein | virus | ribosome | small_protein | unknown
params.num_ab_initio_classes    = 3         // Number of 3D classes for ab-initio
params.molecular_weight_kda     = null      // Used to estimate particle diameter
params.max_resolution_refinement = 2.5      // Target resolution in Å
params.outdir                   = './results'
params.email                    = null
params.max_memory               = '128.GB'
params.max_cpus                 = 16
params.max_time                 = '240.h'
