#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VariantTools
// Explore, diagnose, and compare variant calls using filters.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VariantTools/inst/doc/VariantTools.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("VariantTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VARIANTTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-varianttools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-varianttools:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-varianttools:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(vcf_object)

    output:
    tuple val(meta), path("${meta.id}_varianttools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_varianttools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_varianttools_plots.pdf"),    emit: plots, optional: true
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
    library(LungCancerBamFiles)
    library(TP53Genome)
    library(TallyVariantsParam)
    library(VariantCallingFilters)
    library(VariantPostFilters)
    library(VariantQAFilters)
    library(jsonlite)

    # --- Callvariants [] ---
    # Key functions: LungCancerBamFiles, requireNamespace, exonsOnTP53Genome, TallyVariantsParam, TP53Genome
    library(VariantTools)
    bams <- LungCancerLines::LungCancerBamFiles()
    bam <- bams$H1993
    if (requireNamespace("gmapR", quietly=TRUE)) {
        p53 <- gmapR:::exonsOnTP53Genome("TP53")
    # --- Callvariants Postfilter [] ---
    # Key functions: postFilterVariants
    pf.variants <- postFilterVariants(called.variants)
    # --- Callvariants Exonic [] ---
    # Key functions: subsetByOverlaps
    subsetByOverlaps(called.variants, p53, ignore.strand = TRUE)
    # --- Tallyvariants [] ---
    # Key functions: requireNamespace, tallyVariants
    if (requireNamespace("gmapR", quietly=TRUE)) {
        tallies_H1993 <- tallyVariants(bam, tally.param)
    }
    # --- Qavariants [] ---
    # Key functions: qaVariants, softFilterMatrix
    qa.variants <- qaVariants(tallies_H1993)
    summary(softFilterMatrix(qa.variants))
    # --- Callvariants [] ---
    # Key functions: callVariants
    called.variants <- callVariants(qa.variants)
    # --- Variantqafilters [] ---
    # Key functions: VariantQAFilters
    qa.filters <- VariantQAFilters()
    # --- Variantqafilters Subset [] ---
    # Key functions: subsetByFilter
    qa.variants <- subsetByFilter(tallies_H1993, qa.filters)
    # --- Variantqafilters Fisherstrandp [] ---
    # Key functions: VariantQAFilters
    qa.filters.custom <- VariantQAFilters(fisher.strand.p.value = 1e-4)
    summary(qa.filters.custom, tallies_H1993)
    # --- Variantqafilters Compare [] ---
    # Key functions: eval
    fs.original <- eval(qa.filters["fisherStrand"], tallies_H1993)
    fs.custom <- eval(qa.filters.custom["fisherStrand"], tallies_H1993)
    tallies_H1993[fs.original != fs.custom]
    # --- Variantqafilters Mask [] ---
    # Key functions: requireNamespace, GRanges, IRanges, tallyVariants
    if (requireNamespace("gmapR", quietly=TRUE)) {
        tally.param@mask <- GRanges("TP53", IRanges(1010000, width=10000))
        tallies_masked <- tallyVariants(bam, tally.param)
    }
    # --- Variantcallingfilters [] ---
    # Key functions: VariantCallingFilters
    calling.filters <- VariantCallingFilters()
    summary(calling.filters, qa.variants)
    # --- Post Filter [] ---
    # Key functions: VariantPostFilters
    post.filters <- VariantPostFilters()
    summary(post.filters, qa.variants)
    # --- Post Filter Whitelist [] ---
    # Key functions: VariantPostFilters
    post.filters <- VariantPostFilters(whitelist = called.variants)
    summary(post.filters, qa.variants)
    # --- Callsomaticmutations [] ---
    # Key functions: requireNamespace, callSampleSpecificVariants
    if (requireNamespace("gmapR", quietly=TRUE)) {
        tally.param@bamTallyParam@indels <- FALSE
        somatic <- callSampleSpecificVariants(bams$H1993, bams$H2073,
                                              tally.param)
    } else {

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_varianttools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_varianttools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_varianttools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VARIANTTOOLS:", paste0("    varianttools: ", packageVersion("VariantTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_varianttools_results.csv
    touch ${prefix}_varianttools_output.rds
    echo "BIOC_VARIANTTOOLS:" > versions.yml
    echo "    varianttools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VARIANTTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(vcf_object) ]

    main:
    BIOC_VARIANTTOOLS(ch_input)

    emit:
    results  = BIOC_VARIANTTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VARIANTTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VARIANTTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VARIANTTOOLS.out.versions  // channel: path(versions.yml)
}
