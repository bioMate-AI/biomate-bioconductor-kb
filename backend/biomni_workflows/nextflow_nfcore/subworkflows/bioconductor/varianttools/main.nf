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
    library(VariantTools)
    library(GRanges)
    library(IRanges)
    library(LungCancerBamFiles)
    library(TP53Genome)
    library(TallyVariantsParam)
    library(VariantCallingFilters)
    library(VariantPostFilters)
    library(VariantQAFilters)
    library(jsonlite)

    # --- Quality Assessment [] ---
    # Key functions: qaVariants, VariantQAFilters, softFilterMatrix
    qa.variants <- qaVariants(tallies)
    qa.filters <- VariantQAFilters()
    qa.summary <- summary(softFilterMatrix(qa.variants))


    # --- Variant Calling [] ---
    # Key functions: VariantCallingFilters, callVariants
    calling.filters <- VariantCallingFilters()
    called.variants <- callVariants(qa.variants, calling.filters)


    # --- Somatic Mutation Calling [] ---
    # Key functions: callSampleSpecificVariants
    somatic <- callSampleSpecificVariants(
        case_bam,
        control_bam,
        tally.param
    )


    # --- Wildtype Calling [] ---
    # Key functions: isIndel, VariantCallingFilters, callWildtype
    called.snvs <- called.variants[!isIndel(called.variants)]
    wildtype <- callWildtype(
        bam_file,
        called.snvs,
        VariantCallingFilters(),
        power = 0.85
    )


    # --- VCF Export [] ---
    # Key functions: sampleNames, mcols, asVCF
    sampleNames(called.variants) <- "Sample_1"
    mcols(called.variants) <- NULL
    vcf <- asVCF(called.variants)

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
