#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: chromDraw
// ChromDraw is a R package for drawing the schemes of karyotype(s) in the linear and circular fashion.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/chromDraw/inst/doc/chromDraw.R
// Upstream  : GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("chromDraw")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHROMDRAW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chromdraw"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chromdraw:2.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chromdraw:2.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chromdraw_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chromdraw_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chromdraw_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(IRanges)
    library(Rle)
    library(jsonlite)

    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, Rle, IRanges
    library(GenomicRanges)
    exampleData <- GRanges(seqnames =Rle(c("ACK1"), c(4)),ranges =
    IRanges(start = c(0, 6700000,0,12400000),
            end = c(6700000,12400000,0,17000000),
            names = c("A","B","CENTROMERE","C")),
    # --- frame [] ---
    # Key functions: frame
    name <- c("yellow", "red");
    r <- c(255, 255);
    g <- c(255, 0);
    b <- c(0, 0);
    exampleColor <- data.frame(name,r,g,b);
    # --- path [] ---
    # Key functions: path, chromDraw
    library(chromDraw)
    OUTPUTPATH = file.path(getwd());
    INPUTPATH = system.file('extdata',
                            'Ack_and_Stenopetalum_nutans.txt',
                            package ='chromDraw')
    # --- chrom Draw G R [] ---
    # Key functions: chromDrawGR
    library(chromDraw)
    chromDrawGR(list(exampleData), exampleColor);
    # --- path [] ---
    # Key functions: path, chromDraw
    library(chromDraw)
    OUTPUTPATH = file.path(getwd());
    INPUTPATH = system.file('extdata',
                            'bed.bed',
                            package ='chromDraw')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chromdraw_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chromdraw_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chromdraw_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHROMDRAW:", paste0("    chromdraw: ", packageVersion("chromDraw"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromdraw_results.csv
    touch ${prefix}_chromdraw_output.rds
    echo "BIOC_CHROMDRAW:" > versions.yml
    echo "    chromdraw: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHROMDRAW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHROMDRAW(ch_input)

    emit:
    results  = BIOC_CHROMDRAW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHROMDRAW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHROMDRAW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHROMDRAW.out.versions  // channel: path(versions.yml)
}
