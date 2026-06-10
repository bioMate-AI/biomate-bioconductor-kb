#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: asics — metabolite_quantification_and_analysis
// Preprocess raw 1D 1H NMR spectra, identify and quantify metabolites using a reference library, and perform downstream statistical analyses (PCA, OPLS-DA, Kruska
// Input: raw_spectra_directory, design_file.txt
// Container: quay.io/biocontainers/bioconductor-asics:2.26.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASICS_METABOLITE_QUANTIFICATION_AND_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-asics:2.26.0--r45hdfd78af_0"

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
    .bm_deps <- c("asics", "asicsdata")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(ASICS)
    
    # ----------------------------------------------------------------------
    # 1. Import raw spectra and design metadata
    # ----------------------------------------------------------------------
    design_file <- "design_file.txt"
    if (!file.exists(design_file)) {
      stop("Required design file 'design_file.txt' not found in the working directory.")
    }
    
    # Read design metadata
    design <- read.table(design_file, header = TRUE, stringsAsFactors = FALSE)
    
    # Ensure the grouping column "condition" exists in design.
    # If not, rename the second column to "condition" to match the documented workflow.
    if (!"condition" %in% colnames(design)) {
      if (ncol(design) >= 2) {
        colnames(design)[2] <- "condition"
      } else {
        stop("Design file must have at least two columns (Sample ID and Grouping/Condition).")
      }
    }
    
    # Import spectra based on available user input files
    if (dir.exists("raw_spectra_directory")) {
      message("Importing Bruker spectra from 'raw_spectra_directory'...")
      spectra_data <- importSpectraBruker("raw_spectra_directory")
      spectra_obj <- createSpectra(spectra_data)
    } else if (file.exists("spectra_file.txt")) {
      message("Importing spectra from 'spectra_file.txt'...")
      spectra_data_txt <- read.table("spectra_file.txt", header = TRUE, row.names = 1)
      spectra_base_cor <- baselineCorrection(spectra_data_txt)
      spectra_obj <- createSpectra(spectra_base_cor)
    } else {
      stop("Neither 'raw_spectra_directory' nor 'spectra_file.txt' was found in the working directory.")
    }
    
    # ----------------------------------------------------------------------
    # 2. Identify and quantify metabolites using ASICS
    # ----------------------------------------------------------------------
    # Define areas to exclude (e.g., water and urea regions)
    to_exclude <- matrix(c(4.5, 5.1, 5.5, 6.5), ncol = 2, byrow = TRUE)
    
    # Run ASICS quantification
    ASICS_results <- ASICS(spectra_obj, exclusion.areas = to_exclude)
    
    # Save quantification results to CSV
    quant_df <- getQuantification(ASICS_results)
    write.csv(quant_df, "quantification_results.csv", row.names = TRUE)
    
    # ----------------------------------------------------------------------
    # 3. Format quantification results for downstream analysis
    # ----------------------------------------------------------------------
    # Safely handle specified outliers (only exclude if they exist in the dataset)
    outliers_to_exclude <- c("ADG10003u_007", "ADG19007u_163")
    outliers_to_exclude <- outliers_to_exclude[outliers_to_exclude %in% colnames(quant_df)]
    if (length(outliers_to_exclude) == 0) {
      outliers_to_exclude <- NULL
    }
    
    analysis_data <- formatForAnalysis(
      getQuantification(ASICS_results), 
      design = design, 
      zero.threshold = 75, 
      zero.group = "condition", 
      outliers = outliers_to_exclude
    )
    
    # ----------------------------------------------------------------------
    # 4. Downstream Statistical Analyses
    # ----------------------------------------------------------------------
    # PCA Analysis
    resPCA <- pca(analysis_data)
    
    # OPLS-DA Analysis
    resOPLSDA <- oplsda(analysis_data, condition = "condition", orthoI = 1)
    
    # Kruskal-Wallis Tests
    resTests <- kruskalWallis(analysis_data, "condition")
    
    # Save analysis objects
    saveRDS(ASICS_results, "ASICS_results.rds")
    saveRDS(analysis_data, "analysis_data.rds")
    saveRDS(resPCA, "resPCA.rds")
    saveRDS(resOPLSDA, "resOPLSDA.rds")
    saveRDS(resTests, "resTests.rds")
    
    # ----------------------------------------------------------------------
    # 5. Visualization and Plotting
    # ----------------------------------------------------------------------
    pdf("asics_analysis_plots.pdf", width = 10, height = 8)
    
    # Plot ASICS quantification fit for the first spectrum
    tryCatch({
      plot(ASICS_results, idx = 1, xlim = c(2.8, 3.3), add.metab = "Creatinine")
    }, error = function(e) {
      warning("Could not plot with Creatinine; plotting default fit instead: ", e\$message)
      plot(ASICS_results, idx = 1, xlim = c(2.8, 3.3))
    })
    
    # Plot PCA results
    plot(resPCA, graph = "ind", col.ind = "condition")
    plot(resPCA, graph = "var")
    
    # Plot OPLS-DA results
    plot(resOPLSDA)
    
    # Plot Kruskal-Wallis test results
    plot(resTests)
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ASICS_METABOLITE_QUANTIFICATION_AND_ANALYSIS":
        asics: \$(Rscript -e 'cat(as.character(packageVersion("asics")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metabolite_quantification_and_analysis.csv versions.yml
    """
}

workflow BIOC_ASICS_METABOLITE_QUANTIFICATION_AND_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_spectra_directory, design_file.txt ] ]

    main:
    BIOC_ASICS_METABOLITE_QUANTIFICATION_AND_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ASICS_METABOLITE_QUANTIFICATION_AND_ANALYSIS.out.tables
    plots    = BIOC_ASICS_METABOLITE_QUANTIFICATION_AND_ANALYSIS.out.plots
    objects  = BIOC_ASICS_METABOLITE_QUANTIFICATION_AND_ANALYSIS.out.objects
    versions = BIOC_ASICS_METABOLITE_QUANTIFICATION_AND_ANALYSIS.out.versions
}
