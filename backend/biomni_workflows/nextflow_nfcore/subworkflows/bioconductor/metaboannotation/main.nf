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
    library(CompareSpectraParam)
    library(Mass2MzParam)
    library(Mass2MzRtParam)
    library(MatchForwardReverseParam)
    library(MsBackendMemory)
    library(MzRtParam)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Mass2 Mz Param [] ---
    # Key functions: Mass2MzParam, matchValues
    ---------------------------------------------------------------------
    parm <- Mass2MzParam(adducts = c("[M+H]+", "[M+Na]+"),
                               tolerance = 0.005, ppm = 0)
    matched_features <- matchValues(ms1_features[1:100, ], target_df, parm)
    matched_features
    # --- Head [] ---
    # Key functions: query, target
    ---------------------------------------------------------------------
    head(query(matched_features))
    head(target(matched_features))
    # --- Whichquery [] ---
    # Key functions: whichQuery, whichTarget
    ---------------------------------------------------------------------
    whichQuery(matched_features)
    whichTarget(matched_features)
    # --- Matcheddata [] ---
    # Key functions: matchedData
    ---------------------------------------------------------------------
    matchedData(matched_features)
    # --- Mass2 Mz Rt Param [] ---
    # Key functions: Mass2MzRtParam, matchValues
    ---------------------------------------------------------------------
    parm <- Mass2MzRtParam(adducts = c("[M+H]+", "[M+Na]+"),
                           tolerance = 0.005, ppm = 0,
                           toleranceRt = 10)
    # --- Matcheddata [] ---
    # Key functions: matchedData, whichQuery
    ---------------------------------------------------------------------
    matchedData(matched_features)[whichQuery(matched_features), ]
    # --- Prepare_Feature_Data_Container [] ---
    # Key functions: SummarizedExperiment, rnorm
    ---------------------------------------------------------------------
    library(SummarizedExperiment)
    # --- Mass2 Mz Param [] ---
    # Key functions: Mass2MzParam, matchValues
    ---------------------------------------------------------------------
    parm <- Mass2MzParam(adducts = c("[M+H]+", "[M+Na]+"),
                         tolerance = 0.005, ppm = 0)
    matched_features <- matchValues(se, target_df, param = parm)
    matched_features
    # --- Colnames [] ---
    # Key functions: matchedData
    ---------------------------------------------------------------------
    colnames(matched_features)
    matchedData(matched_features)
    # --- Whichquery [] ---
    # Key functions: whichQuery, query
    ---------------------------------------------------------------------
    matched_sub <- matched_features[whichQuery(matched_features)]
    MetaboAnnotation::query(matched_sub)
    # --- Match_Features_To_Reference_Database [] ---
    # Key functions: matchValues
    ---------------------------------------------------------------------
    matched_qf <- matchValues(qf, target_df, param = parm, queryAssay = "features")
    matched_qf
    # --- Colnames [] ---
    # Key functions: matchedData
    ---------------------------------------------------------------------
    colnames(matched_qf)
    matchedData(matched_qf)
    # --- Comparespectraparam [] ---
    # Key functions: CompareSpectraParam, matchSpectra
    ---------------------------------------------------------------------
    csp <- CompareSpectraParam(requirePrecursor = TRUE, ppm = 10)
    mtches <- matchSpectra(pest_ms2, minimb, param = csp)
    mtches
    # --- Spectravariables [] ---
    # Key functions: spectraVariables
    ---------------------------------------------------------------------
    spectraVariables(mtches)
    # --- Query [] ---
    # Key functions: query
    ---------------------------------------------------------------------
    query(mtches)$.original_query_index

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
