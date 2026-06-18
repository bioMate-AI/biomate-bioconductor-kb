#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowGraph — standard_flowgraph_analysis
// Perform standard differential cell population analysis on flow cytometry cell count data using SpecEnr.
// Input: count, meta
// Container: quay.io/biocontainers/bioconductor-flowgraph:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowGraph
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the flowGraph object using flowGraph
//  * 2. [Core Analysis] Retrieve sample metadata and features using fg_get_meta and fg_get_feature
//  * 3. [Visualization & Output] Calculate summary statistics using fg_summary
//  * 4. [Visualization & Output] Retrieve summary statistics using fg_get_summary
//  * 5. [Visualization & Output] Save and load the flowGraph object using fg_save and fg_load
//  * 6. [Visualization & Output] Visualize results using fg_plot, plot_gr, fg_plot_qq, fg_plot_box, and fg_plot_pVSdiff

nextflow.enable.dsl = 2

process BIOC_FLOWGRAPH_STANDARD_FLOWGRAPH_ANALYSIS {
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
    .bm_deps <- c("flowGraph")
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
        library(flowGraph)
        
        # Helper function to robustly read input files from the working directory
        read_input <- function(base_name) {
          if (file.exists(paste0(base_name, ".rds"))) {
            return(readRDS(paste0(base_name, ".rds")))
          } else if (file.exists(paste0(base_name, ".csv"))) {
            df <- tryCatch({
              read.csv(paste0(base_name, ".csv"), row.names = 1, check.names = FALSE)
            }, error = function(e) {
              read.csv(paste0(base_name, ".csv"), check.names = FALSE)
            })
            return(df)
          } else if (file.exists(base_name)) {
            return(tryCatch(readRDS(base_name), error = function(e) {
              tryCatch({
                read.csv(base_name, row.names = 1, check.names = FALSE)
              }, error = function(ee) {
                read.csv(base_name, check.names = FALSE)
              })
            }))
          } else {
            stop(paste("Required input file not found:", base_name))
          }
        }
        
        # Read user input files
        count_data <- as.matrix(read_input("count"))
        meta_data <- read_input("meta")
        
        # Ensure 'id' column exists in meta_data and matches row names of count_data
        if (!"id" %in% colnames(meta_data)) {
          meta_data\$id <- rownames(meta_data)
        }
        rownames(count_data) <- meta_data\$id
        
        # Ensure 'class' column exists with "control" and "exp" labels to match vignette expectations
        if (!"class" %in% colnames(meta_data)) {
          two_val_cols <- sapply(meta_data, function(x) length(unique(x)) == 2)
          if (any(two_val_cols)) {
            meta_data\$class <- meta_data[[which(two_val_cols)[1]]]
          } else {
            meta_data\$class <- rep(c("control", "exp"), length.out = nrow(meta_data))
          }
        }
        meta_data\$class <- as.character(meta_data\$class)
        unique_classes <- unique(meta_data\$class)
        if (!all(c("control", "exp") %in% unique_classes)) {
          meta_data\$class <- ifelse(meta_data\$class == unique_classes[1], "control", "exp")
        }
        
        # Set number of cores
        no_cores <- 1
        
        # 1. Initialize the flowGraph object
        fg <- flowGraph(count_data, meta=meta_data, no_cores=no_cores)
        
        # 2. Retrieve sample metadata and features
        meta <- fg_get_meta(fg)
        mcount <- fg_get_feature(fg, "node", "count")
        
        # 3. Retrieve summary statistics
        fg_sum <- fg_get_summary(fg, type="node", summary_meta=list(
            node_feature="SpecEnr", 
            test_name="t_diminish", 
            class="class", 
            labels=c("exp","control"))
        )
        
        # 4. Save and load the flowGraph object
        dir.create("path/to/user/specified/folder/directory", recursive=TRUE, showWarnings=FALSE)
        fg_save(fg, "path/to/user/specified/folder/directory")
        fg <- fg_load("path/to/user/specified/folder/directory")
        
        # 5. Modify metadata and features
        meta_new <- fg_get_meta(fg)
        meta_new\$modified <- TRUE
        fg <- fg_replace_meta(fg, meta_new)
        
        mc <- fg_get_feature(fg, type="node", feature="count")
        fg <- fg_add_feature(fg, type="node", feature="count_copy", m=mc)
        fg <- fg_rm_feature(fg, type="node", feature="count_copy")
        
        # 6. Calculate summary statistics
        fg <- fg_summary(fg, no_cores=no_cores, class="class", label1="control",
                         node_features="count", edge_features="NONE",
                         overwrite=FALSE, test_name="t", diminish=FALSE)
        
        # 7. Visualize results and save plots
        gr <- fg_plot(fg, index=1, p_thres=.01, show_bgedges=TRUE)
        
        # Save static plots to a PDF file
        pdf("flowgraph_analysis_plots.pdf", width=11, height=8.5)
        tryCatch({
          print(plot_gr(gr, interactive=FALSE))
          print(fg_plot_qq(fg, type="node", index=1))
          print(fg_plot_box(fg, type="node", summary_meta=NULL, index=1, node_edge=colnames(count_data)[1]))
          print(fg_plot_pVSdiff(fg, type="node", summary_meta=NULL, index=1))
        }, error = function(e) {
          message("Error during PDF plotting: ", e\$message)
        })
        dev.off()
        
        # Run interactive/screen plotting as documented
        tryCatch({
          print(plot_gr(gr, interactive=TRUE))
          print(fg_plot_qq(fg, type="node", index=1))
          print(fg_plot_box(fg, type="node", summary_meta=NULL, index=1, node_edge=colnames(count_data)[1]))
          print(fg_plot_pVSdiff(fg, type="node", summary_meta=NULL, index=1))
        }, error = function(e) {
          message("Interactive plotting skipped or failed: ", e\$message)
        })
        
        # Write meaningful tabular and object outputs
        write.csv(meta, "fg_metadata.csv", row.names=FALSE)
        write.csv(mcount, "fg_node_counts.csv")
        if (!is.null(fg_sum) && !is.null(fg_sum\$values)) {
          write.csv(data.frame(Phenotype=names(fg_sum\$values), P_Value=fg_sum\$values), "fg_specenr_summary_values.csv", row.names=FALSE)
        }
        saveRDS(fg, "flowGraph_final_object.rds")

    writeLines(c(
        '"BIOC_FLOWGRAPH_STANDARD_FLOWGRAPH_ANALYSIS":',
        paste0('    flowGraph: ', as.character(packageVersion('flowGraph')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_flowgraph_analysis.csv versions.yml
    """
}

workflow BIOC_FLOWGRAPH_STANDARD_FLOWGRAPH_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count, meta ] ]

    main:
    BIOC_FLOWGRAPH_STANDARD_FLOWGRAPH_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FLOWGRAPH_STANDARD_FLOWGRAPH_ANALYSIS.out.tables
    plots    = BIOC_FLOWGRAPH_STANDARD_FLOWGRAPH_ANALYSIS.out.plots
    objects  = BIOC_FLOWGRAPH_STANDARD_FLOWGRAPH_ANALYSIS.out.objects
    versions = BIOC_FLOWGRAPH_STANDARD_FLOWGRAPH_ANALYSIS.out.versions
}
