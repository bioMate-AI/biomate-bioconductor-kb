#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MAGAR
// "Methylation-Aware Genotype Association in R" (MAGAR) computes methQTL from DNA methylation and geno
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MAGAR/inst/doc/MAGAR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MAGAR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAGAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-magar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-magar:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-magar:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_magar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_magar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_magar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MAGAR)
    library(jsonlite)

    # --- methQTL Analysis [] ---
    # Key functions: loadMethQTLInput, doMethQTL
    imp.data <- loadMethQTLInput(
        system.file("extdata", "reduced_methQTL", package = "magar")
    )
    meth.qtl.res <- doMethQTL(
        imp.data,
        default.options = FALSE,
        p.val.cutoff = 0.05
    )


    # --- Result Extraction [] ---
    # Key functions: getResult, getAnno
    result.table <- getResult(meth.qtl.res)
    anno.meth <- getAnno(meth.qtl.res, "meth")
    anno.geno <- getAnno(meth.qtl.res, "geno")


    # --- Visualisation [] ---
    # Key functions: qtlPlotSNPCpGInteraction, qtlDistanceScatterplot
    sorted.results <- result.table[order(result.table$P.value), ]
    qtlPlotSNPCpGInteraction(
        imp.data,
        sorted.results$CpG[1],
        sorted.results$SNP[1]
    )
    qtlDistanceScatterplot(meth.qtl.res)


    # --- Interpretation and Comparison [] ---
    # Key functions: qtlBaseSubstitutionEnrichment, loadMethQTLResult, qtlVennPlot, qtlUpsetPlot, getSpecificQTL
    res <- qtlBaseSubstitutionEnrichment(meth.qtl.res)
    meth.qtl.res.2 <- loadMethQTLResult(
        system.file("extdata", "MethQTLResult_chr18", package = "magar")
    )
    meth.qtl.list <- list(First = meth.qtl.res, Second = meth.qtl.res.2)
    qtlVennPlot(meth.qtl.list, out.folder = tempdir())
    qtlUpsetPlot(meth.qtl.list, type = "cor.block")
    spec.first <- getSpecificQTL(meth.qtl.list$First, meth.qtl.list[-1])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_magar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_magar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_magar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MAGAR:", paste0("    magar: ", packageVersion("MAGAR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_magar_results.csv
    touch ${prefix}_magar_output.rds
    echo "BIOC_MAGAR:" > versions.yml
    echo "    magar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MAGAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MAGAR(ch_input)

    emit:
    results  = BIOC_MAGAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MAGAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MAGAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MAGAR.out.versions  // channel: path(versions.yml)
}
