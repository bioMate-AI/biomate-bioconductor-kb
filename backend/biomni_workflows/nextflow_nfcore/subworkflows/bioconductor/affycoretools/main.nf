#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: affycoretools
// Various wrapper functions that have been written to streamline the more common analyses that a core 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/affycoretools/inst/doc/RefactoredAffycoretools.R
// Upstream  : ReportingTools, knitr, limma
// Downstream: none
//
// Install: BiocManager::install("affycoretools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFYCORETOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-affycoretools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-affycoretools:1.78.0--r44_0' :
        'quay.io/biocontainers/bioconductor-affycoretools:1.78.0--r44_0'}"

    input:
    tuple val(meta), path(expressionset)

    output:
    tuple val(meta), path("${meta.id}_affycoretools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_affycoretools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_affycoretools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(affycoretools)
    library(HTMLReport)
    library(jsonlite)

    # --- Linear Modeling and Contrast Fit [] ---
    # Key functions: lmFit, contrasts.fit, eBayes
    pd <- pData(phenoData(eset))
    grps <- factor(apply(pd[, 1:2], 1, paste, collapse = "_"))
    design <- model.matrix(~0 + grps)
    colnames(design) <- gsub("grps", "", colnames(design))
    contrast <- matrix(c(1, -1, 0, 0, 0, 0, 1, -1, 1, -1, -1, 1), ncol = 3)
    colnames(contrast) <- c("Female_Case_vs_Control",
                            "Male_Case_vs_Control",
                            "Interaction")
    fit <- lmFit(eset, design)
    fit2 <- contrasts.fit(fit, contrast)
    fit2 <- eBayes(fit2)


    # --- Image Generation and HTML Reporting [] ---
    # Key functions: makeImages, entrezLinks, affyLinks
    d.f <- topTable(fit2, coef = 1, number = 10)
    out <- makeImages(df = d.f, eset = eset, grp.factor = grps,
                      design = design, contrast = contrast,
                      colind = 1, repdir = ".")
    htab <- HTMLReport("report_step", "Affycoretools Results")
    publish(out$df, htab, .modifyDF = list(entrezLinks, affyLinks))
    finish(htab)


    # --- Venn Diagram Generation [] ---
    # Key functions: makeVenn, vennInLine
    collist <- list(1:2)
    venn <- makeVenn(fit2, contrast, design, collist = collist,
                     adj.meth = "none")
    cap <- list(paste("A Venn diagram showing overlap of differentially",
                      "expressed genes between comparisons."))
    vennInLine(venn, cap)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_affycoretools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_affycoretools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_affycoretools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AFFYCORETOOLS:", paste0("    affycoretools: ", packageVersion("affycoretools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affycoretools_results.csv
    touch ${prefix}_affycoretools_output.rds
    echo "BIOC_AFFYCORETOOLS:" > versions.yml
    echo "    affycoretools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AFFYCORETOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(expressionset) ]

    main:
    BIOC_AFFYCORETOOLS(ch_input)

    emit:
    results  = BIOC_AFFYCORETOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AFFYCORETOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AFFYCORETOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AFFYCORETOOLS.out.versions  // channel: path(versions.yml)
}
