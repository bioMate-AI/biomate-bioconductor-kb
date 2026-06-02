#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VaSP
// Discovery of genome-wide variable alternative splicing events from short-read RNA-seq data and visua
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VaSP/inst/doc/VaSP.R
// Upstream  : Sushi
// Downstream: none
//
// Install: BiocManager::install("VaSP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VASP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vasp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vasp:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vasp:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vasp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vasp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vasp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(VaSP)
    library(jsonlite)

    # --- Genome-wide Splicing Quantification [] ---
    # Key functions: spliceGenome
    data(rice.bg)
    splice <- spliceGenome(rice.bg, gene.select = NA, intron.select = NA)
    scores <- splice$score
    introns <- splice$intron


    # --- Bimodal Splicing Feature Discovery [] ---
    # Key functions: BMfinder, spliceGene
    data(rice.bg)
    score <- spliceGene(rice.bg, gene = "MSTRG.183", junc.type = "score")
    gss <- BMfinder(score, cores = 1)


    # --- Read Depth Extraction [] ---
    # Key functions: getDepth
    path <- system.file("extdata", package = "VaSP")
    bam_files <- list.files(path, "*.bam$")
    depth <- getDepth(
        file.path(path, bam_files[1]), 
        "Chr1", 
        start = 1171800, 
        end = 1179400
    )


    # --- Gene Structure Information Retrieval [] ---
    # Key functions: getGeneinfo
    data(rice.bg)
    gene_ids <- c("MSTRG.181", "MSTRG.182", "MSTRG.183")
    geneinfo <- getGeneinfo(genes = gene_ids, rice.bg)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vasp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vasp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vasp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VASP:", paste0("    vasp: ", packageVersion("VaSP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vasp_results.csv
    touch ${prefix}_vasp_output.rds
    echo "BIOC_VASP:" > versions.yml
    echo "    vasp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VASP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VASP(ch_input)

    emit:
    results  = BIOC_VASP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VASP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VASP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VASP.out.versions  // channel: path(versions.yml)
}
