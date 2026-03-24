#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: StructuralVariantAnnotation
// StructuralVariantAnnotation provides a framework for analysis of structural variants within the Bioc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/StructuralVariantAnnotation/inst/doc/vignettes.R
// Upstream  : dplyr, ggplot2, rtracklayer, ggbio
// Downstream: svaNUMT, svaRetro
//
// Install: BiocManager::install("StructuralVariantAnnotation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STRUCTURALVARIANTANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-structuralvariantannotation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-structuralvariantannotation:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-structuralvariantannotation:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_structuralvariantannotation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_structuralvariantannotation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_structuralvariantannotation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(StructuralVariantAnnotation)
    library(jsonlite)

    # --- Read VCF variant file [] ---
    # Key functions: readVcf
    suppressPackageStartupMessages(library(StructuralVariantAnnotation))
    vcf <- VariantAnnotation::readVcf(system.file("extdata", "representations.vcf", package = "StructuralVariantAnnotation"))
    gr <- c(breakpointRanges(vcf), breakendRanges(vcf))
    # --- Read VCF variant file [] ---
    # Key functions: readVcf, breakpointRanges, partner, breakendRanges
    library(StructuralVariantAnnotation)
    vcf <- VariantAnnotation::readVcf(system.file("extdata", "gridss.vcf", package = "StructuralVariantAnnotation"))
    gr <- breakpointRanges(vcf)
    # --- add to.gr [] ---
    # Key functions: seqlevels, mcols
    suppressPackageStartupMessages(require(ggbio))
    gr.circos <- colo829_bpgr[seqnames(colo829_bpgr) %in% seqlevels(biovizBase::hg19sub)]
    seqlevels(gr.circos) <- seqlevels(biovizBase::hg19sub)
    # --- Genomic visualization (ggbio) [] ---
    # Key functions: ggbio, circle
    p <- ggbio() +
    circle(gr.circos, geom="link", linked.to="to.gr") +
    circle(biovizBase::hg19sub, geom='ideo', fill='gray70') +

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_structuralvariantannotation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_structuralvariantannotation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_structuralvariantannotation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STRUCTURALVARIANTANNOTATION:", paste0("    structuralvariantannotation: ", packageVersion("StructuralVariantAnnotation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_structuralvariantannotation_results.csv
    touch ${prefix}_structuralvariantannotation_output.rds
    echo "BIOC_STRUCTURALVARIANTANNOTATION:" > versions.yml
    echo "    structuralvariantannotation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STRUCTURALVARIANTANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STRUCTURALVARIANTANNOTATION(ch_input)

    emit:
    results  = BIOC_STRUCTURALVARIANTANNOTATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STRUCTURALVARIANTANNOTATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STRUCTURALVARIANTANNOTATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STRUCTURALVARIANTANNOTATION.out.versions  // channel: path(versions.yml)
}
