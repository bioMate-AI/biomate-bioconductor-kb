#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: minfi
// Tools to analyze & visualize Illumina Infinium methylation arrays.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/minfi/inst/doc/minfi.R
// Upstream  : minfiData
// Downstream: bigmelon, ChAMP, conumee, methylumi, REMP
//
// Install: BiocManager::install("minfi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MINFI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-minfi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-minfi:1.52.1--r44_0' :
        'quay.io/biocontainers/bioconductor-minfi:1.52.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_minfi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_minfi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_minfi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(minfi)
    library(jsonlite)


    # --- Rgset Ex [] ---
    # Key functions: preprocessRaw, mapToGenome
    RGsetEx
    ## RGsetEx: RGChannelSet, 622,399 features
    MsetEx <- preprocessRaw(RGsetEx)
    ## MsetEx: MethylSet, 485,512 features
    GMsetEx <- mapToGenome(MsetEx)
    ## GMsetEx: GenomicMethylSet, 485,512 features

    # --- Base Dir [] ---
    # Key functions: list.files, extdata, minfiData
    baseDir <- system.file("extdata", package = "minfiData")
    list.files(baseDir)

    # --- Base Dir2 [] ---
    # Key functions: list.files
    list.files(file.path(baseDir, "5723646052"))

    # --- Sheet [] ---
    # Key functions: read.metharray.sheet
    targets <- read.metharray.sheet(baseDir)
    targets

    # --- Basename Column> [] ---
    # Key functions: minfi
    sub(baseDir, "", targets$Basename)

    # --- Reading Targets [] ---
    # Key functions: read.metharray.exp
    RGset <- read.metharray.exp(targets = targets)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_minfi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_minfi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_minfi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MINFI:", paste0("    minfi: ", packageVersion("minfi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_minfi_results.csv
    touch ${prefix}_minfi_output.rds
    echo "BIOC_MINFI:" > versions.yml
    echo "    minfi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MINFI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MINFI(ch_input)

    emit:
    results  = BIOC_MINFI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MINFI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MINFI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MINFI.out.versions  // channel: path(versions.yml)
}
