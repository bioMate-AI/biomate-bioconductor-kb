#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SimFFPE
// The NGS (Next-Generation Sequencing) reads from FFPE (Formalin-Fixed Paraffin-Embedded) samples cont
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SimFFPE/inst/doc/SimFFPE.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SimFFPE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIMFFPE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-simffpe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-simffpe:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-simffpe:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(bamfile)

    output:
    tuple val(meta), path("${meta.id}_simffpe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_simffpe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_simffpe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAStringSet)
    library(jsonlite)

    # --- Calcphredscoreprofile [] ---
    # Key functions: calcPhredScoreProfile
    library(SimFFPE)
    bamFilePath <- system.file("extdata", "example.bam", package = "SimFFPE")
    regionPath <- system.file("extdata", "regionsBam.txt", package = "SimFFPE")
    regions <- read.table(regionPath)
    PhredScoreProfile <- calcPhredScoreProfile(bamFilePath, targetRegions = regions)
    # --- Readdnastringset [] ---
    # Key functions: readDNAStringSet
    referencePath <- system.file("extdata", "example.fasta", package = "SimFFPE")
    reference <- readDNAStringSet(referencePath)
    reference
    # --- Target Region Table [] ---
    # Key functions: file
    regionPath <- system.file("extdata", "regionsSim.txt", package = "SimFFPE")
    targetRegions <- read.table(regionPath)
    # --- Readsimffpe [] ---
    # Key functions: tempdir, readSimFFPE, DNAStringSet
    ## Simulate reads of the first three sequences of the reference genome
    sourceSeq <- reference[1:3]
    outFile1 <- paste0(tempdir(), "/sim1")
    # --- Targetreadsimffpe [] ---
    # Key functions: tempdir, targetReadSimFFPE
    outFile3 <- paste0(tempdir(), "/sim3")
    targetReadSimFFPE(referencePath, PhredScoreProfile, targetRegions, outFile3,
                      coverage = 120, readLen = 100, meanInsertLen = 180,
                      sdInsertLen = 50, enzymeCut = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_simffpe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_simffpe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_simffpe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIMFFPE:", paste0("    simffpe: ", packageVersion("SimFFPE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simffpe_results.csv
    touch ${prefix}_simffpe_output.rds
    echo "BIOC_SIMFFPE:" > versions.yml
    echo "    simffpe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIMFFPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(bamfile) ]

    main:
    BIOC_SIMFFPE(ch_input)

    emit:
    results  = BIOC_SIMFFPE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIMFFPE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIMFFPE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIMFFPE.out.versions  // channel: path(versions.yml)
}
