#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: variantfiltering — unrelated_individuals_analysis
// Annotate and filter variants from unrelated individuals without assuming an inheritance model.
// Input: CEUtrio.vcf.bgz, NA12878.subset.bam, NA12891.subset.bam, NA12892.subset.bam
// Container: quay.io/biocontainers/bioconductor-variantfiltering:1.46.0--r45h01b2380_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

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
    .bm_deps <- c("Rsamtools", "VariantAnnotation", "variantfiltering")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(VariantFiltering)
    library(VariantAnnotation)
    library(Rsamtools)
    
    # 1. Create parameter object using VariantFilteringParam()
    # Read the user input VCF file from the working directory
    CEUvcf <- "CEUtrio.vcf.bgz"
    if (!file.exists(CEUvcf)) {
      stop(paste("Required input VCF file not found in working directory:", CEUvcf))
    }
    
    vfpar <- VariantFilteringParam(CEUvcf)
    
    # 2. Annotate variants using unrelatedIndividuals()
    uind <- unrelatedIndividuals(vfpar)
    
    # 3. Summarize annotations using summary()
    sum_default <- summary(uind)
    write.csv(sum_default, "summary_default.csv", row.names=FALSE)
    
    sum_bioc <- summary(uind, method="bioc")
    write.csv(sum_bioc, "summary_bioc.csv", row.names=FALSE)
    
    uindSO <- summary(uind, method="SOfull")
    write.csv(uindSO, "summary_SOfull.csv", row.names=FALSE)
    
    all_vars <- allVariants(uind)
    saveRDS(all_vars, "all_variants.rds")
    
    # 4. Set BAM files and plot variant support using bamFiles() and plot()
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
    
    # 5. Filter variants by modifying active filters and cutoffs using filters(), cutoffs(), and change()
    filters(uind)
    active(filters(uind)) <- TRUE
    change(cutoffs(uind), "SOterms") <- "UTR_variant"
    active(filters(uind))["SOterms"] <- TRUE
    change(cutoffs(uind)\$maxMAF, "popmask") <- FALSE
    change(cutoffs(uind)\$maxMAF, "maxvalue") <- 0.01
    
    # 6. Retrieve filtered variants using filteredVariants()
    fil_vars <- filteredVariants(uind)
    saveRDS(fil_vars, "filtered_variants.rds")
    
    # 7. Export results using reportVariants()
    reportVariants(uind, type="csv", file="uind.csv")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_VARIANTFILTERING_UNRELATED_INDIVIDUALS_ANALYSIS":
        variantfiltering: \$(Rscript -e 'cat(as.character(packageVersion("variantfiltering")))')
    END_VERSIONS
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
