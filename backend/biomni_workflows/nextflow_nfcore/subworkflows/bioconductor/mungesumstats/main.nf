#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MungeSumstats
// The *MungeSumstats* package is designed to facilitate the standardisation of GWAS summary statistics
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MungeSumstats/inst/doc/MungeSumstats.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MungeSumstats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUNGESUMSTATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mungesumstats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mungesumstats:1.14.1--r44_0' :
        'quay.io/biocontainers/bioconductor-mungesumstats:1.14.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mungesumstats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mungesumstats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mungesumstats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MungeSumstats)
    library(jsonlite)

    # --- Formatted Example [] ---
    # Key functions: formatted_example, liftover
    ---------------------------------------------------------------------
    sumstats_dt <- MungeSumstats::formatted_example()
    sumstats_dt_hg38 <- MungeSumstats::liftover(sumstats_dt = sumstats_dt,
                                                ref_genome = "hg19",
                                                convert_ref_genome = "hg38")
    # --- Copy [] ---
    # Key functions: copy, setnames, runif, standardise_header
    ---------------------------------------------------------------------
    #### Mess up some column names ####
    dat_raw <- data.table::copy(dat)
    data.table::setnames(dat_raw, c("SNP","CHR"), c("rsID","Seqnames"))
    #### Add a non-standard column that I want to keep the casing for ####

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mungesumstats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mungesumstats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mungesumstats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MUNGESUMSTATS:", paste0("    mungesumstats: ", packageVersion("MungeSumstats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mungesumstats_results.csv
    touch ${prefix}_mungesumstats_output.rds
    echo "BIOC_MUNGESUMSTATS:" > versions.yml
    echo "    mungesumstats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MUNGESUMSTATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MUNGESUMSTATS(ch_input)

    emit:
    results  = BIOC_MUNGESUMSTATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MUNGESUMSTATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MUNGESUMSTATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MUNGESUMSTATS.out.versions  // channel: path(versions.yml)
}
