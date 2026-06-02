#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PhosR
// PhosR is a package for the comprenhensive analysis of phosphoproteomic data. There are two major com
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PhosR/inst/doc/PhosR.R
// Upstream  : ClueR, GGally, annotate, calibrate, directPA
// Downstream: none
//
// Install: BiocManager::install("PhosR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHOSR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phosr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phosr:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-phosr:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phosr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phosr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phosr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PhosR)
    library(GeneSymbol)
    library(Overrepresentation)
    library(PhosphoExperiment)
    library(RNGkind)
    library(RUVphospho)
    library(Residue)
    library(Sequence)
    library(Site)
    library(jsonlite)

    # --- Imputation of Missing Values [] ---
    # Key functions: scImpute, sc2Impute
    grps <- gsub("_[0-9]+", "", colnames(ppe_filtered))
    ppe_imputed <- scImpute(ppe_filtered, percent = 0.5, grps = grps)
    ppe_imputed <- sc2Impute(ppe_imputed, reg = 0.6)


    # --- Normalisation [] ---
    # Key functions: medianScaling, RUVphospho
    ppe_norm <- medianScaling(ppe_imputed)
    ctl <- seq_len(nrow(ppe_norm))
    ppe_normalized <- RUVphospho(
        ppe_norm,
        M = ppe_norm,
        k = 1,
        ctl = ctl
    )


    # --- Kinase Activity Profiling [] ---
    # Key functions: kinaseSubstrateScore, directSubstratePredict
    mat <- assay(ppe_normalized, "Quantification")
    scores <- kinaseSubstrateScore(mat, kinaseSubstrateRelation)
    predictions <- directSubstratePredict(mat, kinaseSubstrateRelation)


    # --- Clustering and Pathway Analysis [] ---
    # Key functions: clue, clueMember
    mat_clust <- assay(ppe_normalized, "Quantification")
    clue_res <- clue(mat_clust, cval = 5, repeatNum = 10)
    best_clust <- clueMember(clue_res)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phosr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phosr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phosr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHOSR:", paste0("    phosr: ", packageVersion("PhosR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phosr_results.csv
    touch ${prefix}_phosr_output.rds
    echo "BIOC_PHOSR:" > versions.yml
    echo "    phosr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHOSR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHOSR(ch_input)

    emit:
    results  = BIOC_PHOSR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHOSR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHOSR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHOSR.out.versions  // channel: path(versions.yml)
}
