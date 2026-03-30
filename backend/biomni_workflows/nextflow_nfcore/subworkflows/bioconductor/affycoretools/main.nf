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
    library(HTMLReport)
    library(jsonlite)

    # --- Linear model fit (limma) [] ---
    # Key functions: annotateEset, pData, lmFit
    suppressMessages(library(hgu95av2.db))
    eset <- annotateEset(eset, hgu95av2.db)
    suppressMessages(library(limma))
    # --- H T M L Report [] ---
    # Key functions: HTMLReport, publish, finish
    suppressMessages(library(ReportingTools))
    htab <- HTMLReport("afile", "My cool results")
    publish(topTable(fit2, 1), htab)
    # --- make Images [] ---
    # Key functions: makeImages, HTMLReport, publish, finish
    d.f <- topTable(fit2, 2)
    out <- makeImages(df = d.f, eset = eset, grp.factor = pd$type, design = design,
    htab <- HTMLReport("afile3", "My cool results, affycoretools style")
    # --- Linear model fit (limma) [] ---
    # Key functions: lmFit, eBayes
    grps <- factor(apply(pd[,1:2], 1, paste, collapse = "_"))
    design <- model.matrix(~0+grps)
    colnames(design) <- gsub("grps", "", colnames(design))
    # --- H T M L Report [] ---
    # Key functions: HTMLReport, makeImages, publish, finish
    out <- lapply(1:3, function(x) topTable(fit2, x))
    htab <- lapply(1:3, function(x){
    tmp <- HTMLReport(gsub("_", " ", colnames(contrast)[x]), colnames(contrast)[x], "./reports")
    # --- kable [] ---
    # Key functions: kable
    d.f <- data.frame(Comparison =  sapply(htab, function(x) XML::saveXML(Link(x))),
    "Number significant" = sapply(out, nrow), check.names = FALSE)
    kable(d.f, caption = "Number of significant genes.",
    # --- make Venn [] ---
    # Key functions: makeVenn, vennInLine
    collist <- list(1:2)
    venn <- makeVenn(fit2, contrast, design, collist = collist, adj.meth = "none")
    cap <- list(paste("A Venn diagram. Note that the first sentence is bolded",

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
