#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ASSET
// An R package for subset-based analysis of heterogeneous traits and disease subtypes. The package all
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ASSET/inst/doc/vignette.R
// Upstream  : none
// Downstream: REBET
//
// Install: BiocManager::install("ASSET")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASSET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-asset"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-asset:2.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-asset:2.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_asset_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_asset_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_asset_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ASSET)
    library(jsonlite)

    # --- Restricted Subset Association Analysis [] ---
    # Key functions: h.traits, h.summary
    sub.def <- function(logicalVec) {
        sum_val <- sum(logicalVec)
        ret <- all(logicalVec[1:sum_val])
        ret
    }
    res_restricted <- h.traits(SNPs, studies, beta, sigma, case,
                               control, meta=TRUE,
                               zmax.args=list(sub.def=sub.def),
                               pval.args=list(sub.def=sub.def))
    h_sum_rest <- h.summary(res_restricted)


    # --- Disease Subtype Association Analysis [] ---
    # Key functions: h.types, h.summary
    datafile <- system.file("sampleData", "vdata.rda", package="ASSET")
    load(datafile)
    data_all <- rbind(data1, data2, data3, data4)
    data_all$STUDY <- rep(1:4, each=nrow(data1))
    for (i in 1:4) {
        data_all[, paste0("STUDY_", i)] <- as.numeric(data_all$STUDY == i)
    }
    snp.vars <- paste0("SNP", 1:3)
    adj.vars <- c("AGE", "STUDY_1", "STUDY_2", "STUDY_3")
    types.lab <- paste0("TYPE_", 1:3)
    ret_types <- h.types(data_all, "TYPE", snp.vars, adj.vars,
                         types.lab, "CONTROL", logit=TRUE)
    h_sum_types <- h.summary(ret_types)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_asset_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_asset_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_asset_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ASSET:", paste0("    asset: ", packageVersion("ASSET"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_asset_results.csv
    touch ${prefix}_asset_output.rds
    echo "BIOC_ASSET:" > versions.yml
    echo "    asset: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ASSET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ASSET(ch_input)

    emit:
    results  = BIOC_ASSET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ASSET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ASSET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ASSET.out.versions  // channel: path(versions.yml)
}
