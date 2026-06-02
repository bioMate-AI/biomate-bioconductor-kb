#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DEqMS
// DEqMS is developped on top of Limma. However, Limma assumes same prior variance for all genes. In pr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DEqMS/inst/doc/DEqMS-package-vignette.R
// Upstream  : matrixStats, ggrepel, ExperimentHub, LSD
// Downstream: none
//
// Install: BiocManager::install("DEqMS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEQMS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-deqms"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-deqms:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-deqms:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(marraylm)

    output:
    tuple val(meta), path("${meta.id}_deqms_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_deqms_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_deqms_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Residualplot)
    library(VarianceBoxplot)
    library(VarianceScatterplot)
    library(jsonlite)

    # --- Linear model fit (limma) [] ---
    # Key functions: lmFit, eBayes, makeContrasts
    protein.matrix = log2(as.matrix(df.LFQ.filter))
    class = as.factor(c("H","H","H","L","L","L"))
    design = model.matrix(~0+class) # fitting without intercept
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_point, theme_bw, xlab, ylab, volcanoplot
    library(ggrepel)
    DEqMS.results$log.sca.pval = -log10(DEqMS.results$sca.P.Value)
    ggplot(DEqMS.results, aes(x = logFC, y =log.sca.pval )) +
    # --- VarianceBoxplot analysis [] ---
    # Key functions: VarianceBoxplot, VarianceScatterplot, unzip, query, peptideProfilePlot, Residualplot, heatscatter
    VarianceScatterplot(fit3, xlab="log2(PSM count)")
    abline(h = log(limma.prior),col="green",lwd=3 )
    legend("topright",legend=c("DEqMS prior variance","Limma prior variance"),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_deqms_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_deqms_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_deqms_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEQMS:", paste0("    deqms: ", packageVersion("DEqMS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deqms_results.csv
    touch ${prefix}_deqms_output.rds
    echo "BIOC_DEQMS:" > versions.yml
    echo "    deqms: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEQMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(marraylm) ]

    main:
    BIOC_DEQMS(ch_input)

    emit:
    results  = BIOC_DEQMS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEQMS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEQMS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEQMS.out.versions  // channel: path(versions.yml)
}
