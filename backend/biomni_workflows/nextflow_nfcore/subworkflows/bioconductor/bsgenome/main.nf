#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BSgenome
// Infrastructure shared by all the Biostrings-based genome data packages.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BSgenome/inst/doc/GenomeSearching.R
// Upstream  : hgu95av2probe
// Downstream: bambu, BSgenomeForge, ChIPanalyser, GOTHiC, HelloRanges
//
// Install: BiocManager::install("BSgenome")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BSGENOME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bsgenome"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bsgenome:1.74.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bsgenome:1.74.0--r44_0'}"

    input:
    tuple val(meta), path(bsgenome)

    output:
    tuple val(meta), path("${meta.id}_bsgenome_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bsgenome_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bsgenome_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAString)
    library(jsonlite)

    # --- Object metadata inspection [] ---
    # Key functions: metadata, seqnames, seqinfo, alphabetFrequency, countPattern, matchPattern, mismatch, DNAString
    runOneStrandAnalysis <- function(dict0, bsgenome, seqnames, strand,
                                     outfile="", append=FALSE)
    {
        cat("\nTarget: strand", strand, "of", metadata(bsgenome)$genome,
            "chromosomes", paste(seqnames, collapse=", "), "\n")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bsgenome_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bsgenome_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bsgenome_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BSGENOME:", paste0("    bsgenome: ", packageVersion("BSgenome"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bsgenome_results.csv
    touch ${prefix}_bsgenome_output.rds
    echo "BIOC_BSGENOME:" > versions.yml
    echo "    bsgenome: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BSGENOME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(bsgenome) ]

    main:
    BIOC_BSGENOME(ch_input)

    emit:
    results  = BIOC_BSGENOME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BSGENOME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BSGENOME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BSGENOME.out.versions  // channel: path(versions.yml)
}
