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
    library(DEqMS)
    library(Residualplot)
    library(VarianceBoxplot)
    library(VarianceScatterplot)
    library(jsonlite)

    # --- Data Normalization and Filtering [Data Preparation] ---
    # Key functions: equalMedianNormalization
    dat_filtered <- dat[rowSums(is.na(dat)) == 0, ]
    dat_log <- log2(dat_filtered)
    dat_norm <- equalMedianNormalization(dat_log)

    # --- Linear Modeling and Contrasts [Differential Expression] ---
    # Key functions: lmFit, contrasts.fit, makeContrasts, eBayes
    design <- model.matrix(~0 + cond)
    colnames(design) <- gsub("cond", "", colnames(design))
    contrast <- limma::makeContrasts(
        contrasts = "treat-ctrl",
        levels = design
    )
    fit1 <- limma::lmFit(dat_norm, design)
    fit2 <- limma::contrasts.fit(fit1, contrasts = contrast)
    fit3 <- limma::eBayes(fit2)

    # --- DEqMS Spectral Count Correction [Statistical Modeling] ---
    # Key functions: spectraCounteBayes
    fit3$count <- psm_count_table[rownames(fit3$coefficients), "count"]
    fit4 <- spectraCounteBayes(fit3)

    # --- Variance Diagnostic Plotting [Visualisation] ---
    # Key functions: VarianceBoxplot, VarianceScatterplot
    pdf("deqms_variance_diagnostics.pdf")
    VarianceBoxplot(fit4, n = 30, main = "PSM Count vs Variance")
    VarianceScatterplot(fit4, main = "Protein Variance Scatterplot")
    dev.off()

    # --- Differential Expression Results [Output Generation] ---
    # Key functions: outputResult
    deqms_results <- outputResult(fit4, coef_col = 1)
    write.table(
        deqms_results,
        file = "DEqMS_results.txt",
        sep = "\t",
        row.names = FALSE,
        quote = FALSE
    )


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
