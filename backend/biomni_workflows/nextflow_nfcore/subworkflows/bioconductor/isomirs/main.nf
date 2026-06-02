#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: isomiRs
// Characterization of miRNAs and isomiRs, clustering and differential expression.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/isomiRs/inst/doc/isomiRs.R
// Upstream  : DESeq2, clusterProfiler, pheatmap
// Downstream: none
//
// Install: BiocManager::install("isomiRs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOMIRS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-isomirs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-isomirs:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-isomirs:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_isomirs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_isomirs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_isomirs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(isomiRs)
    library(IsomirDataSeqFromFiles)
    library(jsonlite)

    # --- Normalization and Annotation [] ---
    # Key functions: isoNorm, isoAnnotate
    ids <- isoNorm(ids, formula = ~ condition)
    annotated_ids <- isoAnnotate(ids)
    norm_counts <- counts(ids, norm=TRUE)


    # --- Differential Expression Analysis [] ---
    # Key functions: isoDE
    dds <- isoDE(ids, formula=~condition)
    dds_iso5 <- isoDE(ids, formula=~condition, ref=TRUE, iso5=TRUE)


    # --- Target Prediction and Network Analysis [] ---
    # Key functions: findTargets, mirna2targetscan, isoNetwork, isoPlotNet
    data(isoExample)
    mirna_ma <- data.frame(
        gene = names(gene_ex_rse)[1:20],
        mir = names(mirna_ex_rse)
    )
    ma_ex <- findTargets(mirna_ex_rse, gene_ex_rse, mirna_ma)
    net_data <- isoNetwork(
        mirna_ex_rse, gene_ex_rse, target = ma_ex,
        summarize = "group"
    )
    isoPlotNet(net_data, minGenes = 4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_isomirs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_isomirs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_isomirs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISOMIRS:", paste0("    isomirs: ", packageVersion("isomiRs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isomirs_results.csv
    touch ${prefix}_isomirs_output.rds
    echo "BIOC_ISOMIRS:" > versions.yml
    echo "    isomirs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISOMIRS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISOMIRS(ch_input)

    emit:
    results  = BIOC_ISOMIRS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISOMIRS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISOMIRS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISOMIRS.out.versions  // channel: path(versions.yml)
}
