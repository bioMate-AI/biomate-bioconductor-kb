#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cyanoFilter — phytoplankton_gating_workflow
// Filter metadata, preprocess flow cytometry data, and sequentially gate margin events, debris, and cyanobacteria populations.
// Input: metadata.csv, sample.fcs
// Container: quay.io/biocontainers/bioconductor-cyanofilter:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cyanoFilter, dplyr, flowCore, flowDensity, magrittr, purrr, stringr, tidyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter metadata for good measurements using goodFcs
//  * 2. [Core Analysis] Select files to retain using retain
//  * 3. [Input & Preparation] Read FCS file using read.FCS
//  * 4. [Core Analysis] Remove NA values using noNA
//  * 5. [Core Analysis] Remove negative values using noNeg
//  * 6. [Core Analysis] Perform logarithmic transformation using lnTrans
//  * 7. [Core Analysis] Gate and remove margin events using cellMargin
//  * 8. [Core Analysis] Gate and remove debris using debrisNc
//  * 9. [Core Analysis] Gate and identify cyanobacteria populations using phytoFilter

nextflow.enable.dsl = 2

process BIOC_CYANOFILTER_PHYTOPLANKTON_GATING_WORKFLOW {
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
    .bm_deps <- c("dplyr", "magrittr", "tidyr", "purrr", "flowCore", "flowDensity", "cyanoFilter")
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
    library(dplyr)
    library(magrittr)
    library(tidyr)
    library(purrr)
    library(flowCore)
    library(flowDensity)
    library(cyanoFilter)
    
    # ==========================================
    # 1. Read and Preprocess Metadata
    # ==========================================
    # Read the user-provided metadata file
    metafile <- read.csv("metadata.csv", stringsAsFactors = FALSE, check.names = TRUE)
    
    # Ensure Sample.ID2 exists (extract from Sample.ID if needed, fallback to "Sample" if missing)
    if (!"Sample.ID2" %in% names(metafile)) {
      if ("Sample.ID" %in% names(metafile)) {
        metafile\$Sample.ID2 <- stringr::str_extract(metafile\$Sample.ID, "BS*[4-5]")
        metafile\$Sample.ID2[is.na(metafile\$Sample.ID2)] <- "Sample"
      } else {
        metafile\$Sample.ID2 <- "Sample"
      }
    }
    
    # Ensure CellspML column exists (rename from Cells.* if needed, fallback to 100 if missing)
    if (!"CellspML" %in% names(metafile)) {
      cells_col <- grep("Cells", names(metafile), value = TRUE)
      if (length(cells_col) > 0) {
        names(metafile)[names(metafile) == cells_col[1]] <- "CellspML"
      } else {
        metafile\$CellspML <- 100
      }
    }
    
    # Filter metadata for good measurements using goodFcs
    metafile <- metafile %>% mutate(Status = cyanoFilter::goodFcs(metafile = metafile, 
                                                                  col_cpml = "CellspML", 
                                            mxd_cellpML = 1000, 
                                            mnd_cellpML = 50)
                                    )
    
    # Select files to retain using retain
    broken <- metafile %>% group_by(Sample.ID2) %>% nest()
    metafile\$Retained <- unlist(map(broken\$data, function(.x) {
      retain(meta_files = .x, make_decision = "maxi",
      Status = "Status",
      CellspML = "CellspML")
     })
    )
    
    # Save processed metadata
    write.csv(metafile, "processed_metadata.csv", row.names = FALSE)
    
    # ==========================================
    # 2. Flow Cytometry File Processing
    # ==========================================
    # Read the user-provided FCS file
    flowfile_path <- "sample.fcs"
    flowfile <- read.FCS(flowfile_path, alter.names = TRUE,
      transformation = FALSE, emptyValue = FALSE,
      dataset = 1)
    
    # Remove NA values using noNA
    flowfile_nona <- noNA(x = flowfile)
    
    # Remove negative values using noNeg
    flowfile_noneg <- noNeg(x = flowfile_nona)
    
    # Perform logarithmic transformation using lnTrans
    flowfile_logtrans <- lnTrans(x = flowfile_noneg, 
      notToTransform = c("SSC.W", "TIME"))
    
    # Gate and remove margin events using cellMargin
    flowfile_marginout <- cellMargin(flowframe = flowfile_logtrans,
                                     Channel = 'SSC.W', type = 'estimate', 
                                     y_toplot = "FSC.HLin")
    
    # Gate and remove debris using debrisNc
    cells_nodebris <-  debrisNc(flowframe = reducedFlowframe(flowfile_marginout), 
                                 ch_chlorophyll = "RED.B.HLin", ch_p2 = "YEL.B.HLin",
                                 ph = 0.05)
    
    # Gate and identify cyanobacteria populations using phytoFilter
    bs4_gate1 <- phytoFilter(flowfile = reducedFlowframe(cells_nodebris),
                   pig_channels = c("RED.B.HLin", "YEL.B.HLin", "RED.R.HLin"),
                   com_channels = c("FSC.HLin", "SSC.HLin"))
    
    # ==========================================
    # 3. Save Outputs and Plots
    # ==========================================
    # Save the final PhytoFilter object
    saveRDS(bs4_gate1, "phyto_filter_result.rds")
    
    # Save cell counts summary
    counts_df <- data.frame(
      Cell_Count = bs4_gate1@Cell_count,
      Debris_Count = bs4_gate1@Debris_Count
    )
    write.csv(counts_df, "cell_counts.csv", row.names = FALSE)
    
    # Save diagnostic plots
    pdf("margin_events_plot.pdf")
    plot(flowfile_marginout)
    dev.off()
    
    pdf("debris_plot.pdf")
    plot(cells_nodebris)
    dev.off()
    
    pdf("phyto_filter_plot.pdf")
    plot(bs4_gate1)
    dev.off()

    writeLines(c(
        '"BIOC_CYANOFILTER_PHYTOPLANKTON_GATING_WORKFLOW":',
        paste0('    cyanoFilter: ', as.character(packageVersion('cyanoFilter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phytoplankton_gating_workflow.csv versions.yml
    """
}

workflow BIOC_CYANOFILTER_PHYTOPLANKTON_GATING_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metadata.csv, sample.fcs ] ]

    main:
    BIOC_CYANOFILTER_PHYTOPLANKTON_GATING_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_CYANOFILTER_PHYTOPLANKTON_GATING_WORKFLOW.out.tables
    plots    = BIOC_CYANOFILTER_PHYTOPLANKTON_GATING_WORKFLOW.out.plots
    objects  = BIOC_CYANOFILTER_PHYTOPLANKTON_GATING_WORKFLOW.out.objects
    versions = BIOC_CYANOFILTER_PHYTOPLANKTON_GATING_WORKFLOW.out.versions
}
