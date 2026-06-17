#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: STATegRa — omics_component_analysis
// Identify common and distinctive variation across multiple omics datasets using DISCO-SCA, JIVE, or O2PLS.
// Input: Block1.PCA, Block2.PCA, ed.PCA
// Container: quay.io/biocontainers/bioconductor-stategra:1.46.0--r45hdfd78af_0
// R packages: Biobase, ggplot2, gridExtra, STATegRa
// Bioconductor: 3.20 | R: 4.4
// Requires: STATegRa, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create ExpressionSet objects using createOmicsExpressionSet
//  * 2. [Core Analysis] Perform model selection to find the optimal number of common and distinctive components using modelSelection
//  * 3. [Core Analysis] Run component analysis using omicsCompAnalysis with the chosen method ("DISCOSCA", "JIVE", or "O2PLS")
//  * 4. [Core Analysis] Retrieve scores, loadings, and VAF using getScores, getLoadings, and getVAF
//  * 5. [Visualization & Output] Plot VAF using plotVAF and results using plotRes

nextflow.enable.dsl = 2

process BIOC_STATEGRA_OMICS_COMPONENT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("Biobase", "ggplot2", "gridExtra", "STATegRa")
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
        library(STATegRa)
        library(ggplot2)
        
        # Robust file reader to handle various formats (RDS, CSV, TSV, TXT)
        read_file <- function(base_name) {
          possible_files <- c(
            base_name,
            paste0(base_name, ".rds"),
            paste0(base_name, ".RDS"),
            paste0(base_name, ".csv"),
            paste0(base_name, ".CSV"),
            paste0(base_name, ".tsv"),
            paste0(base_name, ".txt")
          )
          
          found_file <- NULL
          for (f in possible_files) {
            if (file.exists(f)) {
              found_file <- f
              break
            }
          }
          
          if (is.null(found_file)) {
            stop(paste("Required input file missing:", base_name))
          }
          
          ext <- tolower(tools::file_ext(found_file))
          if (ext == "rds") {
            return(readRDS(found_file))
          } else if (ext %in% c("csv", "tsv", "txt")) {
            sep <- if (ext == "csv") "," else "\t"
            res <- tryCatch({
              as.matrix(read.table(found_file, header = TRUE, row.names = 1, sep = sep, check.names = FALSE))
            }, error = function(e) {
              as.matrix(read.table(found_file, header = TRUE, sep = sep, check.names = FALSE))
            })
            return(res)
          } else {
            res <- tryCatch(readRDS(found_file), error = function(e) NULL)
            if (!is.null(res)) return(res)
            res <- tryCatch(as.matrix(read.table(found_file, header = TRUE, row.names = 1, check.names = FALSE)), error = function(e) NULL)
            if (!is.null(res)) return(res)
            stop(paste("Could not parse file:", found_file))
          }
        }
        
        # 1. Load User Input Files
        message("Loading input datasets...")
        Block1.PCA <- as.matrix(read_file("Block1.PCA"))
        Block2.PCA <- as.matrix(read_file("Block2.PCA"))
        ed.PCA     <- as.data.frame(read_file("ed.PCA"))
        
        # Ensure the experimental design has the expected column name "classname"
        if (!"classname" %in% colnames(ed.PCA)) {
          if (ncol(ed.PCA) == 1) {
            colnames(ed.PCA) <- "classname"
          } else {
            colnames(ed.PCA)[1] <- "classname"
          }
        }
        
        # 2. Create OmicsExpressionSet Objects
        message("Creating OmicsExpressionSet objects...")
        B1 <- createOmicsExpressionSet(Data=Block1.PCA, pData=ed.PCA,
                                       pDataDescr=c("classname"))
        B2 <- createOmicsExpressionSet(Data=Block2.PCA, pData=ed.PCA, 
                                       pDataDescr=c("classname"))
        
        # 3. Model Selection
        message("Running model selection...")
        ms <- modelSelection(Input=list(B1, B2), Rmax=3, fac.sel="single%",
                             varthreshold=0.03, center=TRUE, scale=TRUE, 
                             weight=TRUE, plot_common=FALSE, plot_dist=FALSE)
        
        # Save model selection results
        saveRDS(ms, "model_selection_results.rds")
        
        # Extract optimal components dynamically
        opt_Rcommon <- ms\$common\$comp
        if (is.null(opt_Rcommon)) {
          # Fallback if exact name differs
          nums <- Filter(is.numeric, ms\$common)
          opt_Rcommon <- if (length(nums) > 0) nums[[1]] else 2
        }
        opt_Rspecific <- as.numeric(unlist(ms\$dist))
        
        # 4. Component Analysis (DISCO-SCA, JIVE, O2PLS)
        message("Running component analysis using DISCO-SCA...")
        discoRes <- omicsCompAnalysis(Input=list(B1, B2), Names=c("expr", "mirna"),
                                      method="DISCOSCA", Rcommon=opt_Rcommon, Rspecific=opt_Rspecific,
                                      center=TRUE, scale=TRUE, weight=TRUE)
        
        message("Running component analysis using JIVE...")
        jiveRes <- omicsCompAnalysis(Input=list(B1, B2), Names=c("expr", "mirna"),
                                     method="JIVE", Rcommon=opt_Rcommon, Rspecific=opt_Rspecific,
                                     center=TRUE, scale=TRUE, weight=TRUE)
        
        message("Running component analysis using O2PLS...")
        o2plsRes <- omicsCompAnalysis(Input=list(B1, B2),Names=c("expr", "mirna"),
                                      method="O2PLS", Rcommon=opt_Rcommon, Rspecific=opt_Rspecific,
                                      center=TRUE, scale=TRUE, weight=TRUE)
        
        # Save component analysis results
        saveRDS(discoRes, "disco_results.rds")
        saveRDS(jiveRes, "jive_results.rds")
        saveRDS(o2plsRes, "o2pls_results.rds")
        
        # 5. Retrieve Scores, Loadings, and VAF
        message("Retrieving scores, loadings, and VAF...")
        scores_common <- getScores(discoRes, part="common")
        scores_dist1  <- getScores(discoRes, part="distinctive", block="1")
        scores_dist2  <- getScores(discoRes, part="distinctive", block="2")
        
        loadings_common1 <- getLoadings(discoRes, part="common", block="1")
        loadings_common2 <- getLoadings(discoRes, part="common", block="2")
        loadings_dist1   <- getLoadings(discoRes, part="distinctive", block="1")
        loadings_dist2   <- getLoadings(discoRes, part="distinctive", block="2")
        
        vaf_res       <- getVAF(discoRes)
        
        # Save retrieved scores, loadings, and VAF to files
        write.csv(as.data.frame(scores_common), "disco_scores_common.csv", row.names = TRUE)
        write.csv(as.data.frame(scores_dist1), "disco_scores_distinctive_block1.csv", row.names = TRUE)
        write.csv(as.data.frame(scores_dist2), "disco_scores_distinctive_block2.csv", row.names = TRUE)
        
        write.csv(as.data.frame(loadings_common1), "disco_loadings_common_block1.csv", row.names = TRUE)
        write.csv(as.data.frame(loadings_common2), "disco_loadings_common_block2.csv", row.names = TRUE)
        write.csv(as.data.frame(loadings_dist1), "disco_loadings_distinctive_block1.csv", row.names = TRUE)
        write.csv(as.data.frame(loadings_dist2), "disco_loadings_distinctive_block2.csv", row.names = TRUE)
        
        sink("disco_vaf_summary.txt")
        print(vaf_res)
        sink()
        
        # 6. Plotting Results
        message("Generating plots...")
        
        # Plot VAF
        pdf("disco_vaf_plot.pdf", width = 7, height = 6)
        print(plotVAF(discoRes))
        dev.off()
        
        # Plot Results (Scores)
        plot_comps <- if (opt_Rcommon >= 2) c(1, 2) else c(1, 1)
        pdf("disco_scores_plot.pdf", width = 8, height = 7)
        print(plotRes(object=discoRes, comps=plot_comps, what="scores", type="common",
                combined=FALSE, block=NULL, color="classname", shape=NULL, labels=NULL,
                background=TRUE, palette=NULL, pointSize=4, labelSize=NULL,
                axisSize=NULL, titleSize=NULL))
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_STATEGRA_OMICS_COMPONENT_ANALYSIS":',
        paste0('    STATegRa: ', as.character(packageVersion('STATegRa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omics_component_analysis.csv versions.yml
    """
}

workflow BIOC_STATEGRA_OMICS_COMPONENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Block1.PCA, Block2.PCA, ed.PCA ] ]

    main:
    BIOC_STATEGRA_OMICS_COMPONENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_STATEGRA_OMICS_COMPONENT_ANALYSIS.out.tables
    plots    = BIOC_STATEGRA_OMICS_COMPONENT_ANALYSIS.out.plots
    objects  = BIOC_STATEGRA_OMICS_COMPONENT_ANALYSIS.out.objects
    versions = BIOC_STATEGRA_OMICS_COMPONENT_ANALYSIS.out.versions
}
