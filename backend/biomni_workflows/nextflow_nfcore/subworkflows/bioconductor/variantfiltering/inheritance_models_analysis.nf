#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: variantfiltering — inheritance_models_analysis
// Filter variants that segregate according to specific inheritance models using pedigree information.
// Input: CEUtrio.vcf.bgz, CEUtrio.ped
// Container: quay.io/biocontainers/bioconductor-variantfiltering:1.46.0--r45h01b2380_0
// R packages: VariantFiltering
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VARIANTFILTERING_INHERITANCE_MODELS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-variantfiltering:1.46.0--r45h01b2380_0"

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
    .bm_deps <- c("VariantFiltering")
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
    library(VariantFiltering)
    
    # Define input files in the working directory
    CEUvcf <- "CEUtrio.vcf.bgz"
    CEUped <- "CEUtrio.ped"
    
    # Verify input files exist
    if (!file.exists(CEUvcf)) {
      stop(paste("Required input VCF file not found in working directory:", CEUvcf))
    }
    if (!file.exists(CEUped)) {
      stop(paste("Required input PED file not found in working directory:", CEUped))
    }
    
    # 1. Create parameter object with both VCF and PED files
    message("Initializing VariantFilteringParam with input files...")
    param <- VariantFilteringParam(vcfFilenames=CEUvcf, pedFilename=CEUped)
    
    # 2. Filter variants using inheritance model functions
    # We will run the different inheritance models, generate summaries, and save the results.
    
    # Autosomal Recessive Homozygous
    message("Running Autosomal Recessive Homozygous model...")
    arh <- tryCatch({
      res <- autosomalRecessiveHomozygous(param)
      saveRDS(res, "autosomalRecessiveHomozygous.rds")
      write.csv(summary(res), "autosomalRecessiveHomozygous_summary.csv", row.names=FALSE)
      try(reportVariants(res, type="csv", file="autosomalRecessiveHomozygous_variants.csv"))
      res
    }, error = function(e) {
      message("Autosomal Recessive Homozygous analysis failed or returned no variants: ", e\$message)
      NULL
    })
    
    # Autosomal Recessive Heterozygous (Compound Heterozygous)
    message("Running Autosomal Recessive Heterozygous model...")
    areh <- tryCatch({
      res <- autosomalRecessiveHeterozygous(param)
      saveRDS(res, "autosomalRecessiveHeterozygous.rds")
      write.csv(summary(res), "autosomalRecessiveHeterozygous_summary.csv", row.names=FALSE)
      try(reportVariants(res, type="csv", file="autosomalRecessiveHeterozygous_variants.csv"))
      res
    }, error = function(e) {
      message("Autosomal Recessive Heterozygous analysis failed or returned no variants: ", e\$message)
      NULL
    })
    
    # Autosomal Dominant
    message("Running Autosomal Dominant model...")
    ad <- tryCatch({
      res <- autosomalDominant(param)
      saveRDS(res, "autosomalDominant.rds")
      write.csv(summary(res), "autosomalDominant_summary.csv", row.names=FALSE)
      try(reportVariants(res, type="csv", file="autosomalDominant_variants.csv"))
      res
    }, error = function(e) {
      message("Autosomal Dominant analysis failed or returned no variants: ", e\$message)
      NULL
    })
    
    # X-Linked
    message("Running X-Linked model...")
    xl <- tryCatch({
      res <- xLinked(param)
      saveRDS(res, "xLinked.rds")
      write.csv(summary(res), "xLinked_summary.csv", row.names=FALSE)
      try(reportVariants(res, type="csv", file="xLinked_variants.csv"))
      res
    }, error = function(e) {
      message("X-Linked analysis failed or returned no variants: ", e\$message)
      NULL
    })
    
    # De Novo
    message("Running De Novo model...")
    dn <- tryCatch({
      res <- deNovo(param)
      saveRDS(res, "deNovo.rds")
      write.csv(summary(res), "deNovo_summary.csv", row.names=FALSE)
      try(reportVariants(res, type="csv", file="deNovo_variants.csv"))
      res
    }, error = function(e) {
      message("De Novo analysis failed or returned no variants: ", e\$message)
      NULL
    })
    
    message("VariantFiltering inheritance models analysis pipeline completed.")

    writeLines(c(
        '"BIOC_VARIANTFILTERING_INHERITANCE_MODELS_ANALYSIS":',
        paste0('        variantfiltering: ', as.character(packageVersion("variantfiltering")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inheritance_models_analysis.csv versions.yml
    """
}

workflow BIOC_VARIANTFILTERING_INHERITANCE_MODELS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CEUtrio.vcf.bgz, CEUtrio.ped ] ]

    main:
    BIOC_VARIANTFILTERING_INHERITANCE_MODELS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_VARIANTFILTERING_INHERITANCE_MODELS_ANALYSIS.out.tables
    plots    = BIOC_VARIANTFILTERING_INHERITANCE_MODELS_ANALYSIS.out.plots
    objects  = BIOC_VARIANTFILTERING_INHERITANCE_MODELS_ANALYSIS.out.objects
    versions = BIOC_VARIANTFILTERING_INHERITANCE_MODELS_ANALYSIS.out.versions
}
