#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowClean — flow_cytometry_quality_control
// Perform quality control on a flow cytometry dataset to identify and filter out cells collected during perturbed time periods.
// Input: user_data.fcs
// Container: quay.io/biocontainers/bioconductor-flowclean:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowClean, flowCore, flowViz, gridExtra
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the clean function on the flowFrame to identify perturbed periods and append the GoodVsBad parameter
//  * 2. [Visualization & Output] Estimate and apply logicle transformation for visualization and downstream analysis
//  * 3. [Input & Preparation] Define a rectangleGate to select cells with GoodVsBad values below 10000
//  * 4. [Core Analysis] Filter and subset the flowFrame to retain only the high-quality cells

nextflow.enable.dsl = 2

process BIOC_FLOWCLEAN_FLOW_CYTOMETRY_QUALITY_CONTROL {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("flowCore", "flowClean", "flowViz", "gridExtra")
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
    library(flowCore)
    library(flowClean)
    library(flowViz)
    library(grid)
    library(gridExtra)
    
    # 1. Read the user input FCS file
    # We read the FCS file without transformation to preserve the original state for flowClean
    synPerturbed <- read.FCS("user_data.fcs", transformation=FALSE, truncate_max_range=FALSE)
    
    # Dynamically identify marker columns by excluding scatter (FSC/SSC) and Time parameters
    params <- parameters(synPerturbed)\$name
    marker_cols <- grep("FSC|SSC|Time", params, invert=TRUE, ignore.case=TRUE)
    
    # 2. Run the clean function to identify perturbed periods and append the GoodVsBad parameter
    # (Documented Code Stage 1)
    synPerturbed.c <- clean(synPerturbed, vectMarkers=marker_cols, 
                       filePrefixWithDir="sample_out", ext="fcs", diagnostic=TRUE)
    
    # 3. Estimate and apply logicle transformation
    # (Documented Code Stage 2)
    lgcl <- estimateLogicle(synPerturbed.c, unname(parameters(synPerturbed.c)\$name[marker_cols]))
    synPerturbed.cl <- transform(synPerturbed.c, lgcl)
    
    # 4. Define a rectangleGate to select cells with GoodVsBad values below 10000
    # (Documented Code Stage 3)
    rg <- rectangleGate(filterId="gvb", list("GoodVsBad"=c(0, 9999)))
    
    # 5. Filter and subset the flowFrame to retain only the high-quality cells
    # (Documented Code Stage 4)
    idx <- filter(synPerturbed.cl, rg)
    synPerturbed.clean <- Subset(synPerturbed.cl, idx)
    
    # 6. Save the meaningful results to output files
    # Save the cleaned flowFrame as an FCS file
    write.FCS(synPerturbed.clean, "cleaned_data.fcs")
    
    # Save the cleaned flowFrame object as an RDS file
    saveRDS(synPerturbed.clean, "synPerturbed_clean.rds")
    
    # Generate and save diagnostic QC plots
    pdf("flowClean_qc_plots.pdf", width=10, height=5)
    tryCatch({
      # Plot GoodVsBad parameter over Time to visualize the identified perturbed regions
      p_qc <- xyplot(`GoodVsBad` ~ `Time`, data=synPerturbed.cl, 
                     abs=TRUE, smooth=FALSE, alpha=0.5, ylim=c(0, 20000),
                     main="flowClean QC: GoodVsBad vs Time")
      print(p_qc)
    }, error = function(e) {
      warning("Could not generate diagnostic xyplot: ", e\$message)
    })
    dev.off()
    
    # Write a summary CSV file of the filtering results
    summary_stats <- data.frame(
      Metric = c("Total Cells", "Clean Cells Retained", "Percentage Retained"),
      Value = c(
        nrow(synPerturbed),
        nrow(synPerturbed.clean),
        round((nrow(synPerturbed.clean) / nrow(synPerturbed)) * 100, 2)
      )
    )
    write.csv(summary_stats, "flowClean_summary.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_FLOWCLEAN_FLOW_CYTOMETRY_QUALITY_CONTROL":',
        paste0('    flowClean: ', as.character(packageVersion('flowClean')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flow_cytometry_quality_control.csv versions.yml
    """
}

workflow BIOC_FLOWCLEAN_FLOW_CYTOMETRY_QUALITY_CONTROL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_data.fcs ] ]

    main:
    BIOC_FLOWCLEAN_FLOW_CYTOMETRY_QUALITY_CONTROL(ch_input)

    emit:
    tables   = BIOC_FLOWCLEAN_FLOW_CYTOMETRY_QUALITY_CONTROL.out.tables
    plots    = BIOC_FLOWCLEAN_FLOW_CYTOMETRY_QUALITY_CONTROL.out.plots
    objects  = BIOC_FLOWCLEAN_FLOW_CYTOMETRY_QUALITY_CONTROL.out.objects
    versions = BIOC_FLOWCLEAN_FLOW_CYTOMETRY_QUALITY_CONTROL.out.versions
}
