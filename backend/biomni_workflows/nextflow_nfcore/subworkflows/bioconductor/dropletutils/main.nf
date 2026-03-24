#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DropletUtils
// Provides a number of utility functions for handling single-cell (RNA-seq) data from droplet technolo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DropletUtils/inst/doc/DropletUtils.R
// Upstream  : knitr
// Downstream: OSCA.advanced, OSCA.intro, OSCA.multisample, OSCA.workflows
//
// Install: BiocManager::install("DropletUtils")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DROPLETUTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dropletutils"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dropletutils:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dropletutils:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dropletutils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dropletutils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dropletutils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DropletUtils)
    library(jsonlite)

    # --- Example [] ---
    # Key functions: example, files
    ---------------------------------------------------------------------
    # To generate the files.
    example(write10xCounts, echo=FALSE)
    dir.name <- tmpdir
    list.files(dir.name)
    # --- read10x Counts [] ---
    # Key functions: read10xCounts
    ---------------------------------------------------------------------
    sce <- read10xCounts(dir.name)
    sce
    # --- Class [] ---
    # Key functions: counts
    ---------------------------------------------------------------------
    class(counts(sce))
    # --- read10x Mol Info [] ---
    # Key functions: read10xMolInfo
    ---------------------------------------------------------------------
    mol.info <- read10xMolInfo(mol.info.file)
    mol.info
    # --- Barcoderanks [] ---
    # Key functions: barcodeRanks, metadata
    ---------------------------------------------------------------------
    br.out <- barcodeRanks(my.counts)
    # Making a plot.
    plot(br.out$rank, br.out$total, log="xy", xlab="Rank", ylab="Total")
    o <- order(br.out$rank)
    # --- Plot [] ---
    # Key functions: ifelse
    ---------------------------------------------------------------------
    plot(e.out$Total, -e.out$LogProb, col=ifelse(is.cell, "red", "black"),
        xlab="Total UMI count", ylab="-Log Probability")
    # --- Emptydrops [] ---
    # Key functions: emptyDrops
    ---------------------------------------------------------------------
    hto.calls <- emptyDrops(y, lower=500)
    has.cell <- hto.calls$FDR <= 0.001
    summary(has.cell)
    # --- Hasheddrops [] ---
    # Key functions: hashedDrops, metadata
    ---------------------------------------------------------------------
    demux <- hashedDrops(y[,which(has.cell)],
        ambient=metadata(hto.calls)$ambient)
    demux
    # --- Ifelse [] ---
    # Key functions: ifelse
    ---------------------------------------------------------------------
    colors <- ifelse(demux$Confident, "black",
        ifelse(demux$Doublet, "red", "grey"))
    plot(demux$LogFC, demux$LogFC2, col=colors,
        xlab="Log-fold change between best and second HTO",
    # --- Swappeddrops [] ---
    # Key functions: swappedDrops
    ---------------------------------------------------------------------
    s.out <- swappedDrops(mult.mol.info, min.frac=0.9)
    length(s.out$cleaned)
    class(s.out$cleaned[[1]])
    # --- Chimericdrops [] ---
    # Key functions: chimericDrops
    ---------------------------------------------------------------------
    out <- chimericDrops(mult.mol.info[1])
    class(out)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dropletutils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dropletutils_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dropletutils_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DROPLETUTILS:", paste0("    dropletutils: ", packageVersion("DropletUtils"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dropletutils_results.csv
    touch ${prefix}_dropletutils_output.rds
    echo "BIOC_DROPLETUTILS:" > versions.yml
    echo "    dropletutils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DROPLETUTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DROPLETUTILS(ch_input)

    emit:
    results  = BIOC_DROPLETUTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DROPLETUTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DROPLETUTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DROPLETUTILS.out.versions  // channel: path(versions.yml)
}
