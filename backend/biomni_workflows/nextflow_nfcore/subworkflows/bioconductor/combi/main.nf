#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: combi — unconstrained_integration
// Integrate multiple omics views without constraints and visualize the shared variability.
// Input: zhangMicrobio, zhangMetabo, zhangMetavars
// Container: quay.io/biocontainers/bioconductor-combi:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: combi
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit unconstrained combi model using combi()
//  * 2. [Visualization & Output] Print model summary
//  * 3. [Visualization & Output] Plot ordination with sample metadata
//  * 4. [Visualization & Output] Plot alternative feature representations (points or density)
//  * 5. [Core Analysis] Add links/projections between features and samples using addLink()
//  * 6. [Core Analysis] Extract coordinates using extractCoords()
//  * 7. [Core Analysis] Run diagnostics using convPlot() and inflPlot()

nextflow.enable.dsl = 2

process BIOC_COMBI_UNCONSTRAINED_INTEGRATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("combi")
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
    library(combi)
    
    # Helper function to read user input files from the working directory
    read_input = function(base_name) {
      # Try RDS first
      if (file.exists(paste0(base_name, ".rds"))) {
        return(readRDS(paste0(base_name, ".rds")))
      }
      # Try CSV
      if (file.exists(paste0(base_name, ".csv"))) {
        return(read.csv(paste0(base_name, ".csv"), row.names = 1, check.names = FALSE))
      }
      # Try TSV/TXT
      if (file.exists(paste0(base_name, ".txt"))) {
        return(read.table(paste0(base_name, ".txt"), header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
      }
      stop(paste("Error: Input file not found for", base_name))
    }
    
    # Read the declared user input files
    zhangMicrobio = read_input("zhangMicrobio")
    zhangMetabo = read_input("zhangMetabo")
    zhangMetavars = read_input("zhangMetavars")
    
    # 1. Fit unconstrained combi model
    microMetaboInt = combi(
     list("microbiome" = zhangMicrobio, "metabolomics" = zhangMetabo),
     distributions = c("quasi", "gaussian"), compositional = c(TRUE, FALSE),
     logTransformGaussian = FALSE)
    
    # 2. Print model summary
    sink("model_summary.txt")
    print(microMetaboInt)
    sink()
    
    # Open PDF to save all plots
    pdf("combi_plots.pdf", width = 10, height = 8)
    
    # 3. Plot ordination
    p1 = plot(microMetaboInt)
    print(p1)
    
    # Dynamically select the first column of the metadata for plotting
    sam_col_name = colnames(zhangMetavars)[1]
    
    p2 = plot(microMetaboInt, samDf = zhangMetavars, samCol = sam_col_name)
    print(p2)
    
    # 4. Plot alternative feature representations
    p3 = plot(microMetaboInt, samDf = zhangMetavars, samCol = sam_col_name, 
         featurePlot = "points")
    print(p3)
    
    p4 = plot(microMetaboInt, samDf = zhangMetavars, samCol = sam_col_name, 
         featurePlot = "density")
    print(p4)
    
    # 5. Add links/projections between features and samples
    mmPlot = plot(microMetaboInt, samDf = zhangMetavars, samCol = sam_col_name, returnCoords = TRUE, featNum = 10)
    
    # Wrap in tryCatch in case the specific features do not exist in the user's custom dataset
    tryCatch({
      p5 = addLink(mmPlot, links = cbind("Staphylococcus_819c11","OTU929ffc"), Views = 1, samples = c(0,1))
      print(p5)
    }, error = function(e) {
      message("Could not add link (likely due to missing specific features in input data): ", e\$message)
    })
    
    # 6. Extract coordinates
    coords = extractCoords(microMetaboInt, Dim = c(1,2))
    if (!is.null(names(coords))) {
      for (n in names(coords)) {
        write.csv(coords[[n]], paste0("extracted_coordinates_", n, ".csv"), row.names = TRUE)
      }
    } else {
      for (i in seq_along(coords)) {
        write.csv(coords[[i]], paste0("extracted_coordinates_", i, ".csv"), row.names = TRUE)
      }
    }
    
    # 7. Run diagnostics
    p_conv = convPlot(microMetaboInt)
    print(p_conv)
    
    # Wrap in tryCatch in case the user's dataset has fewer than 20 samples
    tryCatch({
      p_infl = inflPlot(microMetaboInt, samples = 1:20, plotType = "boxplot")
      print(p_infl)
    }, error = function(e) {
      message("Could not plot influence (likely due to sample size constraints): ", e\$message)
    })
    
    dev.off()
    
    # Save the fitted model object
    saveRDS(microMetaboInt, "microMetaboInt.rds")

    writeLines(c(
        '"BIOC_COMBI_UNCONSTRAINED_INTEGRATION":',
        paste0('    combi: ', as.character(packageVersion('combi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unconstrained_integration.csv versions.yml
    """
}

workflow BIOC_COMBI_UNCONSTRAINED_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zhangMicrobio, zhangMetabo, zhangMetavars ] ]

    main:
    BIOC_COMBI_UNCONSTRAINED_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_COMBI_UNCONSTRAINED_INTEGRATION.out.tables
    plots    = BIOC_COMBI_UNCONSTRAINED_INTEGRATION.out.plots
    objects  = BIOC_COMBI_UNCONSTRAINED_INTEGRATION.out.objects
    versions = BIOC_COMBI_UNCONSTRAINED_INTEGRATION.out.versions
}
