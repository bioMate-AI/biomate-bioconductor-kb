#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: regioneR
// regioneR offers a statistical framework based on customizable permutation tests to assess the associ
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/regioneR/inst/doc/regioneR.R
// Upstream  : knitr
// Downstream: karyoploteR, regioneReloaded
//
// Install: BiocManager::install("regioneR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGIONER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regioner"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regioner:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-regioner:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_regioner_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regioner_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regioner_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(regioneR)
    library(jsonlite)

    # --- Createrandomregions [] ---
    # Key functions: createRandomRegions, numOverlaps, randomizeRegions
    ---------------------------------------------------------------------
      A <- createRandomRegions(nregions=50, length.mean=5000000, length.sd=3000000)
      B <- c(A[1:25], createRandomRegions(nregions=25, length.mean=500000, length.sd=30000))
      numOverlaps(A, B, count.once=TRUE)
      numOverlaps(randomizeRegions(A), B, count.once=TRUE)
    # --- Overlappermtest [] ---
    # Key functions: overlapPermTest
    ---------------------------------------------------------------------
      pt <- overlapPermTest(A=A, B=B, ntimes=50)
      pt
    # --- Togranges [] ---
    # Key functions: toGRanges
    ---------------------------------------------------------------------
      special <- toGRanges(system.file("extdata", "my.special.genes.txt", package="regioneR"))
      all.genes <- toGRanges(system.file("extdata", "all.genes.txt", package="regioneR"))
      altered <- toGRanges(system.file("extdata", "my.altered.regions.txt", package="regioneR"))
      length(special)
    # --- Numoverlaps [] ---
    # Key functions: numOverlaps
    ---------------------------------------------------------------------
      numOverlaps(special, altered)
    # --- Resampleregions [] ---
    # Key functions: resampleRegions
    ---------------------------------------------------------------------
      random.RS <- resampleRegions(special, universe=all.genes)
      random.RS
    # --- Resampleregions [] ---
    # Key functions: resampleRegions, numOverlaps
    ---------------------------------------------------------------------
      random.RS <- resampleRegions(special, universe=all.genes)
      numOverlaps(random.RS, altered)
      random.RS <- resampleRegions(special, universe=all.genes)
      numOverlaps(random.RS, altered)
    # --- Permtest [] ---
    # Key functions: permTest
    ---------------------------------------------------------------------
      pt <- permTest(A=special, ntimes=50, randomize.function=resampleRegions, universe=all.genes,
      evaluate.function=numOverlaps, B=altered, verbose=FALSE)
    # --- Togranges [] ---
    # Key functions: toGRanges, frame
    ---------------------------------------------------------------------
      A <- toGRanges(data.frame(chr=c("chr1", "chr1", "chr1"), start=c(20000, 50000, 100000), end=c(22000, 70000, 400000)))
    # --- Randomizeregions [] ---
    # Key functions: randomizeRegions
    ---------------------------------------------------------------------
      randomizeRegions(A, genome="hg19")
    # --- Circularrandomizeregions [] ---
    # Key functions: circularRandomizeRegions
    ---------------------------------------------------------------------
    circularRandomizeRegions(A, genome="hg19", mask=NA)
    # --- Function [] ---
    # Key functions: toGRanges, getSeq, alphabetFrequency, width
    ---------------------------------------------------------------------
    gcContent <- function(A, bsgenome, ...) {
    A <- toGRanges(A)
    reg.seqs <- getSeq(bsgenome, A)
    base.frequency <- alphabetFrequency(reg.seqs)
    # --- Function [] ---
    # Key functions: toGRanges, mcols, sample
    ---------------------------------------------------------------------
    permuteRegionsMetadata <- function(A, ...) {
    A <- toGRanges(A)
    mcols(A)[,1] <- mcols(A)[sample(length(A)),1]
    return(A)
    # --- Createrandomregions [] ---
    # Key functions: createRandomRegions, overlapPermTest
    ---------------------------------------------------------------------
    A <- createRandomRegions(nregions=50, length.mean=5000000, length.sd=3000000)
    B <- c(A[1:25], createRandomRegions(nregions=25, length.mean=500000, length.sd=30000))
    #Without mc.set.seed=FALSE
    set.seed(123)
    # --- Frame [] ---
    # Key functions: frame, toGRanges
    ---------------------------------------------------------------------
    A <- data.frame(chr=1, start=c(1,15,24), end=c(10,20,30),  x=c(1,2,3), y=c("a","b","c"))
    B <- toGRanges(A)
    B
    # --- Todataframe [] ---
    # Key functions: toDataframe
    ---------------------------------------------------------------------
    toDataframe(B)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regioner_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regioner_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regioner_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGIONER:", paste0("    regioner: ", packageVersion("regioneR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regioner_results.csv
    touch ${prefix}_regioner_output.rds
    echo "BIOC_REGIONER:" > versions.yml
    echo "    regioner: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGIONER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REGIONER(ch_input)

    emit:
    results  = BIOC_REGIONER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGIONER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGIONER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGIONER.out.versions  // channel: path(versions.yml)
}
