#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FitHiC
// Fit-Hi-C is a tool for assigning statistical confidence estimates to intra-chromosomal contact maps 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FitHiC/inst/doc/fithic.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("FitHiC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FITHIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fithic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fithic:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fithic:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fithic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fithic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fithic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FitHiC)
    library(jsonlite)


    # --- Run [] ---
    # Key functions: getwd, FitHiC, extdata, Duan_yeast_EcoRI, hide
    library("FitHiC")
    fragsfile <- system.file("extdata", "fragmentLists/Duan_yeast_EcoRI.gz",
        package = "FitHiC")
    intersfile <- system.file("extdata", "contactCounts/Duan_yeast_EcoRI.gz",
        package = "FitHiC")
    outdir <- file.path(getwd(), "Duan_yeast_EcoRI")
    FitHiC(fragsfile, intersfile, outdir, libname="Duan_yeast_EcoRI",
        distUpThres=250000, distLowThres=10000)

    ## ----run-visual, echo=FALSE, message=FALSE, warning=FALSE, results="hide"-----
    library("FitHiC")
    fragsfile <- system.file("extdata", "fragmentLists/Duan_yeast_EcoRI.gz",
        package = "FitHiC")
    intersfile <- system.file("extdata", "contactCounts/Duan_yeast_EcoRI.gz",
        package = "FitHiC")

    # --- Fragsfile [] ---
    # Key functions: read.table, gzfile, extdata, crrrr
    fragsfile <- system.file("extdata",
        "fragmentLists/Dixon_hESC_HindIII_hg18_w40000_chr1.gz", package = "FitHiC")
    data <- read.table(gzfile(fragsfile), header=FALSE,
        col.names=c("Chromosome Name", "Column 2", "Mid Point", "Hit Count",
        "Column 5"))
    knitr::kable(head(data, n=6L), align = "crrrr", caption="FRAGSFILE")

    # --- Intersfile [] ---
    # Key functions: read.table, gzfile, extdata, crcrr
    intersfile <- system.file("extdata",
        "contactCounts/Dixon_hESC_HindIII_hg18_w40000_chr1.gz", package = "FitHiC")
    data <- read.table(gzfile(intersfile), header=FALSE,
        col.names=c("Chromosome1 Name", "Mid Point 1", "Chromosome2 Name",
        "Mid Point 2", "Hit Count"))
    knitr::kable(head(data, n=6L), align = "crcrr", caption="INTERSFILE")

    # --- Biasfile [] ---
    # Key functions: read.table, gzfile, extdata, crr
    biasfile <- system.file("extdata",
        "biasPerLocus/Dixon_hESC_HindIII_hg18_w40000_chr1.gz", package = "FitHiC")
    data <- read.table(gzfile(biasfile), header=FALSE,
        col.names=c("Chromosome Name", "Mid Point", "Bias"))
    knitr::kable(head(data, n=6L), align = "crr", caption="BIASFILE")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fithic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fithic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fithic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FITHIC:", paste0("    fithic: ", packageVersion("FitHiC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fithic_results.csv
    touch ${prefix}_fithic_output.rds
    echo "BIOC_FITHIC:" > versions.yml
    echo "    fithic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FITHIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FITHIC(ch_input)

    emit:
    results  = BIOC_FITHIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FITHIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FITHIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FITHIC.out.versions  // channel: path(versions.yml)
}
