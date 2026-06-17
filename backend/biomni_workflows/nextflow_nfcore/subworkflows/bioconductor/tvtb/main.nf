#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TVTB — vcf_filtering_and_frequency_analysis
// Import VCF data, calculate overall and phenotype-level allele frequencies, apply multi-slot filter rules, and visualize the results.
// Input: chr15.phase3_integrated.vcf.gz, integrated_samples.txt
// Container: quay.io/biocontainers/bioconductor-tvtb:1.36.0--r45hdfd78af_0
// R packages: EnsDb.Hsapiens.v75, GenomicRanges, IRanges, Rsamtools, S4Vectors, VariantAnnotation, knitr, TVTB
// Bioconductor: 3.20 | R: 4.4
// Requires: EnsDb.Hsapiens.v75, GenomicRanges, IRanges, Rsamtools, S4Vectors, TVTB, VariantAnnotation
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define recurrent parameters (genotypes, genomic ranges)
//  * 2. [Visualization & Output] Import phenotypes into a DataFrame and set up VCF import
//  * 3. [Visualization & Output] Import and expand the VCF file into an ExpandedVCF object
//  * 4. [Visualization & Output] Calculate and append overall genotype counts and allele
//  * 5. [Visualization & Output] Calculate and append phenotype-level genotype counts and
//  * 6. [Visualization & Output] Define specialized VCF filter rules using VcfFixedRules,
//  * 7. [Visualization & Output] Evaluate the filter rules on the VCF object and save
//  * 8. [Visualization & Output] Visualize the allele frequencies across genomic ranges

nextflow.enable.dsl = 2

process BIOC_TVTB_VCF_FILTERING_AND_FREQUENCY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("EnsDb.Hsapiens.v75", "GenomicRanges", "IRanges", "Rsamtools", "S4Vectors", "VariantAnnotation", "knitr", "TVTB")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(TVTB)
    library(VariantAnnotation)
    library(Rsamtools)
    library(GenomicRanges)
    library(S4Vectors)
    library(EnsDb.Hsapiens.v75)
    
    # --- Define recurrent parameters (genotypes, genomic ranges) ---
    tparam <- TVTBparam(Genotypes(
        ref = "0|0",
        het = c("0|1", "1|0", "0|2", "2|0", "1|2", "2|1"),
        alt = c("1|1", "2|2")),
        ranges = GenomicRanges::GRangesList(
            SLC24A5 = GenomicRanges::GRanges(
                seqnames = "15",
                IRanges::IRanges(
                    start = 48413170, end = 48434757)
                )
            )
        )
    
    # --- Import phenotypes into a DataFrame and set up VCF import ---
    phenoFile <- "integrated_samples.txt"
    phenotypes <- S4Vectors::DataFrame(
        read.table(file = phenoFile, header = TRUE, row.names = 1))
    
    vcfFile <- "chr15.phase3_integrated.vcf.gz"
    tabixVcf <- Rsamtools::TabixFile(file = vcfFile)
    
    VariantAnnotation::vcfInfo(svp(tparam)) <- vep(tparam)
    VariantAnnotation::vcfGeno(svp(tparam)) <- "GT"
    
    # --- Import and expand the VCF file into an ExpandedVCF object ---
    vcf <- VariantAnnotation::readVcf(
        tabixVcf, param = tparam, colData = phenotypes)
    vcf <- VariantAnnotation::expand(x = vcf, row.names = TRUE)
    
    # --- Calculate and append overall genotype counts and allele ---
    vcf <- addOverallFrequencies(vcf = vcf)
    
    # --- Calculate and append phenotype-level genotype counts and ---
    vcf <- addPhenoLevelFrequencies(
        vcf = vcf, pheno = "super_pop", level = "AFR")
    vcf <- addFrequencies(
        vcf,
        list(super_pop = c("EUR", "SAS", "EAS", "AMR"))
    )
    vcf <- addFrequencies(vcf, "pop")
    
    # --- Define specialized VCF filter rules using VcfFixedRules, ---
    fixedR <- VcfFixedRules(list(
        pass = expression(FILTER == "PASS"),
        qual = expression(QUAL > 20)
    ))
    infoR <- VcfInfoRules(
        exprs = list(
            rare = expression(MAF < 0.01 & MAF > 0),
            common = expression(MAF > 0.05),
            mac_ge3 = expression(HET + 2*ALT >= 3)),
        active = c(TRUE, TRUE, FALSE)
    )
    vepR <- VcfVepRules(exprs = list(
        missense = expression(Consequence %in% c("missense_variant")),
        CADD_gt15 = expression(CADD_PHRED > 15)
        ))
    vcfRules <- VcfFilterRules(fixedR, infoR, vepR)
    active(vcfRules)["CADD_gt15"] <- FALSE
    
    # --- Evaluate the filter rules on the VCF object and save ---
    sum_infoR <- summary(eval(expr = infoR, envir = vcf))
    sum_vcfRules <- summary(eval(expr = vcfRules, envir = vcf))
    sum_sep_vcfRules <- summary(evalSeparately(expr = vcfRules, envir = vcf))
    
    # Write evaluation summaries to a text file
    sink("filter_evaluation_summaries.txt")
    cat("=== Summary of eval(infoR) ===\n")
    print(sum_infoR)
    cat("\n=== Summary of eval(vcfRules) ===\n")
    print(sum_vcfRules)
    cat("\n=== Summary of evalSeparately(vcfRules) ===\n")
    print(sum_sep_vcfRules)
    sink()
    
    # --- Visualize the allele frequencies across genomic ranges ---
    # Save plotInfo visualization
    pdf("plotInfo_AAF.pdf", width = 10, height = 8)
    p1 <- plotInfo(
        subsetByFilter(vcf, vcfRules["common"]), "AAF",
        range(GenomicRanges::granges(vcf)),
        EnsDb.Hsapiens.v75::EnsDb.Hsapiens.v75,
        "super_pop",
        zero.rm = FALSE
    )
    if (!is.null(p1)) print(p1)
    dev.off()
    
    # Save pairsInfo visualization
    pdf("pairsInfo_AAF.pdf", width = 10, height = 10)
    p2 <- pairsInfo(subsetByFilter(vcf, vcfRules["common"]), "AAF", "super_pop")
    if (!is.null(p2)) print(p2)
    dev.off()
    
    # Save the final processed VCF object as an RDS file
    saveRDS(vcf, "processed_vcf.rds")

    writeLines(c(
        '"BIOC_TVTB_VCF_FILTERING_AND_FREQUENCY_ANALYSIS":',
        paste0('    TVTB: ', as.character(packageVersion('TVTB')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vcf_filtering_and_frequency_analysis.csv versions.yml
    """
}

workflow BIOC_TVTB_VCF_FILTERING_AND_FREQUENCY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chr15.phase3_integrated.vcf.gz, integrated_samples.txt ] ]

    main:
    BIOC_TVTB_VCF_FILTERING_AND_FREQUENCY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TVTB_VCF_FILTERING_AND_FREQUENCY_ANALYSIS.out.tables
    plots    = BIOC_TVTB_VCF_FILTERING_AND_FREQUENCY_ANALYSIS.out.plots
    objects  = BIOC_TVTB_VCF_FILTERING_AND_FREQUENCY_ANALYSIS.out.objects
    versions = BIOC_TVTB_VCF_FILTERING_AND_FREQUENCY_ANALYSIS.out.versions
}
