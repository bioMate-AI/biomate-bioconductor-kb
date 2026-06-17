#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowCore — flow_cytometry_preprocessing
// Read FCS files, calculate and apply spectral compensation, transform fluorescence channels, and apply manual gates to filter populations.
// Input: file.name.FCS, fcs.dir, comp_match.csv
// Container: quay.io/biocontainers/bioconductor-flowcore:2.22.1--r45ha27e39d_0
// R packages: flowCore, flowStats, flowWorkspace, ggcyto, gridExtra, Rgraphviz
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowStats
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read FCS files into flowFrame or flowSet
//  * 2. [Input & Preparation] Calculate or load the spillover matrix
//  * 3. [Core Analysis] Compensate the spectral overlap
//  * 4. [Core Analysis] Transform parameters using log or logicle scales
//  * 5. [Input & Preparation] Define and apply gates (filtering) to isolate cell populations

nextflow.enable.dsl = 2

process BIOC_FLOWCORE_FLOW_CYTOMETRY_PREPROCESSING {
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
    .bm_deps <- c("flowCore", "flowStats", "flowWorkspace", "ggcyto", "gridExtra", "Rgraphviz")
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
                library(flowStats)
                
                # Define user inputs from the working directory
                file.name <- "file.name.FCS"
                fcs.dir <- "fcs.dir"
                comp_match <- "comp_match.csv"
                
                # ==========================================
                # 1. Read FCS files into flowFrame or flowSet
                # ==========================================
                
                # Read raw FCS file
                x <- read.FCS(file.name, transformation=FALSE)
                summary(x)
                
                # Search keywords
                keyword(x, c("\$P1E", "\$P2E", "\$P3E", "\$P4E"))
                
                # Read with alter.names
                x_alt <- read.FCS(file.name, alter.names=TRUE)
                
                # Read with column pattern (handled robustly in case pattern is absent)
                tryCatch({
                  x_pattern <- read.FCS(file.name, column.pattern="-H")
                }, error = function(e) {
                  message("Note: column.pattern '-H' not found, skipping pattern read.")
                })
                
                # Read subset of lines
                lines <- sample(1:nrow(x), min(50, nrow(x)))
                y <- read.FCS(file.name, which.lines = lines)
                
                # Read compensation controls from directory
                fs <- read.flowSet(path = fcs.dir)
                fsApply(fs, each_col, median)
                
                # ==========================================
                # 2. Calculate or load the spillover matrix
                # ==========================================
                
                # Dynamically identify FSC and SSC channels
                chans <- colnames(x)
                fsc_chan <- grep("FSC", chans, value=TRUE, ignore.case=TRUE)[1]
                ssc_chan <- grep("SSC", chans, value=TRUE, ignore.case=TRUE)[1]
                if (is.na(fsc_chan)) fsc_chan <- "FSC-H"
                if (is.na(ssc_chan)) ssc_chan <- "SSC-H"
                
                # Match controls and calculate spillover matrix
                match_df <- read.csv(comp_match, stringsAsFactors = FALSE)
                sampleNames(fs) <- match_df[match(sampleNames(fs), match_df[[1]]), 2]
                
                comp <- flowCore::spillover(fs, fsc = fsc_chan, ssc = ssc_chan, 
                                             prematched = TRUE)
                
                # Save calculated compensation matrix
                write.csv(comp, "compensation_matrix.csv", row.names=TRUE)
                
                # ==========================================
                # 3. Compensate the spectral overlap
                # ==========================================
                
                x_comp <- compensate(x, comp)
                fs_comp <- compensate(fs, comp)
                
                # ==========================================
                # 4. Transform parameters using log or logicle scales
                # ==========================================
                
                # Identify fluorescence channels for transformation
                fluor_chans <- chans[!grepl("FSC|SSC|Time", chans, ignore.case=TRUE)]
                trans_chans <- head(fluor_chans, 2)
                if (length(trans_chans) < 2) {
                  trans_chans <- c("FL1-H", "FL2-H")
                }
                
                # Estimate Logicle transform
                transList <- estimateLogicle(x_comp, trans_chans)
                x_trans <- transform(x_comp, transList)
                
                # Apply truncateTransform
                aTrans <- truncateTransform("truncate at 1", a=1)
                myTrans <- transformList(trans_chans[1], aTrans)
                fs_trans <- transform(fs_comp, myTrans)
                
                # Save preprocessed flowSet
                saveRDS(fs_trans, "preprocessed_flowset.rds")
                
                # ==========================================
                # 5. Define and apply gates (filtering)
                # ==========================================
                
                # Define rectangle gate on the first two fluorescence channels
                gate_args <- list(filterId="Fluorescence Region")
                gate_args[[trans_chans[1]]] <- c(0, 12)
                gate_args[[trans_chans[2]]] <- c(0, 12)
                rectGate <- do.call(rectangleGate, gate_args)
                
                # Apply rectangle gate
                result <- filter(x_trans, rectGate)
                gating_summary <- summary(result)
                
                # Apply to entire sample
                x_filtered <- Subset(x_trans, rectGate)
                
                # Define and apply morphology gate (norm2Filter)
                morphGate <- norm2Filter(fsc_chan, ssc_chan, filterId="MorphologyGate", scale=2)
                smaller <- Subset(x_trans, morphGate)
                
                # Apply kmeansFilter and split
                k_args <- list(c("Low", "Medium", "High"))
                names(k_args) <- fsc_chan
                k_args\$filterId <- "myKMeans"
                kmGate <- do.call(kmeansFilter, k_args)
                split_result <- split(smaller, kmGate)
                
                # ==========================================
                # 6. Write Outputs
                # ==========================================
                
                # Write gating summary text
                sink("gating_summary.txt")
                cat("=== Gating Summary ===\n")
                print(gating_summary)
                cat("\n=== Split Populations (K-Means) ===\n")
                print(split_result)
                sink()
                
                # Generate diagnostic plots
                pdf("gating_plots.pdf", width=10, height=8)
                par(mfrow=c(2,2))
                
                # Plot 1: Raw FSC vs SSC
                plot(exprs(fs[[1]])[, c(fsc_chan, ssc_chan)], 
                     pch=".", col=densCols(exprs(fs[[1]])[, c(fsc_chan, ssc_chan)]),
                     xlab=fsc_chan, ylab=ssc_chan, main="Raw FSC vs SSC")
                
                # Plot 2: Gated FSC vs SSC (Morphology Gate)
                plot(exprs(smaller)[, c(fsc_chan, ssc_chan)], 
                     pch=".", col="blue",
                     xlab=fsc_chan, ylab=ssc_chan, main="Gated FSC vs SSC (Morphology Gate)")
                
                # Plot 3: Fluorescence Channels (Compensated & Transformed)
                plot(exprs(x_trans)[, trans_chans], 
                     pch=".", col=densCols(exprs(x_trans)[, trans_chans]),
                     xlab=trans_chans[1], ylab=trans_chans[2], main="Compensated & Transformed")
                
                dev.off()

    writeLines(c(
        '"BIOC_FLOWCORE_FLOW_CYTOMETRY_PREPROCESSING":',
        paste0('    flowCore: ', as.character(packageVersion('flowCore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flow_cytometry_preprocessing.csv versions.yml
    """
}

workflow BIOC_FLOWCORE_FLOW_CYTOMETRY_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.name.FCS, fcs.dir, comp_match.csv ] ]

    main:
    BIOC_FLOWCORE_FLOW_CYTOMETRY_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_FLOWCORE_FLOW_CYTOMETRY_PREPROCESSING.out.tables
    plots    = BIOC_FLOWCORE_FLOW_CYTOMETRY_PREPROCESSING.out.plots
    objects  = BIOC_FLOWCORE_FLOW_CYTOMETRY_PREPROCESSING.out.objects
    versions = BIOC_FLOWCORE_FLOW_CYTOMETRY_PREPROCESSING.out.versions
}
