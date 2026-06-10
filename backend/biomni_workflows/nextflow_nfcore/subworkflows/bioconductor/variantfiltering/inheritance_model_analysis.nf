#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: VariantFiltering — inheritance_model_analysis
// Filter variants that segregate according to a specific inheritance model using pedigree data.
// Input: CEUtrio.vcf.bgz, CEUtrio.ped
// Container: quay.io/biocontainers/bioconductor-variantfiltering:1.46.0--r45h01b2380_0
// Requires: VariantFiltering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize parameters with VariantFilteringParam() specifying both VCF and PED files
//  * 2. [Core Analysis] Run the inheritance-model-specific function (e.g., autosomalRecessiveHomozygous, autosomalRecessiveHeterozygous, autosomalDominant
//  * 3. [Visualization & Output] Summarize and filter results
//  * 4. [Visualization & Output] Export results using reportVariants()

nextflow.enable.dsl = 2

process BIOC_VARIANTFILTERING_INHERITANCE_MODEL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    library(VariantFiltering)
    
    # Define input files in the working directory
    CEUvcf <- "CEUtrio.vcf.bgz"
    CEUped <- "CEUtrio.ped"
    
    # Verify input files exist
    if (!file.exists(CEUvcf)) {
      stop(paste("Required VCF file missing in working directory:", CEUvcf))
    }
    if (!file.exists(CEUped)) {
      stop(paste("Required PED file missing in working directory:", CEUped))
    }
    
    # 1. Initialize parameters with VariantFilteringParam specifying both VCF and PED files
    param <- VariantFilteringParam(vcfFilenames=CEUvcf, pedFilename=CEUped)
    
    # Helper function to summarize, filter, and export results
    process_results <- function(res, model_name) {
      if (is.null(res)) {
        message(paste("Skipping export for", model_name, "due to previous errors or empty results."))
        return(NULL)
      }
      
      message(paste("Processing results for inheritance model:", model_name))
      
      # Save the VariantFilteringResults object as an RDS file
      saveRDS(res, file = paste0(model_name, "_results.rds"))
      
      # 3. Summarize results
      tryCatch({
        sum_df <- summary(res)
        write.csv(sum_df, file = paste0(model_name, "_summary.csv"), row.names = FALSE)
      }, error = function(e) {
        message(paste("Could not generate summary for", model_name, ":", e\$message))
      })
      
      # 4. Export results using reportVariants()
      tryCatch({
        reportVariants(res, type="csv", file=paste0(model_name, "_variants.csv"))
      }, error = function(e) {
        message(paste("Could not export variants for", model_name, ":", e\$message))
      })
    }
    
    # 2. Run the inheritance-model-specific functions based on the study design
    
    # Autosomal Recessive Homozygous
    homozygous_results <- tryCatch({
      autosomalRecessiveHomozygous(param)
    }, error = function(e) {
      message("Error running autosomalRecessiveHomozygous: ", e\$message)
      NULL
    })
    process_results(homozygous_results, "homozygous")
    
    # Autosomal Recessive Heterozygous (Compound Heterozygous)
    comp_het_results <- tryCatch({
      autosomalRecessiveHeterozygous(param)
    }, error = function(e) {
      message("Error running autosomalRecessiveHeterozygous: ", e\$message)
      NULL
    })
    process_results(comp_het_results, "comp_het")
    
    # Autosomal Dominant
    dominant_results <- tryCatch({
      autosomalDominant(param)
    }, error = function(e) {
      message("Error running autosomalDominant: ", e\$message)
      NULL
    })
    process_results(dominant_results, "dominant")
    
    # X-Linked (restricted to affected males)
    x_linked_results <- tryCatch({
      xLinked(param)
    }, error = function(e) {
      message("Error running xLinked: ", e\$message)
      NULL
    })
    process_results(x_linked_results, "x_linked")
    
    # De Novo variants (restricted to a trio)
    de_novo_results <- tryCatch({
      deNovo(param)
    }, error = function(e) {
      message("Error running deNovo: ", e\$message)
      NULL
    })
    process_results(de_novo_results, "de_novo")
    
    message("VariantFiltering inheritance model analysis pipeline completed.")

    writeLines(c(
        '"BIOC_VARIANTFILTERING_INHERITANCE_MODEL_ANALYSIS":',
        paste0('    VariantFiltering: ', as.character(packageVersion('VariantFiltering')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inheritance_model_analysis.csv versions.yml
    """
}

workflow BIOC_VARIANTFILTERING_INHERITANCE_MODEL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CEUtrio.vcf.bgz, CEUtrio.ped ] ]

    main:
    BIOC_VARIANTFILTERING_INHERITANCE_MODEL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_VARIANTFILTERING_INHERITANCE_MODEL_ANALYSIS.out.tables
    plots    = BIOC_VARIANTFILTERING_INHERITANCE_MODEL_ANALYSIS.out.plots
    objects  = BIOC_VARIANTFILTERING_INHERITANCE_MODEL_ANALYSIS.out.objects
    versions = BIOC_VARIANTFILTERING_INHERITANCE_MODEL_ANALYSIS.out.versions
}
