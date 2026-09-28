#!/usr/bin/env nextflow
/*
 * single_cell/visium_voyager_spatial_esda
 *
 * Self-contained 10X Visium spatial ESDA (Exploratory Spatial Data Analysis)
 * on a SpatialFeatureExperiment (SFE) with the Voyager package.
 *
 * This is the MINIMAL-CORRECT runnable implementation. The prior version chained
 * an upstream nf-core/spatialvi Space Ranger run + a suite of bespoke
 * /opt/biomate/voyager/*.R scripts that were never implemented and required
 * Space Ranger output dirs that BioMate does not stage. It could never run.
 *
 * This version runs a single self-contained R process (esda_run.R, baked into
 * the bioc-domain-spatial image) that:
 *   1. Loads a real 10X Visium SFE — either a built-in SFEData example
 *      (default: McKellarMuscleData, 10X Visium mouse skeletal muscle) or a
 *      user-supplied SFE .rds via --sfe_rds.
 *   2. Keeps in-tissue spots, log-normalizes counts, selects HVGs.
 *   3. Builds the Visium spatial neighborhood graph (findVisiumGraph).
 *   4. Computes univariate Moran's I (global spatial autocorrelation) for HVGs.
 *   5. Emits: SFE .rds, Moran's I table (CSV), per-spot QC table (CSV),
 *      and a Moran's-I bar plot + a spatial feature plot (PNG).
 *
 * Uses the Voyager / SpatialFeatureExperiment / SFEData / scater / scran stack
 * baked into bioc-domain-spatial:3.20-deps.
 *
 * References:
 *   - Moses & Pachter, Voyager, 2023 Nat Methods
 *   - Righelli et al. 2022 SpatialExperiment (Bioinformatics)
 *   - McKellar et al. 2021 (10X Visium mouse skeletal muscle regeneration)
 */

nextflow.enable.dsl = 2

params.outdir            = './results'
// SFEData example to load when no user SFE is supplied. Any function name in the
// SFEData package that returns a Visium SFE (e.g. McKellarMuscleData).
params.sfe_dataset       = 'McKellarMuscleData'
// Optional: path to a user-supplied SpatialFeatureExperiment .rds. Overrides sfe_dataset.
params.sfe_rds           = 'null'
params.min_counts_per_spot = '100'
params.n_hvgs            = '200'
params.max_spots         = '2000'   // subsample cap to bound runtime/cost
params.sample_id         = 'sample'
// container is injected by the BioMate executor as params.container (the ECR
// bioc-domain-spatial image). Fall back to a local dev tag otherwise.
params.container         = 'biomate/bioc-domain-spatial:3.20-deps'

process VISIUM_VOYAGER_SPATIAL_ESDA {
    tag "${params.sample_id}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container "${params.container}"

    output:
    path "sfe_esda.rds",          emit: sfe
    path "univariate_moran.csv",  emit: moran
    path "qc_metrics.csv",        emit: qc
    path "moran_top_genes.png",   emit: moran_plot
    path "spatial_feature.png",   emit: spatial_plot
    path "esda_summary.json",     emit: summary
    path "versions.yml",          emit: versions

    script:
    """
    Rscript /opt/biomate/voyager/esda_run.R \\
        --sfe_dataset ${params.sfe_dataset} \\
        --sfe_rds ${params.sfe_rds} \\
        --min_counts ${params.min_counts_per_spot} \\
        --n_hvgs ${params.n_hvgs} \\
        --max_spots ${params.max_spots} \\
        --sample_id ${params.sample_id}

    cat <<EOF > versions.yml
    "${task.process}":
        Voyager: \$(Rscript -e "cat(as.character(packageVersion('Voyager')))")
        SpatialFeatureExperiment: \$(Rscript -e "cat(as.character(packageVersion('SpatialFeatureExperiment')))")
        SFEData: \$(Rscript -e "cat(as.character(packageVersion('SFEData')))")
    EOF
    """
}

workflow VISIUM_VOYAGER_SPATIAL_ESDA_WORKFLOW {
    main:
    VISIUM_VOYAGER_SPATIAL_ESDA()

    emit:
    sfe           = VISIUM_VOYAGER_SPATIAL_ESDA.out.sfe
    moran         = VISIUM_VOYAGER_SPATIAL_ESDA.out.moran
    qc            = VISIUM_VOYAGER_SPATIAL_ESDA.out.qc
    moran_plot    = VISIUM_VOYAGER_SPATIAL_ESDA.out.moran_plot
    spatial_plot  = VISIUM_VOYAGER_SPATIAL_ESDA.out.spatial_plot
    summary       = VISIUM_VOYAGER_SPATIAL_ESDA.out.summary
    versions      = VISIUM_VOYAGER_SPATIAL_ESDA.out.versions
}

workflow {
    VISIUM_VOYAGER_SPATIAL_ESDA_WORKFLOW()
}
