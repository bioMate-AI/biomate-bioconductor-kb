#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: regutools
// RegulonDB has collected, harmonized and centralized data from hundreds of experiments for nearly two
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/regutools/inst/doc/regutools.R
// Upstream  : BiocStyle, Biostrings, RefManageR, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("regutools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGUTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regutools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regutools:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-regutools:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_regutools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regutools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regutools_plots.pdf"),    emit: plots, optional: true
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
    library(PrintBibliography)
    library(jsonlite)

    # --- Vignettesetup [] ---
    # Key functions: time
    ## For links
    library("BiocStyle")
    ## Track time spent on making the vignette
    startTime <- Sys.time()
    ## Bib setup
    # --- 'Connect Db' [] ---
    # Key functions: connect_database, regulondb
    library("regutools")
    ## Other packages used
    library("Biostrings")
    ## Connect to the RegulonDB database
    regulondb_conn <- connect_database()
    # --- 'List Datasets' [] ---
    # Key functions: list_datasets
    list_datasets(e_coli_regulondb)
    # --- 'List Attr' [] ---
    # Key functions: list_attributes
    head(list_attributes(e_coli_regulondb, "GENE"), 8)
    # --- 'Get Dataset' [] ---
    # Key functions: get_dataset

    # --- 'Get Dataset Interval' [] ---
    # Key functions: get_dataset

    # --- 'Get Dataset Df' [] ---
    # Key functions: get_dataset, slotNames

    # --- 'Convert Granges' [] ---
    # Key functions: convert_to_granges
    convert_to_granges(res)
    # --- 'Get Dataset Granges' [] ---
    # Key functions: get_dataset

    # --- 'Dnastring Res' [] ---
    # Key functions: get_dataset, convert_to_biostrings, mcols

    # --- 'Product Seq' [] ---
    # Key functions: get_dataset, convert_to_biostrings, mcols

    # --- 'Partial Match' [] ---
    # Key functions: get_dataset

    # --- 'Position Interval' [] ---
    # Key functions: get_dataset

    # --- 'Genomic Elements' [] ---
    # Key functions: get_dna_objects
    get_dna_objects(e_coli_regulondb)
    # --- 'Especific Ranges' [] ---
    # Key functions: GRanges, IRanges, get_dna_objects
    grange <- GenomicRanges::GRanges(
        "chr",
        IRanges::IRanges(5000, 10000)
    )
    get_dna_objects(e_coli_regulondb, grange)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regutools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regutools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regutools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGUTOOLS:", paste0("    regutools: ", packageVersion("regutools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regutools_results.csv
    touch ${prefix}_regutools_output.rds
    echo "BIOC_REGUTOOLS:" > versions.yml
    echo "    regutools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGUTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REGUTOOLS(ch_input)

    emit:
    results  = BIOC_REGUTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGUTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGUTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGUTOOLS.out.versions  // channel: path(versions.yml)
}
