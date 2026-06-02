#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ffpe
// Identify low-quality data using metrics developed for expression data derived from Formalin-Fixed, P
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ffpe/inst/doc/ffpe.R
// Upstream  : ffpeExampleData, genefilter
// Downstream: none
//
// Install: BiocManager::install("ffpe")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FFPE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ffpe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ffpe:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ffpe:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ffpe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ffpe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ffpe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ffpe)
    library(CATplot)
    library(jsonlite)

    # --- Sample Filtering [] ---
    # Key functions: sampleQC
    data(lumibatch.GSE17565, package = "ffpeExampleData")
    QC <- sampleQC(
        lumibatch.GSE17565, 
        xaxis = "index", 
        cor.to = "pseudochip", 
        QCmeasure = "IQR"
    )
    lumibatch.QC <- lumibatch.GSE17565[, !QC$rejectQC]


    # --- Concordance Analysis [] ---
    # Key functions: CATplot
    pvals.rep1 <- runif(1000, 0, 1)
    pvals.rep2 <- runif(1000, 0, 1)
    names(pvals.rep1) <- paste0("gene", 1:1000)
    names(pvals.rep2) <- paste0("gene", 1:1000)
    x <- CATplot(
        pvals.rep1, 
        pvals.rep2, 
        maxrank = 1000, 
        xlab = "Size of top-ranked gene lists", 
        ylab = "Concordance"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ffpe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ffpe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ffpe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FFPE:", paste0("    ffpe: ", packageVersion("ffpe"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ffpe_results.csv
    touch ${prefix}_ffpe_output.rds
    echo "BIOC_FFPE:" > versions.yml
    echo "    ffpe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FFPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FFPE(ch_input)

    emit:
    results  = BIOC_FFPE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FFPE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FFPE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FFPE.out.versions  // channel: path(versions.yml)
}
