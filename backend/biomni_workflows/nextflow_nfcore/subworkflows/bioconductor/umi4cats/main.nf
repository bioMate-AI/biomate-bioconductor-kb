#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: UMI4Cats
// UMI-4C is a technique that allows characterization of 3D chromatin interactions with a bait of inter
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/UMI4Cats/inst/doc/UMI4Cats.R
// Upstream  : tidyr
// Downstream: none
//
// Install: BiocManager::install("UMI4Cats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_UMI4CATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-umi4cats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-umi4cats:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-umi4cats:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_umi4cats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_umi4cats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_umi4cats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(UMI4Cats)
    library(jsonlite)


    # --- Logo [] ---
    # Key functions: include_graphics
    knitr::include_graphics("../man/figures/UMI4Cats.png", dpi = 800)

    # --- Load [] ---
    # Key functions: include_graphics, downloadUMI4CexampleData, DpnII, digestGenome
    library(UMI4Cats)

    ## ----umi4cats-scheme, echo=FALSE, eval=TRUE, fig.cap="Overview of the different functions included in the UMI4Cats package to analyze UMI-4C data."----
    knitr::include_graphics("figures/scheme.png", dpi = 400)

    ## ----processing-quick-start, eval=FALSE---------------------------------------
    #  ## 0) Download example data -------------------------------
    #  path <- downloadUMI4CexampleData()
    #  
    #  ## 1) Generate Digested genome ----------------------------
    #  # The selected RE in this case is DpnII (|GATC), so the cut_pos is 0, and the res_enz "GATC".
    # --- Demultiplex [] ---
    # Key functions: downloadUMI4CexampleData, tempdir, demultiplexFastq, fastq, ctrl_hi24_CIITA_R1.fastq.gz
    ## Input files
    path <- downloadUMI4CexampleData(reduced=TRUE)
    fastq <- file.path(path, "CIITA", "fastq", "ctrl_hi24_CIITA_R1.fastq.gz")

    ## Barcode info
    barcodes <- data.frame(
        sample = c("CIITA"),
        barcode = c("GGACAAGCTCCCTGCAACTCA")
    )

    ## Output path
    out_path <- tempdir()

    ## Demultiplex baits inside FastQ file
    # --- Digest [] ---
    # Key functions: digestGenome, chr, tempdir, dpnII, chr16
    library(BSgenome.Hsapiens.UCSC.hg19)
    refgen <- BSgenome.Hsapiens.UCSC.hg19

    hg19_dpnii <- digestGenome(
        res_enz = "GATC",
        cut_pos = 0,
        name_RE = "dpnII",
        ref_gen = refgen,
        sel_chr = "chr16", # Select bait's chr (chr16) to make example faster
        out_path = file.path(tempdir(), "digested_genome/")
    )

    hg19_dpnii

    ## ----read-scheme, echo=FALSE, eval=TRUE, fig.cap="Schematic of a UMI-4C read detailing the different elements that need to be used as input for processing the data."----

    # --- Processing [] ---
    # Key functions: downloadUMI4CexampleData, contactsUMI4C, fastq, ref_genome, ucsc.hg19.chr16, ctrl_hi24_CIITA
    ## Use reduced example to make vignette faster
    ## If you want to download the full dataset, set reduced = FALSE or remove
    ## the reduce argument.
    ## The reduced example is already downloaded in the demultiplexFastq chunk.

    # path <- downloadUMI4CexampleData(reduced=TRUE)
    raw_dir <- file.path(path, "CIITA", "fastq")
    index_path <- file.path(path, "ref_genome", "ucsc.hg19.chr16")

    ## Run main function to process UMI-4C contacts
    # --- Stats [] ---
    # Key functions: statsUMI4C, read.delim, list.files, extdata, logs, stats_summary.txt, count
    # Using the full dataset included in the package
    statsUMI4C(wk_dir = system.file("extdata", "CIITA",
        package = "UMI4Cats"
    ))

    # Read stats table
    stats <- read.delim(system.file("extdata", "CIITA", "logs", "stats_summary.txt",
        package = "UMI4Cats"
    ))

    knitr::kable(stats)

    ## ----make-umi4c---------------------------------------------------------------
    # Load sample processed file paths

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_umi4cats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_umi4cats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_umi4cats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_UMI4CATS:", paste0("    umi4cats: ", packageVersion("UMI4Cats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_umi4cats_results.csv
    touch ${prefix}_umi4cats_output.rds
    echo "BIOC_UMI4CATS:" > versions.yml
    echo "    umi4cats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_UMI4CATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_UMI4CATS(ch_input)

    emit:
    results  = BIOC_UMI4CATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_UMI4CATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_UMI4CATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_UMI4CATS.out.versions  // channel: path(versions.yml)
}
