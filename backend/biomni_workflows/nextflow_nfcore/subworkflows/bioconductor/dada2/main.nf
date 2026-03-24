#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dada2
// The dada2 package infers exact amplicon sequence variants (ASVs) from high-throughput amplicon seque
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dada2/inst/doc/dada2-intro.R
// Upstream  : none
// Downstream: MiscMetabar
//
// Install: BiocManager::install("dada2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DADA2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dada2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dada2:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dada2:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dada2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dada2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dada2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(dada2)
    library(jsonlite)

    # --- plot Quality Profile [] ---
    # Key functions: plotQualityProfile
    plotQualityProfile(fnF1) # Forward
    plotQualityProfile(fnR1) # Reverse
    # --- filter And Trim [] ---
    # Key functions: filterAndTrim
    filterAndTrim(fwd=fnF1, filt=filtF1, rev=fnR1, filt.rev=filtR1,
    trimLeft=10, truncLen=c(240, 200),
    # --- derep Fastq [] ---
    # Key functions: derepFastq
    derepF1 <- derepFastq(filtF1, verbose=TRUE)
    derepR1 <- derepFastq(filtR1, verbose=TRUE)
    # --- learn Errors [] ---
    # Key functions: learnErrors
    errF <- learnErrors(derepF1, multithread=FALSE) # multithreading is available on many functions
    errR <- learnErrors(derepR1, multithread=FALSE)
    # --- dada [] ---
    # Key functions: dada
    dadaF1 <- dada(derepF1, err=errF, multithread=FALSE)
    dadaR1 <- dada(derepR1, err=errR, multithread=FALSE)
    print(dadaF1)
    # --- merge Pairs [] ---
    # Key functions: mergePairs
    merger1 <- mergePairs(dadaF1, derepF1, dadaR1, derepR1, verbose=TRUE)
    # --- tempfile [] ---
    # Key functions: tempfile, filterAndTrim, derepFastq, dada, mergePairs
    fnF2 <- system.file("extdata", "sam2F.fastq.gz", package="dada2")
    fnR2 <- system.file("extdata", "sam2R.fastq.gz", package="dada2")
    filtF2 <- tempfile(fileext=".fastq.gz")
    # --- make Sequence Table [] ---
    # Key functions: makeSequenceTable
    seqtab <- makeSequenceTable(list(merger1, merger2))
    seqtab.nochim <- removeBimeraDenovo(seqtab, verbose=TRUE)
    dim(seqtab.nochim)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dada2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dada2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dada2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DADA2:", paste0("    dada2: ", packageVersion("dada2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dada2_results.csv
    touch ${prefix}_dada2_output.rds
    echo "BIOC_DADA2:" > versions.yml
    echo "    dada2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DADA2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DADA2(ch_input)

    emit:
    results  = BIOC_DADA2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DADA2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DADA2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DADA2.out.versions  // channel: path(versions.yml)
}
