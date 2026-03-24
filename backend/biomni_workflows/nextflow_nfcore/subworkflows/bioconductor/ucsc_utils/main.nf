#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: UCSC.utils
// A set of low-level utilities to retrieve data from the UCSC Genome Browser. Most functions in the pa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/UCSC.utils/inst/doc/UCSC.utils.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("UCSC.utils")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_UCSC_UTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ucsc_utils"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ucsc.utils:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ucsc.utils:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ucsc_utils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ucsc_utils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ucsc_utils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(UCSC_dbselect)
    library(jsonlite)

    # --- list UCSC genomes [] ---
    # Key functions: list_UCSC_genomes
    suppressPackageStartupMessages(library(UCSC.utils))
    list_UCSC_genomes("cat")
    # --- get UCSC chrom sizes [] ---
    # Key functions: get_UCSC_chrom_sizes
    felCat9_chrom_sizes <- get_UCSC_chrom_sizes("felCat9")
    head(felCat9_chrom_sizes)
    # --- list UCSC tracks [] ---
    # Key functions: list_UCSC_tracks
    list_UCSC_tracks("felCat9", group="varRep")
    # --- fetch UCSC track data [] ---
    # Key functions: fetch_UCSC_track_data
    mm9_cytoBandIdeo <- fetch_UCSC_track_data("mm9", "cytoBandIdeo")
    head(mm9_cytoBandIdeo)
    # --- UCSC dbselect [] ---
    # Key functions: UCSC_dbselect
    felCat9_refGene <- UCSC_dbselect("felCat9", "refGene")
    head(felCat9_refGene)
    # --- UCSC dbselect2 [] ---
    # Key functions: UCSC_dbselect
    columns <- c("chrom", "strand", "txStart", "txEnd", "exonCount", "name2")
    UCSC_dbselect("felCat9", "refGene", columns=columns, where="chrom='chrA1'")
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ucsc_utils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ucsc_utils_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ucsc_utils_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_UCSC_UTILS:", paste0("    ucsc_utils: ", packageVersion("UCSC.utils"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ucsc_utils_results.csv
    touch ${prefix}_ucsc_utils_output.rds
    echo "BIOC_UCSC_UTILS:" > versions.yml
    echo "    ucsc_utils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_UCSC_UTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_UCSC_UTILS(ch_input)

    emit:
    results  = BIOC_UCSC_UTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_UCSC_UTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_UCSC_UTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_UCSC_UTILS.out.versions  // channel: path(versions.yml)
}
