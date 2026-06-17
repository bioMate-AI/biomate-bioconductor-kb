#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PureCN — standard_purecn_pipeline
// Run the complete PureCN pipeline using internal coverage calculation, normalization, and segmentation to estimate purity, ploidy, and classify variants.
// Input: baits.bed, reference.fa, mappability.bigWig, tumor.bam, normal_coverages.list, normal_panel.vcf, tumor_mutect.vcf
// Container: quay.io/biocontainers/bioconductor-purecn:2.16.0--r45hdfd78af_0
// R packages: VariantAnnotation, PureCN, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: PureCN, VariantAnnotation, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess intervals and calculate GC-content using preprocessIntervals
//  * 2. [Core Analysis] Calculate BAM coverage for tumor and normal samples using calculateBamCoverageByInterval
//  * 3. [Core Analysis] Correct library-specific coverage biases using correctCoverageBias
//  * 4. [Input & Preparation] Build a normal database for coverage normalization using createNormalDatabase
//  * 5. [Core Analysis] Calculate tangent normal coverage using calculateTangentNormal
//  * 6. [Core Analysis] Pre-calculate variant mapping biases from a normal panel VCF using calculateMappingBiasVcf
//  * 7. [Core Analysis] Run absolute copy number, purity, and ploidy estimation using runAbsoluteCN
//  * 8. [Core Analysis] Predict somatic status and cellular fraction using predictSomatic
//  * 9. [Core Analysis] Call gene-level alterations and LOH using callAlterations, callAmplificationsInLowPurity, and callLOH
//  * 10. [Input & Preparation] Create and read curation files for manual verification using createCurationFile and readCurationFile

nextflow.enable.dsl = 2

process BIOC_PURECN_STANDARD_PURECN_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("VariantAnnotation", "PureCN", "rtracklayer")
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
            library(PureCN)
            library(rtracklayer)
            library(VariantAnnotation)
            
            # Define input files from the working directory
            bed.file <- "baits.bed"
            reference.file <- "reference.fa"
            mappability.file <- "mappability.bigWig"
            bam.file <- "tumor.bam"
            normal.panel.vcf.file <- "normal_panel.vcf"
            vcf.file <- "tumor_mutect.vcf"
            
            # Read the list of normal coverage files
            normal.coverage.files <- readLines("normal_coverages.list")
            normal.coverage.file <- normal.coverage.files[1]
            
            # 1. Preprocess intervals and calculate GC-content
            intervals <- import(bed.file)
            mappability <- import(mappability.file)
            
            preprocessIntervals(intervals, reference.file, 
                mappability = mappability, output.file = "ex2_gc_file.txt")
            
            interval.file <- "ex2_gc_file.txt"
            
            # 2. Calculate BAM coverage for the tumor sample
            calculateBamCoverageByInterval(bam.file = bam.file, 
             interval.file = interval.file, output.file = "ex1_coverage.txt")
            
            tumor.coverage.file <- "ex1_coverage.txt"
            
            # 3. Correct library-specific coverage biases for the tumor sample
            correctCoverageBias(tumor.coverage.file, interval.file, 
                output.file = "tumor_coverage_loess.txt.gz", plot.bias = TRUE)
            
            tumor.coverage.file <- "tumor_coverage_loess.txt.gz"
            
            # 4. Build a normal database for coverage normalization
            normalDB <- createNormalDatabase(normal.coverage.files)
            saveRDS(normalDB, file = "normalDB.rds")
            
            # 5. Calculate tangent normal coverage
            normalDB <- readRDS("normalDB.rds")
            pool <- calculateTangentNormal(tumor.coverage.file, normalDB)
            
            # 6. Pre-calculate variant mapping biases from a normal panel VCF
            bias <- calculateMappingBiasVcf(normal.panel.vcf.file, genome = "hg19")
            saveRDS(bias, "mapping_bias.rds")
            mapping.bias.file <- "mapping_bias.rds"
            
            # 7. Run absolute copy number, purity, and ploidy estimation
            ret <-runAbsoluteCN(normal.coverage.file = pool,
                tumor.coverage.file = tumor.coverage.file, vcf.file = vcf.file, 
                genome = "hg19", sampleid = "Sample1", 
                interval.file = interval.file, normalDB = normalDB,
                args.setMappingBiasVcf=list(
                    mapping.bias.file = mapping.bias.file
                ),
                post.optimize = FALSE, plot.cnv = FALSE, verbose = FALSE)
            
            file.rds <- "Sample1_PureCN.rds"
            saveRDS(ret, file = file.rds)
            
            # Generate diagnostic plots
            pdf("Sample1_PureCN.pdf", width = 10, height = 11)
            plotAbs(ret, type = "all")
            dev.off()
            
            # 8. Predict somatic status and cellular fraction
            somatic_predictions <- predictSomatic(ret)
            write.csv(somatic_predictions, "Sample1_somatic_predictions.csv", row.names = FALSE)
            
            vcf <- predictSomatic(ret, return.vcf = TRUE)
            writeVcf(vcf, file = "Sample1_PureCN.vcf")
            
            # 9. Call alterations, amplifications, and LOH
            gene.calls <- callAlterations(ret)
            gene.calls.zscore <- callAmplificationsInLowPurity(ret, normalDB)
            loh <- callLOH(ret)
            
            # 10. Create and read curation file
            createCurationFile(file.rds)
            ret <- readCurationFile(file.rds)

    writeLines(c(
        '"BIOC_PURECN_STANDARD_PURECN_PIPELINE":',
        paste0('    PureCN: ', as.character(packageVersion('PureCN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_purecn_pipeline.csv versions.yml
    """
}

workflow BIOC_PURECN_STANDARD_PURECN_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ baits.bed, reference.fa, mappability.bigWig, tumor.bam, normal_coverages.list, normal_panel.vcf, tumor_mutect.vcf ] ]

    main:
    BIOC_PURECN_STANDARD_PURECN_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PURECN_STANDARD_PURECN_PIPELINE.out.tables
    plots    = BIOC_PURECN_STANDARD_PURECN_PIPELINE.out.plots
    objects  = BIOC_PURECN_STANDARD_PURECN_PIPELINE.out.objects
    versions = BIOC_PURECN_STANDARD_PURECN_PIPELINE.out.versions
}
