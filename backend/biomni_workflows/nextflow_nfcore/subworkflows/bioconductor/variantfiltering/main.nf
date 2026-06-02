#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VariantFiltering
// Filter genetic variants using different criteria such as inheritance model, amino acid change conseq
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VariantFiltering/inst/doc/usingVariantFiltering.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("VariantFiltering")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VARIANTFILTERING {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-variantfiltering"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-variantfiltering:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-variantfiltering:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_variantfiltering_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_variantfiltering_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_variantfiltering_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(VariantFiltering)
    library(BamViews)
    library(DataFrame)
    library(jsonlite)

    # --- Parameter Initialization [VariantFilteringParam] ---
    # Key functions: VariantFilteringParam
    vcf_file <- system.file(
        "extdata", 
        "CEU.exon.2010_03.genotypes.vcf.gz", 
        package="VariantFiltering"
    )
    ped_file <- system.file(
        "extdata", 
        "CEU.exon.2010_03.ped", 
        package="VariantFiltering"
    )
    param <- VariantFilteringParam(
        vcfFilename=vcf_file,
        pedFilename=ped_file
    )

    # --- Variant Filtering Execution [variantFiltering] ---
    # Key functions: variantFiltering
    vf_results <- variantFiltering(param)

    # --- Filter Inspection and Adjustment [cutoffs, filters, active] ---
    # Key functions: cutoffs, filters, active
    current_cutoffs <- cutoffs(vf_results)
    cutoffs(vf_results)$MAFs <- 0.05
    active(filters(vf_results))["SOterms"] <- FALSE

    # --- Variant Alignment Visualization [BamViews, bamFiles, plot] ---
    # Key functions: BamViews, bamFiles, plot, samples
    path2bams <- file.path(
        system.file("extdata", package="VariantFiltering"),
        paste0(samples(vf_results), ".subset.bam")
    )
    bv <- BamViews(
        bamPaths=path2bams,
        bamSamples=DataFrame(row.names=samples(vf_results))
    )
    bamFiles(vf_results) <- bv
    plot(vf_results, what="rs6130959", sampleName="NA12892")

    # --- Exporting Filtered Variants [reportVariants] ---
    # Key functions: reportVariants
    filtered_gr <- reportVariants(vf_results, type="GRanges")
    reportVariants(
        vf_results,
        type="tsv",
        file="filtered_variants.tsv"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_variantfiltering_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_variantfiltering_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_variantfiltering_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VARIANTFILTERING:", paste0("    variantfiltering: ", packageVersion("VariantFiltering"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variantfiltering_results.csv
    touch ${prefix}_variantfiltering_output.rds
    echo "BIOC_VARIANTFILTERING:" > versions.yml
    echo "    variantfiltering: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VARIANTFILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VARIANTFILTERING(ch_input)

    emit:
    results  = BIOC_VARIANTFILTERING.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VARIANTFILTERING.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VARIANTFILTERING.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VARIANTFILTERING.out.versions  // channel: path(versions.yml)
}
