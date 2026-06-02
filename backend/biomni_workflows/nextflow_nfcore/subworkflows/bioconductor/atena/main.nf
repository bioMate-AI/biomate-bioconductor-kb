#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: atena
// Quantify expression of transposable elements (TEs) from RNA-seq data through different methods, incl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/atena/inst/doc/atena.R
// Upstream  : BiocParallel, RColorBrewer
// Downstream: none
//
// Install: BiocManager::install("atena")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ATENA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-atena"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-atena:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-atena:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_atena_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_atena_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_atena_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(atena)
    library(jsonlite)


    # --- Comparsedann [] ---
    # Key functions: brewer.pal, mcols, par, grid, axis, text, black
    library(RColorBrewer)

    pal1 <- brewer.pal(6, "Pastel2")
    pal2 <- brewer.pal(length(unique(mcols(teann)$Class)), "Set2")

    par(mfrow = c(1,2), mar = c(5,4,3,1))
    bp1 <- barplot(table(mcols(teann)$Status), col = pal1, border = "black",
            main = "TEs by status", cex.axis=0.8, xaxt = "n")
    grid(nx=NA, ny=NULL)
    axis(1, at=bp1, labels = FALSE, las=1, line=0, lwd = 0, lwd.ticks = 1) 
    par(xpd=TRUE)
    text(x= bp1[, 1] - 0.3, y = 10, labels=names(table(mcols(teann)$Status)), 
         srt=40, offset = 1.7, cex = 0.8, pos = 1)
    par(xpd=FALSE)


    # --- Results='hide' [] ---
    # Key functions: qtex, colSums, assay
    emq <- qtex(empar)

    ## -----------------------------------------------------------------------------
    emq
    colSums(assay(emq))

    # --- Results='hide' [] ---
    # Key functions: qtex, colSums, assay
    tsq <- qtex(tspar)

    ## -----------------------------------------------------------------------------
    tsq
    colSums(assay(tsq))

    # --- Results='hide' [] ---
    # Key functions: qtex, colSums, assay, rowData
    ttq <- qtex(ttpar)

    ## -----------------------------------------------------------------------------
    ttq
    colSums(assay(ttq))

    ## -----------------------------------------------------------------------------
    head(assay(ttq))

    ## -----------------------------------------------------------------------------
    rowData(ttq)

    ## -----------------------------------------------------------------------------
    table(rowData(ttq)$isTE)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_atena_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_atena_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_atena_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ATENA:", paste0("    atena: ", packageVersion("atena"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_atena_results.csv
    touch ${prefix}_atena_output.rds
    echo "BIOC_ATENA:" > versions.yml
    echo "    atena: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ATENA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ATENA(ch_input)

    emit:
    results  = BIOC_ATENA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ATENA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ATENA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ATENA.out.versions  // channel: path(versions.yml)
}
