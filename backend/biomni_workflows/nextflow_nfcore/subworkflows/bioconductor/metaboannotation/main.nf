#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MetaboAnnotation
// High level functions to assist in annotation of (metabolomics) data sets. These include functions to
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MetaboAnnotation/inst/doc/MetaboAnnotation.R
// Upstream  : AnnotationHub, QFeatures, Spectra, SummarizedExperiment, microbenchmark
// Downstream: none
//
// Install: BiocManager::install("MetaboAnnotation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METABOANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metaboannotation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metaboannotation:1.10.1--r44_0' :
        'quay.io/biocontainers/bioconductor-metaboannotation:1.10.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metaboannotation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metaboannotation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metaboannotation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MetaboAnnotation)
    library(CompareSpectraParam)
    library(Mass2MzParam)
    library(Mass2MzRtParam)
    library(MatchForwardReverseParam)
    library(MsBackendMemory)
    library(MzRtParam)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- MS1 Feature Matching with Retention Time [] ---
    # Key functions: Mass2MzRtParam, matchValues, whichQuery, whichTarget
    ms1_subset <- data.frame(mz = c(120.08, 150.12), rtime = c(10, 20))
    target_df <- data.frame(exactmass = c(119.07, 149.11), rtime = c(12, 22))
    parm <- Mass2MzRtParam(adducts = c("[M+H]+", "[M+Na]+"),
                           tolerance = 0.005, ppm = 0,
                           toleranceRt = 10)
    matched_features <- matchValues(ms1_subset, target_df, param = parm,
                                    rtColname = "rtime")
    q_idx <- whichQuery(matched_features)
    t_idx <- whichTarget(matched_features)


    # --- MS2 Spectra Matching [] ---
    # Key functions: CompareSpectraParam, matchSpectra, spectraVariables, spectraData
    csp <- CompareSpectraParam(requirePrecursor = TRUE, ppm = 10)
    mtches <- matchSpectra(pest_ms2, minimb, param = csp)
    spec_vars <- spectraVariables(mtches)
    mtches_df <- spectraData(mtches,
                             columns = c("spectrum_id", "score",
                                         "target_compound_name"))


    # --- Visualisation and Processing of Matched Spectra [] ---
    # Key functions: addProcessing, plotSpectraMirror
    scale_int <- function(x, ...) {
        x[, "intensity"] <- x[, "intensity"] / max(x[, "intensity"],
                                                   na.rm = TRUE)
        x
    }
    mtches_scaled <- addProcessing(mtches, scale_int)
    plotSpectraMirror(mtches_scaled[2])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metaboannotation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metaboannotation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metaboannotation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METABOANNOTATION:", paste0("    metaboannotation: ", packageVersion("MetaboAnnotation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metaboannotation_results.csv
    touch ${prefix}_metaboannotation_output.rds
    echo "BIOC_METABOANNOTATION:" > versions.yml
    echo "    metaboannotation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METABOANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METABOANNOTATION(ch_input)

    emit:
    results  = BIOC_METABOANNOTATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METABOANNOTATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METABOANNOTATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METABOANNOTATION.out.versions  // channel: path(versions.yml)
}
