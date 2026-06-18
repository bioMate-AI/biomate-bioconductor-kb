#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: variantfiltering — unrelated_individuals_analysis
// Annotate and filter variants from unrelated individuals without assuming an inheritance model.
// Input: CEUtrio.vcf.bgz, NA12878.subset.bam, NA12891.subset.bam, NA12892.subset.bam
// Container: quay.io/biocontainers/bioconductor-variantfiltering:1.46.0--r45h01b2380_0
// R packages: Rsamtools, VariantAnnotation, VariantFiltering
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_VARIANTFILTERING_UNRELATED_INDIVIDUALS_ANALYSIS {
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
    .bm_deps <- c("Rsamtools", "VariantAnnotation", "VariantFiltering")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(VariantAnnotation)
    library(Rsamtools)
    
    # --- Create parameter object using VariantFilteringParam() ---
    # Read the user input VCF file from the working directory
    CEUvcf <- "CEUtrio.vcf.bgz"
    if (!file.exists(CEUvcf)) {
      stop(paste("Required input VCF file not found in working directory:", CEUvcf))
    }
    
    vfpar <- VariantFilteringParam(CEUvcf)
    
    # --- Annotate variants using unrelatedIndividuals() ---
    uind <- unrelatedIndividuals(vfpar)
    
    # --- Summarize annotations using summary() ---
    sum_default <- summary(uind)
    write.csv(sum_default, "summary_default.csv", row.names=FALSE)
    
    sum_bioc <- summary(uind, method="bioc")
    write.csv(sum_bioc, "summary_bioc.csv", row.names=FALSE)
    
    uindSO <- summary(uind, method="SOfull")
    write.csv(uindSO, "summary_SOfull.csv", row.names=FALSE)
    
    all_vars <- allVariants(uind)
    saveRDS(all_vars, "all_variants.rds")
    
    # --- Set BAM files and plot variant support using bamFiles() ---
    # Read the user input BAM files from the working directory
    path2bams <- paste0(samples(uind), ".subset.bam")
    
    if (all(file.exists(path2bams))) {
      bv <- BamViews(bamPaths=path2bams, bamSamples=DataFrame(row.names=samples(uind)))
      bamFiles(uind) <- bv
      
      # Save plot to PDF
      pdf("variant_plot.pdf", width=10, height=8)
      tryCatch({
        plot(uind, what="rs6130959", sampleName="NA12892")
      }, error = function(e) {
        message("Plotting failed: ", e\$message)
      })
      dev.off()
    } else {
      message("One or more BAM files not found in working directory. Skipping BAM visualization.")
    }
    
    # Restrict samples and reset
    samples(uind) <- c("NA12891", "NA12892")
    uind <- resetSamples(uind)
    
    # --- Filter variants by modifying active filters and cutoffs ---
    filters(uind)
    active(filters(uind)) <- TRUE
    change(cutoffs(uind), "SOterms") <- "UTR_variant"
    active(filters(uind))["SOterms"] <- TRUE
    change(cutoffs(uind)\$maxMAF, "popmask") <- FALSE
    change(cutoffs(uind)\$maxMAF, "maxvalue") <- 0.01
    
    # --- Retrieve filtered variants using filteredVariants() ---
    fil_vars <- filteredVariants(uind)
    saveRDS(fil_vars, "filtered_variants.rds")
    
    # --- Export results using reportVariants() ---
    reportVariants(uind, type="csv", file="uind.csv")

    writeLines(c(
        '"BIOC_VARIANTFILTERING_UNRELATED_INDIVIDUALS_ANALYSIS":',
        paste0('        variantfiltering: ', as.character(packageVersion("variantfiltering")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unrelated_individuals_analysis.csv versions.yml
    """
}

workflow BIOC_VARIANTFILTERING_UNRELATED_INDIVIDUALS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CEUtrio.vcf.bgz, NA12878.subset.bam, NA12891.subset.bam, NA12892.subset.bam ] ]

    main:
    BIOC_VARIANTFILTERING_UNRELATED_INDIVIDUALS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_VARIANTFILTERING_UNRELATED_INDIVIDUALS_ANALYSIS.out.tables
    plots    = BIOC_VARIANTFILTERING_UNRELATED_INDIVIDUALS_ANALYSIS.out.plots
    objects  = BIOC_VARIANTFILTERING_UNRELATED_INDIVIDUALS_ANALYSIS.out.objects
    versions = BIOC_VARIANTFILTERING_UNRELATED_INDIVIDUALS_ANALYSIS.out.versions
}
