#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TVTB
// The package provides S4 classes and methods to filter, summarise and visualise genetic variation dat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TVTB/inst/doc/Introduction.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("TVTB")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TVTB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tvtb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tvtb:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tvtb:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(vcf)

    output:
    tuple val(meta), path("${meta.id}_tvtb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tvtb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tvtb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TVTB)
    library(DataFrame)
    library(IRanges)
    library(TVTBparam)
    library(TabixFile)
    library(jsonlite)

    # --- VCF Import and Expansion [] ---
    # Key functions: readVcf, expand
    phenoFile <- system.file(
        "extdata", "integrated_samples.txt", package = "TVTB"
    )
    phenotypes <- S4Vectors::DataFrame(
        read.table(file = phenoFile, header = TRUE, row.names = 1)
    )
    vcfFile <- system.file(
        "extdata", "chr15.phase3_integrated.vcf.gz", package = "TVTB"
    )
    tabixVcf <- Rsamtools::TabixFile(file = vcfFile)
    vcf <- VariantAnnotation::readVcf(
        tabixVcf, param = tparam, colData = phenotypes
    )
    vcf <- VariantAnnotation::expand(x = vcf, row.names = TRUE)


    # --- Frequency Calculation [] ---
    # Key functions: addOverallFrequencies, addPhenoLevelFrequencies, addFrequencies
    vcf <- addOverallFrequencies(vcf = vcf)
    vcf <- addFrequencies(vcf = vcf, force = TRUE)
    vcf <- addPhenoLevelFrequencies(
        vcf = vcf, pheno = "super_pop", level = "AFR"
    )
    vcf <- addFrequencies(
        vcf,
        list(super_pop = c("EUR", "SAS", "EAS", "AMR"))
    )
    vcf <- addFrequencies(vcf, "pop")


    # --- Filter Rules Definition [] ---
    # Key functions: VcfFixedRules, VcfInfoRules, VcfVepRules, VcfFilterRules
    fixedR <- VcfFixedRules(list(
        pass = expression(FILTER == "PASS"),
        qual = expression(QUAL > 20)
    ))
    infoR <- VcfInfoRules(
        exprs = list(
            rare = expression(MAF < 0.01 & MAF > 0),
            common = expression(MAF > 0.05),
            mac_ge3 = expression(HET + 2*ALT >= 3)
        ),
        active = c(TRUE, TRUE, FALSE)
    )
    vepR <- VcfVepRules(exprs = list(
        missense = expression(Consequence %in% c("missense_variant")),
        CADD_gt15 = expression(CADD_PHRED > 15)
    ))
    vcfRules <- VcfFilterRules(fixedR, infoR, vepR)


    # --- Filter Evaluation and Subsetting [] ---
    # Key functions: eval, evalSeparately, subsetByFilter
    info_summary <- eval(expr = infoR, envir = vcf)
    rules_summary <- eval(expr = vcfRules, envir = vcf)
    sep_summary <- evalSeparately(expr = vcfRules, envir = vcf)
    vcf_filtered <- subsetByFilter(vcf, vcfRules["common"])


    # --- Visualization [] ---
    # Key functions: plotInfo, pairsInfo
    plotInfo(
        subsetByFilter(vcf, vcfRules["common"]), "AAF",
        range(GenomicRanges::granges(vcf)),
        EnsDb.Hsapiens.v75::EnsDb.Hsapiens.v75,
        "super_pop",
        zero.rm = FALSE
    )
    pairsInfo(
        subsetByFilter(vcf, vcfRules["common"]), "AAF", "super_pop"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tvtb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tvtb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tvtb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TVTB:", paste0("    tvtb: ", packageVersion("TVTB"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tvtb_results.csv
    touch ${prefix}_tvtb_output.rds
    echo "BIOC_TVTB:" > versions.yml
    echo "    tvtb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TVTB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(vcf) ]

    main:
    BIOC_TVTB(ch_input)

    emit:
    results  = BIOC_TVTB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TVTB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TVTB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TVTB.out.versions  // channel: path(versions.yml)
}
