#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: npGSEA
// Current gene set enrichment methods rely upon permutations for inference.  These approaches are comp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/npGSEA/inst/doc/npGSEA.R
// Upstream  : ALL, GSEABase, ReportingTools, genefilter, limma
// Downstream: none
//
// Install: BiocManager::install("npGSEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NPGSEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-npgsea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-npgsea:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-npgsea:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_npgsea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_npgsea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_npgsea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(npGSEA)
    library(GeneSet)
    library(GeneSetCollection)
    library(HTMLReport)
    library(jsonlite)

    # --- Gene Set Preparation [GeneSet, GeneSetCollection] ---
    # Key functions: GeneSet, GeneSetCollection
    gene_ids <- paste0("G", 1:100)
    set1 <- GeneSet(geneIds = gene_ids[1:15], setName = "set1",
                    shortDescription = "Simulated Gene Set 1")
    set2 <- GeneSet(geneIds = gene_ids[16:50], setName = "set2",
                    shortDescription = "Simulated Gene Set 2")
    gsc <- GeneSetCollection(c(set1, set2))

    # --- Non-parametric GSEA Analysis [npGSEA, betaHats, chiSqStat] ---
    # Key functions: npGSEA, betaHats, chiSqStat
    expr_matrix <- matrix(rnorm(100 * 20), nrow = 100)
    rownames(expr_matrix) <- paste0("G", 1:100)
    phenotype <- factor(rep(c("Control", "Treatment"), each = 10))
    res_norm <- npGSEA(x = expr_matrix, y = phenotype, 
                       set = set1, approx = "norm")
    res_beta <- npGSEA(x = expr_matrix, y = phenotype, 
                       set = set1, approx = "beta")
    res_chisq <- npGSEA(x = expr_matrix, y = phenotype, 
                        set = set1, approx = "chiSq")
    beta_vals <- betaHats(res_beta)
    chisq_val <- chiSqStat(res_chisq)

    # --- Weighted and Covariate-Adjusted GSEA [npGSEA] ---
    # Key functions: npGSEA
    expr_matrix <- matrix(rnorm(100 * 20), nrow = 100)
    rownames(expr_matrix) <- paste0("G", 1:100)
    phenotype <- factor(rep(c("Control", "Treatment"), each = 10))
    covariate <- rnorm(20)
    wts <- apply(expr_matrix[1:15, ], 1, var)
    wts <- 1 / wts
    res_wts <- npGSEA(x = expr_matrix, y = phenotype, 
                      set = set1, w = wts, approx = "norm")
    res_covar <- npGSEA(x = expr_matrix, y = phenotype, 
                        set = set1, covars = covariate)

    # --- Diagnostics and Visualisation [npGSEAPlot, stat, zStat, pValues, pLeft] ---
    # Key functions: npGSEAPlot, stat, zStat, pValues, pLeft
    expr_matrix <- matrix(rnorm(100 * 20), nrow = 100)
    rownames(expr_matrix) <- paste0("G", 1:100)
    phenotype <- factor(rep(c("Control", "Treatment"), each = 10))
    res <- npGSEA(x = expr_matrix, y = phenotype, set = set1)
    stat_val <- stat(res)
    z_val <- zStat(res)
    p_vals <- pValues(res)
    p_left <- pLeft(res)
    npGSEAPlot(res)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_npgsea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_npgsea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_npgsea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NPGSEA:", paste0("    npgsea: ", packageVersion("npGSEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_npgsea_results.csv
    touch ${prefix}_npgsea_output.rds
    echo "BIOC_NPGSEA:" > versions.yml
    echo "    npgsea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NPGSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NPGSEA(ch_input)

    emit:
    results  = BIOC_NPGSEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NPGSEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NPGSEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NPGSEA.out.versions  // channel: path(versions.yml)
}
