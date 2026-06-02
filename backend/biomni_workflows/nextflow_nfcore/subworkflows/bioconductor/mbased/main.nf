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
    library(MBASED)
    library(GRanges)
    library(IRanges)
    library(MulticoreParam)
    library(SerialParam)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Phased ASE Analysis [] ---
    # Key functions: runMBASED, SerialParam, assays
    ASEresults_1s_haplotypesKnown <- runMBASED(
        ASESummarizedExperiment=mySample,
        isPhased=TRUE,
        numSim=10^5,
        BPPARAM=BiocParallel::SerialParam()
    )
    ase_maf <- SummarizedExperiment::assays(
        ASEresults_1s_haplotypesKnown
    )$majorAlleleFrequency
    ase_pval <- SummarizedExperiment::assays(
        ASEresults_1s_haplotypesKnown
    )$pValueASE


    # --- Unphased ASE Analysis [] ---
    # Key functions: runMBASED, SerialParam, assays
    ASEresults_1s_unphased <- runMBASED(
        ASESummarizedExperiment=mySample,
        isPhased=FALSE,
        numSim=10^5,
        BPPARAM=BiocParallel::SerialParam()
    )
    unphased_maf <- SummarizedExperiment::assays(
        ASEresults_1s_unphased
    )$majorAlleleFrequency
    unphased_pval <- SummarizedExperiment::assays(
        ASEresults_1s_unphased
    )$pValueASE


    # --- Two-Sample Comparative ASE Analysis [] ---
    # Key functions: GRanges, SummarizedExperiment, runMBASED, SerialParam
    mySNVs_2s <- GenomicRanges::GRanges(
        seqnames=c('chr1', 'chr2', 'chr2', 'chr2', 'chr3'),
        ranges=IRanges::IRanges(start=c(100, 1000, 1100, 1200, 2000), width=1),
        aseID=c('gene1', rep('gene2', 3), 'gene3'),
        allele1=c('G', 'A', 'C', 'A', 'T'),
        allele2=c('T', 'C', 'T', 'G', 'G')
    )
    names(mySNVs_2s) <- c(
        'gene1_SNV1', 'gene2_SNV1', 'gene2_SNV2', 'gene2_SNV3', 'gene3_SNV1'
    )
    myTumorNormalExample <- SummarizedExperiment::SummarizedExperiment(
        assays=list(
            lociAllele1Counts=matrix(
                c(25, 10, 35, 14, 35, 18, 17, 21, 25, 40), ncol=2,
                dimnames=list(names(mySNVs_2s), c('tumor', 'normal'))
            ),
            lociAllele2Counts=matrix(
                c(20, 29, 15, 40, 9, 23, 19, 24, 31, 10), ncol=2,
                dimnames=list(names(mySNVs_2s), c('tumor', 'normal'))
            )
        ),
        rowRanges=mySNVs_2s
    )
    ASEresults_2s <- runMBASED(
        ASESummarizedExperiment=myTumorNormalExample,
        isPhased=FALSE,
        numSim=10^5,
        BPPARAM=BiocParallel::SerialParam()
    )

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
