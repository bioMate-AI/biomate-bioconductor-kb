#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NOISeq — differential_expression_analysis
// Identify differentially expressed genes using NOISeq (for technical replicates or no replicates) or NOISeqBIO (for biological replicates), and visualize results
// Input: mydata
// Container: quay.io/biocontainers/bioconductor-noiseq:2.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: NOISeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run differential expression analysis using noiseq or noiseqbio
//  * 2. [Core Analysis] Extract differentially expressed features using degenes
//  * 3. [Visualization & Output] Visualize differential expression results using DE.plot

nextflow.enable.dsl = 2

process BIOC_NOISEQ_DIFFERENTIAL_EXPRESSION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("NOISeq")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load the NOISeq library
    library(NOISeq)
    
    # 1. Read User Input
    # The pipeline reads the 'mydata' file (NOISeq eSet object) from the working directory.
    if (file.exists("mydata")) {
      mydata <- readRDS("mydata")
    } else if (file.exists("mydata.rds")) {
      mydata <- readRDS("mydata.rds")
    } else {
      stop("Error: Input file 'mydata' or 'mydata.rds' not found in the working directory.")
    }
    
    # Extract factors to determine experimental design dynamically
    factors_df <- pData(mydata)
    
    if (ncol(factors_df) == 0) {
      stop("Error: No factors found in the input data.")
    }
    
    # Use the first factor for differential expression analysis
    myfactor <- colnames(factors_df)[1]
    myconditions <- levels(as.factor(factors_df[[myfactor]]))
    
    if (length(myconditions) < 2) {
      stop("Error: The selected factor must have at least two levels to perform differential expression.")
    }
    
    cond1 <- myconditions[1]
    cond2 <- myconditions[2]
    
    # Determine if there are replicates for the selected conditions
    replicates_per_cond <- table(factors_df[[myfactor]])
    has_replicates <- any(replicates_per_cond[c(cond1, cond2)] > 1)
    
    # 2. Run Differential Expression Analysis
    # Adapt to the user's actual experimental design
    deg_source <- NULL
    mynoiseqbio <- NULL
    myresults <- NULL
    
    if (has_replicates) {
      print(paste0("Running noiseqbio (biological replicates) on factor '", myfactor, "'..."))
      mynoiseqbio <- tryCatch({
        noiseqbio(mydata, k = 0.5, norm = "tmm", factor = myfactor, conditions = c(cond1, cond2), lc = 0, r = 20, adj = 1.5, plot = FALSE, a0per = 0.9, random.seed = 12345, filter = 2)
      }, error = function(e) {
        warning("Failed to run noiseqbio: ", e\$message)
        NULL
      })
      deg_source <- mynoiseqbio
    } else {
      print(paste0("Running noiseq (no replicates) on factor '", myfactor, "'..."))
      myresults <- tryCatch({
        noiseq(mydata, factor = myfactor, conditions = c(cond1, cond2), k = NULL, norm = "tmm", pnr = 0.2, nss = 5, v = 0.02, lc = 0, replicates = "no")
      }, error = function(e) {
        warning("Failed to run noiseq (no replicates): ", e\$message)
        NULL
      })
      deg_source <- myresults
    }
    
    # 3. Extract Differentially Expressed Features
    if (!is.null(deg_source)) {
      print("Extracting differentially expressed genes...")
      mynoiseq.deg <- degenes(deg_source, q = 0.8, M = NULL)
      mynoiseq.deg1 <- degenes(deg_source, q = 0.8, M = "up")
      mynoiseq.deg2 <- degenes(deg_source, q = 0.8, M = "down")
    
      # Save extracted DEGs to CSV files
      write.csv(mynoiseq.deg, "mynoiseq_deg_all.csv", row.names = TRUE)
      write.csv(mynoiseq.deg1, "mynoiseq_deg_up.csv", row.names = TRUE)
      write.csv(mynoiseq.deg2, "mynoiseq_deg_down.csv", row.names = TRUE)
    } else {
      warning("No successful differential expression analysis object available to extract DEGs.")
    }
    
    # Save RDS objects of the analysis results
    if (!is.null(myresults)) saveRDS(myresults, "myresults.rds")
    if (!is.null(mynoiseqbio)) saveRDS(mynoiseqbio, "mynoiseqbio.rds")
    
    # 4. Visualize Differential Expression Results
    if (!is.null(deg_source)) {
      print("Generating DE plots...")
      pdf("DE_plots.pdf", width = 10, height = 8)
    
      tryCatch({
        DE.plot(deg_source, q = 0.9, graphic = "expr", log.scale = TRUE)
      }, error = function(e) warning("Failed DE.plot (expr): ", e\$message))
    
      tryCatch({
        DE.plot(deg_source, q = 0.8, graphic = "MD")
      }, error = function(e) warning("Failed DE.plot (MD): ", e\$message))
    
      tryCatch({
        DE.plot(deg_source, chromosomes = c(1,2), log.scale = TRUE, join = FALSE, q = 0.8, graphic = "chrom")
      }, error = function(e) warning("Failed DE.plot (chrom): ", e\$message))
    
      tryCatch({
        DE.plot(deg_source, chromosomes = NULL, q = 0.8, graphic = "distr")
      }, error = function(e) warning("Failed DE.plot (distr): ", e\$message))
    
      dev.off()
      print("Plots saved to DE_plots.pdf")
    } else {
      warning("No successful differential expression analysis object available to generate plots.")
    }
    
    print("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_NOISEQ_DIFFERENTIAL_EXPRESSION_ANALYSIS":',
        paste0('    NOISeq: ', as.character(packageVersion('NOISeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_expression_analysis.csv versions.yml
    """
}

workflow BIOC_NOISEQ_DIFFERENTIAL_EXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mydata ] ]

    main:
    BIOC_NOISEQ_DIFFERENTIAL_EXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_NOISEQ_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_NOISEQ_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_NOISEQ_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.objects
    versions = BIOC_NOISEQ_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.versions
}
