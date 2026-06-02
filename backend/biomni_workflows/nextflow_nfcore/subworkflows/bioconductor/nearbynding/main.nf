#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: nearBynding
// Provides a pipeline to discern RNA structure at and proximal to the site of protein binding within r
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/nearBynding/inst/doc/nearBynding.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("nearBynding")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NEARBYNDING {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nearbynding"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nearbynding:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nearbynding:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nearbynding_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nearbynding_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nearbynding_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomeMappingToChainFile)
    library(jsonlite)

    # --- Load [] ---
    # Key functions: GenomeMappingToChainFile
    ---------------------------------------------------------------------
    # load transcript list
    load(system.file("extdata/transcript_list.Rda", package="nearBynding"))
    # get GTF file
    gtf<-system.file("extdata/Homo_sapiens.GRCh38.chr4&5.gtf",
    # --- Getchainchrsize [] ---
    # Key functions: getChainChrSize
    ---------------------------------------------------------------------
    getChainChrSize(chain = "test.chain",
                    out_chr = "chr4and5_3UTR.size")
    # --- Liftovertoexomicbg [] ---
    # Key functions: liftOverToExomicBG
    ---------------------------------------------------------------------
    liftOverToExomicBG(input = "chr4and5_sorted.bedGraph",
                        chain = "test.chain",
                        chrom_size = "chr4and5_3UTR.size",
                        output_bg = "chr4and5_liftOver.bedGraph")
    # --- Processcaprout [] ---
    # Key functions: processCapRout
    ---------------------------------------------------------------------
    processCapRout(CapR_outfile = system.file("extdata/chr4and5_3UTR.out",
                                                package="nearBynding"),
                    chain = "test.chain",
                    output_prefix = "chr4and5_3UTR",
    # --- Bindingcontextdistance [] ---
    # Key functions: bindingContextDistance
    ---------------------------------------------------------------------
    bindingContextDistance(RNA_context = "chr4and5_3UTR_stem_liftOver",
                            protein_file = "chr4and5_liftOver",
                            RNA_context_2 = "chr4and5_3UTR_hairpin_liftOver")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nearbynding_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nearbynding_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nearbynding_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NEARBYNDING:", paste0("    nearbynding: ", packageVersion("nearBynding"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nearbynding_results.csv
    touch ${prefix}_nearbynding_output.rds
    echo "BIOC_NEARBYNDING:" > versions.yml
    echo "    nearbynding: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NEARBYNDING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NEARBYNDING(ch_input)

    emit:
    results  = BIOC_NEARBYNDING.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NEARBYNDING.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NEARBYNDING.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NEARBYNDING.out.versions  // channel: path(versions.yml)
}
