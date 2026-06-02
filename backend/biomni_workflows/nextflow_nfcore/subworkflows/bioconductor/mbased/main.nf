#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MBASED
// The package implements MBASED algorithm for detecting allele-specific gene expression from RNA count
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MBASED/inst/doc/MBASED.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MBASED")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MBASED {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mbased"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mbased:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mbased:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mbased_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mbased_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mbased_plots.pdf"),    emit: plots, optional: true
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
    library(MulticoreParam)
    library(SerialParam)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Example1S Sim Phased [] ---
    # Key functions: args, GRanges, IRanges
    set.seed(988482)
    library(MBASED)
    ##a quick look at the main function
    args(runMBASED)
    ## create GRanges object for SNVs of interest.
    # --- Example1S Sim Unphased [] ---
    # Key functions: summarizeASEResults_1s, runMBASED, SerialParam
    summarizeASEResults_1s(
      runMBASED(
        ASESummarizedExperiment=mySample,
        isPhased=FALSE,
        numSim=10^6,
    # --- Example1S Nosim [] ---
    # Key functions: summarizeASEResults_1s, runMBASED, SerialParam
    ##re-run analysis without simulations
    summarizeASEResults_1s(
      runMBASED(
        ASESummarizedExperiment=mySample,
        isPhased=FALSE,
    # --- Example1S Parallel [] ---
    # Key functions: summarizeASEResults_1s, runMBASED, MulticoreParam, time, SerialParam
    ## ##re-run analysis while parallelizing computations
    ## ## results are same as before
    ## ## with some random flactuations due to simulations
    ## summarizeASEResults_1s(
    ##   runMBASED(
    # --- Binomtestillustration [] ---
    # Key functions: test
    binom.test(25, 45, 0.5, 'two.sided')$p.value
    # --- Isoform Specific [] ---
    # Key functions: SummarizedExperiment, summarizeASEResults_1s, runMBASED, MulticoreParam
    isoSpecificExampleSNVs <- mySNVs[2:4,]
    ## create input RangedSummarizedExperiment object
    isoSpecificExample <- SummarizedExperiment(
      assays=list(
        lociAllele1Counts=matrix(
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, IRanges, SummarizedExperiment
    mySNVs_2s <- GRanges(
      seqnames=c('chr1', 'chr2', 'chr2', 'chr2', 'chr3'),
      ranges=IRanges(start=c(100, 1000, 1100, 1200, 2000), width=1),
      aseID=c('gene1', rep('gene2', 3), 'gene3'),
      allele1=c('G', 'A', 'C', 'A', 'T'),
    # --- Two Sample Asymmetric [] ---
    # Key functions: tumor, normal, GRanges, IRanges, summarizeASEResults_2s, runMBASED
    ## single-SNV gene with strong ASE in tumor (25 vs. 5 reads)
    ## and no ASE in normal (22 vs. 23 reads):
    mySNV <- GRanges(
      seqnames=c('chr1'),
      ranges=IRanges(start=c(100), width=1),
    # --- Example1S Refbias No Adjustment [] ---
    # Key functions: summarizeASEResults_1s, runMBASED, SummarizedExperiment, SerialParam
    mySNVs
    ## run MBASED with default values:
    summarizeASEResults_1s(
      runMBASED(
        SummarizedExperiment(
    # --- Example1S Refbias Adjustment [] ---
    # Key functions: summarizeASEResults_1s, runMBASED, SummarizedExperiment, SerialParam
    ##run the analysis adjusting for pre-existing allelic bias
    summarizeASEResults_1s(
      runMBASED(
        SummarizedExperiment(
          assays=list(
    # --- Overdispersion Example [] ---
    # Key functions: vectorizedRbetabinomMR, summarizeASEResults_1s, runMBASED, SummarizedExperiment
    set.seed(5) ## we chose this seed to get a 'significant' result
    totalAlleleCounts=c(45, 26, 37, 30)
    ## simulate allele1 counts
    allele1Counts <- MBASED:::vectorizedRbetabinomMR(
      n=4,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mbased_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mbased_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mbased_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MBASED:", paste0("    mbased: ", packageVersion("MBASED"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mbased_results.csv
    touch ${prefix}_mbased_output.rds
    echo "BIOC_MBASED:" > versions.yml
    echo "    mbased: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MBASED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MBASED(ch_input)

    emit:
    results  = BIOC_MBASED.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MBASED.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MBASED.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MBASED.out.versions  // channel: path(versions.yml)
}
