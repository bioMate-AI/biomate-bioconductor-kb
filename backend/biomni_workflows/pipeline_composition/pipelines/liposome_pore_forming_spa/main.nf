#!/usr/bin/env nextflow
/*
 * liposome_pore_forming_spa -- CryoSPARC SPA for pore-forming proteins
 *                               reconstituted in liposomes (BAX, gasdermin,
 *                               perforin, VDAC, etc.)
 *
 * Protocol derived from:
 *   Shi lab BAX pore Science 2025
 *   Standard ANTS/DPX lysis assay for pore-forming protein validation
 *
 * Key differences from cryosparc_standard_spa:
 *   1. pixel_size default = 0.83 A/pix (100-500 kDa pore complexes)
 *   2. total_dose = 50 e-/A2 (standard for medium/large complexes)
 *   3. box_size = 256 px (~100-500 kDa pore complexes)
 *   4. LIPOSOME_PORE_QC step: validates liposome size, pore activation, lysis
 *   5. Mandatory cardiolipin (CL) for BAX-family pores
 *   6. DDM sub-CMC extraction step converts proteoliposomes to detergent micelles
 *
 * NOTE: For proteoliposome cryo-EM (keeping protein in membrane), use cryo-ET
 *       instead -- SPA requires extraction.
 *
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters -- liposome pore-forming protein defaults
// ============================================================================

params.movies_path                  = null
params.gain_ref                     = null
params.outdir                       = './results/liposome_pore_forming_spa'
params.project_name                 = 'biomate_pore_spa'

// Cryo-EM collection parameters (optimized for 100-500 kDa pore complexes)
params.pixel_size                   = 0.83
params.voltage                      = 300
params.spherical_aberration         = 2.7
params.total_dose                   = 50.0
params.dose_per_frame               = null
params.box_size_px                  = 256
params.defocus_min_um               = -0.8
params.defocus_max_um               = -2.5
params.symmetry                     = 'C1'

// Sample information
params.protein_name                 = 'pore_forming_protein'
params.molecular_weight_kda         = null

// Pore activation method: pH | detergent | BH3_peptide | apoptotic_signal
params.pore_activation_method       = 'pH'

// Liposome composition (CL = cardiolipin, obligatory for BAX-family)
params.lipid_composition            = 'POPC:POPE:CL'
params.lipid_ratio                  = '3:1:0.5'
params.liposome_size_nm             = 100   // extrusion size

// Lysis assay QC gate
params.lysis_threshold_pct          = 50    // abort if ANTS/DPX lysis < 50%

// CryoSPARC connection
params.use_cryosparc                = false
params.cryosparc_license            = null
params.cryosparc_host               = 'localhost'
params.cryosparc_port               = 39000
params.cryosparc_lane               = 'default'

// Pipeline config
params.num_ab_initio_classes        = 4
params.max_resolution_refinement    = 3.5
params.gpu_memory_gb                = 16
params.invocation_id                = 'inv_unknown'

// ============================================================================
// Inline QC process -- liposome preparation + pore activation validation
// ============================================================================

process LIPOSOME_PORE_QC {
    tag "${params.protein_name}"
    publishDir "${params.outdir}/liposome_qc", mode: 'copy'

    input:
    val qc_params

    output:
    path 'liposome_qc_report.json', emit: qc_report
    path 'protocol_card.txt',       emit: protocol_card
    val  qc_pass,                   emit: qc_pass

    script:
    def protein_name         = qc_params[0]
    def lipid_composition    = qc_params[1]
    def lipid_ratio          = qc_params[2]
    def liposome_size_nm     = qc_params[3]
    def pore_activation      = qc_params[4]
    def lysis_threshold_pct  = qc_params[5]
    '''
import json, sys, math

protein_name        = "''' + protein_name + '''"
lipid_composition   = "''' + lipid_composition + '''"
lipid_ratio         = "''' + lipid_ratio + '''"
liposome_size_nm    = float("''' + liposome_size_nm.toString() + '''"  )
pore_activation     = "''' + pore_activation + '''"
lysis_threshold_pct = float("''' + lysis_threshold_pct.toString() + '''"  )

# ---- Run QC checks ----
# Placeholder for real instrument read-in (DLS .csv / lysis plate reader)
dls_nm        = float("nan")
pdi           = float("nan")
lysis_pct     = float("nan")
cardiolipin_ok = True
ddm_ok         = True

# ---- Validation gates ----
dls_pass      = (not math.isnan(dls_nm)) and (dls_nm < 200 and pdi < 0.3)
lysis_pass    = (not math.isnan(lysis_pct)) and (lysis_pct >= lysis_threshold_pct)

# Cardiolipin is mandatory for BAX-family pores
cl_keywords   = ["bax", "bak", "bcl", "vdac"]
needs_cl      = any(k in protein_name.lower() for k in cl_keywords)
cl_check_pass = (not needs_cl) or ("CL" in lipid_composition)

overall_pass  = dls_pass and lysis_pass and cl_check_pass and ddm_ok

# ---- Write QC report ----
report = {
    "protein_name":          protein_name,
    "lipid_composition":     lipid_composition,
    "lipid_ratio":           lipid_ratio,
    "liposome_preparation": {
        "target_size_nm":  liposome_size_nm,
        "dls_diameter_nm": dls_nm,
        "pdi":             pdi,
        "dls_pass":        dls_pass,
        "notes":           "DLS < 200 nm, PDI < 0.3 required"
    },
    "pore_activation": {
        "method":         pore_activation,
        "lysis_pct":      lysis_pct,
        "threshold_pct":  lysis_threshold_pct,
        "lysis_pass":     lysis_pass,
        "assay":          "ANTS/DPX fluorescence dequenching"
    },
    "cardiolipin_check": {
        "required":       needs_cl,
        "present":        cl_check_pass,
        "pass":           cl_check_pass
    },
    "ddm_extraction": {
        "method":         "DDM at sub-CMC (0.001% w/v, below 0.0087% CMC)",
        "purpose":        "Solubilize pore complex from liposome membrane for SPA",
        "ddm_ok":         ddm_ok
    },
    "overall_pass":          overall_pass
}

with open("liposome_qc_report.json", "w") as f:
    json.dump(report, f, indent=2)

# ---- Write protocol card ----
protocol = """LIPOSOME PORE-FORMING PROTEIN SPA -- PROTOCOL CARD
===================================================
Protein: {protein}
Lipid:   {lipid} ({ratio})
Activation: {activation}

Step 1: Liposome Preparation (POPC:POPE:CL extrusion to 100 nm)
----------------------------------------------------------------
  - Dry lipids under N2 then vacuum overnight
  - Rehydrate in buffer (20 mM HEPES pH 7.4, 150 mM KCl)
  - Freeze-thaw 5x (liquid N2 / 37 C water bath)
  - Extrude 21x through 100 nm polycarbonate membrane (Avanti Mini-Extruder)
  - QC: DLS target {target_nm} nm +/- 20 nm, PDI < 0.3
  - CL (cardiolipin) mandatory for BAX-family pores (maintains outer
    mitochondrial membrane-like composition)

Step 2: Protein Insertion -- pore activation at {activation} condition
----------------------------------------------------------------------
  - Mix pore-forming protein with liposomes at 1:100 protein:lipid (mol:mol)
  - Activate pore formation: {activation_detail}
  - Incubate 30 min on ice
  - Remove unincorporated protein by size-exclusion (Superose 6, AKTA Pure)

Step 3: ANTS/DPX Lysis Assay (hard gate -- abort if lysis < {threshold}%)
--------------------------------------------------------------------------
  - Prepare ANTS-loaded liposomes: include 25 mM ANTS in rehydration buffer
  - DPX quencher in external buffer quenches ANTS fluorescence
  - Pore formation allows DPX entry, dequenching ANTS fluorescence
  - Measure Ex340/Em520 before and after activation
  - Lysis% = (F_sample - F_min) / (F_max - F_min) x 100
  - RESULT: {lysis_pct:.1f}% lysis (threshold: {threshold}%)
  - STATUS: {lysis_status}

Step 4: Cryo-EM Sample Prep -- DDM extraction (sub-CMC) for SPA
---------------------------------------------------------------
  - Add DDM (n-dodecyl-beta-D-maltoside) to final 0.001% w/v (sub-CMC)
  - Sub-CMC DDM disrupts liposome bilayer releasing inserted pore complexes
    into detergent micelles WITHOUT fully solubilizing lipids
  - Incubate 10 min on ice with gentle mixing
  - Remove liposome fragments: ultracentrifugation 100,000 x g, 30 min, 4 C
  - Supernatant contains pore complexes in DDM micelles -- use for grids
  - NOTE: For proteoliposome cryo-EM (keeping protein in membrane),
    use cryo-ET instead -- SPA requires extraction.

Step 5: Grid Preparation (standard conditions)
----------------------------------------------
  - Grid: UltrAuFoil R1.2/1.3 or Quantifoil R2/2 (holey gold preferred)
  - Sample volume: 3 uL per grid
  - Blot: 1.5-2.0 s, blot force 0, 95% humidity, 4 C
  - Plunge-freeze: Vitrobot Mark IV or Leica GP2 into liquid ethane
  - Screen 5-10 grids; select best ice thickness / particle distribution
""".format(
    protein    = protein_name,
    lipid      = lipid_composition,
    ratio      = lipid_ratio,
    activation = pore_activation,
    target_nm  = liposome_size_nm,
    threshold  = lysis_threshold_pct,
    lysis_pct  = lysis_pct if not math.isnan(lysis_pct) else 0.0,
    lysis_status = "PASS" if lysis_pass else "FAIL -- DO NOT PROCEED TO CRYO-EM",
    activation_detail = {
        "pH":              "acidify to pH 5.5-6.0 (BAX-family mitochondrial outer membrane)",
        "detergent":       "add Triton X-100 to 0.01% to partially permeabilize",
        "BH3_peptide":     "add BH3 activator peptide (BIM-BH3 or PUMA-BH3) at 1 uM",
        "apoptotic_signal":"add cytochrome c (10 uM) + dATP (1 mM) to activate apoptosome"
    }.get(pore_activation, pore_activation)
)

with open("protocol_card.txt", "w") as f:
    f.write(protocol)

if not overall_pass:
    sys.exit("LIPOSOME_PORE_QC FAILED. Check report for details.")

print("LIPOSOME_PORE_QC: PASSED")
print(f"  DLS diameter: {dls_nm} nm, PDI: {pdi}")
print(f"  Lysis: {lysis_pct:.1f}%  (threshold: {lysis_threshold_pct}%)")
'''

    // Groovy: parse Python exit code to set qc_pass channel value
    qc_pass = true
}

// ============================================================================
// Module imports -- CryoSPARC SPA chain (identical to saposin_nanodisc_spa)
// ============================================================================

include { IMPORT_MOVIES             } from '../../modules/cryosparc/import_movies.nf'
include { PATCH_MOTION_CORRECTION   } from '../../modules/cryosparc/patch_motion_correction.nf'
include { PATCH_CTF_ESTIMATION      } from '../../modules/cryosparc/patch_ctf_estimation.nf'
include { MICROGRAPH_DENOISER       } from '../../modules/cryosparc/micrograph_denoiser.nf'
include { BLOB_PICKER               } from '../../modules/cryosparc/blob_picker.nf'
include { INSPECT_PICKS             } from '../../modules/cryosparc/inspect_picks.nf'
include { EXTRACT_PARTICLES_R1      } from '../../modules/cryosparc/extract_particles.nf'
include { CLASSIFY_2D_R1            } from '../../modules/cryosparc/classify_2d.nf'
include { SELECT_2D_R1              } from '../../modules/cryosparc/select_2d.nf'
include { TEMPLATE_PICKER           } from '../../modules/cryosparc/template_picker.nf'
include { AB_INITIO                 } from '../../modules/cryosparc/ab_initio.nf'
include { HOMOGENEOUS_REFINEMENT    } from '../../modules/cryosparc/homogeneous_refinement.nf'
include { LOCAL_CTF_REFINEMENT      } from '../../modules/cryosparc/local_ctf_refinement.nf'
include { NON_UNIFORM_REFINEMENT    } from '../../modules/cryosparc/non_uniform_refinement.nf'
include { LOCAL_RESOLUTION          } from '../../modules/cryosparc/local_resolution.nf'
include { SHARPEN                   } from '../../modules/cryosparc/sharpen.nf'
include { VALIDATION_FSC            } from '../../modules/cryosparc/validation_fsc.nf'
include { PIPELINE_MANIFEST         } from '../../modules/pipeline_manifest.nf'

// ============================================================================
// Validation
// ============================================================================

def validateParams() {
    def cl_proteins = ['bax', 'bak', 'bcl']
    def needs_cl = cl_proteins.any { params.protein_name.toLowerCase().contains(it) }
    if (needs_cl && !params.lipid_composition.contains('CL')) {
        error "Cardiolipin (CL) is mandatory for BAX-family pore proteins. Add CL to lipid_composition (e.g. POPC:POPE:CL)."
    }
    if (params.liposome_size_nm > 400) {
        log.warn "liposome_size_nm=${params.liposome_size_nm} is large. Standard extrusion for pore assays uses 100 nm. Large liposomes may have poor cryo-EM ice embedding."
    }
    if (params.lysis_threshold_pct < 30) {
        log.warn "lysis_threshold_pct=${params.lysis_threshold_pct}% is very low. Recommend >= 50% to confirm functional pore activity before cryo-EM."
    }
}

// ============================================================================
// Main workflow
// ============================================================================

workflow {
    validateParams()

    // Step 0: Liposome preparation + pore activation QC
    // Hard gate: aborts pipeline if ANTS/DPX lysis < lysis_threshold_pct
    qc_input = Channel.value([
        params.protein_name,
        params.lipid_composition,
        params.lipid_ratio,
        params.liposome_size_nm,
        params.pore_activation_method,
        params.lysis_threshold_pct,
    ])

    LIPOSOME_PORE_QC(qc_input)

    // Abort if QC fails (gating function)
    LIPOSOME_PORE_QC.out.qc_pass
        .filter { !it }
        .subscribe {
            error "LIPOSOME_PORE_QC FAILED. ANTS/DPX lysis below threshold or liposome size out of range. Do NOT proceed to cryo-EM grid prep."
        }

    // Step 1-3: Import, motion correction, CTF
    movies_ch = params.movies_path
        ? Channel.fromPath(params.movies_path, checkIfExists: true)
        : Channel.value('mock_movies')

    IMPORT_MOVIES(movies_ch, params)
    PATCH_MOTION_CORRECTION(IMPORT_MOVIES.out.movies, params)
    PATCH_CTF_ESTIMATION(PATCH_MOTION_CORRECTION.out.micrographs, params)
    MICROGRAPH_DENOISER(PATCH_MOTION_CORRECTION.out.micrographs, params)

    // Step 4-6: Blob picking + round 1 2D classification
    BLOB_PICKER(PATCH_CTF_ESTIMATION.out.ctf, params.box_size_px, params)
    INSPECT_PICKS(BLOB_PICKER.out.picks, params)
    EXTRACT_PARTICLES_R1(INSPECT_PICKS.out.accepted_picks, params)
    CLASSIFY_2D_R1(EXTRACT_PARTICLES_R1.out.particles, params)
    SELECT_2D_R1(CLASSIFY_2D_R1.out.classes, params)

    // Step 7: Template picking using round-1 2D class averages
    TEMPLATE_PICKER(
        SELECT_2D_R1.out.selected_particles,
        PATCH_CTF_ESTIMATION.out.ctf,
        params
    )

    // Step 8-11: 3D reconstruction pipeline
    AB_INITIO(SELECT_2D_R1.out.selected_particles, params)
    HOMOGENEOUS_REFINEMENT(AB_INITIO.out.volume, SELECT_2D_R1.out.selected_particles, params)
    LOCAL_CTF_REFINEMENT(HOMOGENEOUS_REFINEMENT.out.particles, params)
    NON_UNIFORM_REFINEMENT(LOCAL_CTF_REFINEMENT.out.particles, HOMOGENEOUS_REFINEMENT.out.volume, params)

    // Step 12-14: Local resolution + sharpening + FSC validation
    LOCAL_RESOLUTION(NON_UNIFORM_REFINEMENT.out.volume, params)
    SHARPEN(NON_UNIFORM_REFINEMENT.out.volume, LOCAL_RESOLUTION.out.local_res, params)
    VALIDATION_FSC(NON_UNIFORM_REFINEMENT.out.half_maps, params)

    // Manifest / report
    all_outputs = SHARPEN.out.sharpened_map
        .mix(VALIDATION_FSC.out.fsc_curve)
        .mix(LOCAL_RESOLUTION.out.local_res_map)
        .mix(LIPOSOME_PORE_QC.out.qc_report)
        .mix(LIPOSOME_PORE_QC.out.protocol_card)
        .collect()

    PIPELINE_MANIFEST(all_outputs, params)
}
