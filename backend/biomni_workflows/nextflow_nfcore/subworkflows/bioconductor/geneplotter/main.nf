#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geneplotter — whole_genome_expression_plotting
// Visualize expression levels across all chromosomes using a reference genome
// Input: sample.ExpressionSet, hgu95av2
// Container: quay.io/biocontainers/bioconductor-geneplotter:1.88.0--r45hdfd78af_0
// R packages: Biobase, annotate, geneplotter, hgu95av2.db
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, geneplotter, hgu95av2.db
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load expression data and calculate statistics
//  * 2. [Input & Preparation] Build a chromLocation object using buildChromLocation
//  * 3. [Visualization & Output] Initialize the chromosome plot using cPlot
//  * 4. [Visualization & Output] Color the genes on the chromosome plot using cColor

nextflow.enable.dsl = 2

process BIOC_GENEPLOTTER_WHOLE_GENOME_EXPRESSION_PLOTTING {
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
    .bm_deps <- c("Biobase", "annotate", "geneplotter", "hgu95av2.db")
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
            library(geneplotter)
            library(Biobase)
            library(hgu95av2.db)
            
            # 1. Load expression data and calculate statistics
            # Read the ExpressionSet object from the working directory
            if (file.exists("sample.ExpressionSet")) {
              eset <- readRDS("sample.ExpressionSet")
            } else if (file.exists("sample.ExpressionSet.rds")) {
              eset <- readRDS("sample.ExpressionSet.rds")
            } else {
              stop("Error: sample.ExpressionSet file not found in the working directory.")
            }
            
            # Define the t-test function as documented
            mytt <- function(y, cov2) {
              ys <- split( y, cov2 )
              t.test( ys[[1]], ys[[2]] )
            }
            
            # Apply the t-test across features
            ttout <- esApply(eset, 1, mytt, eset\$type)
            
            # Extract means and classify into deciles
            s1means <- sapply(ttout, function(x) x\$estimate[1])
            s2means <- sapply(ttout, function(x) x\$estimate[2])
            deciles <- quantile(c(s1means, s2means), probs=seq(0,1,.1))
            s1class <- cut(s1means, deciles)
            names(s1class) <- names(s1means)
            s2class <- cut(s2means, deciles)
            names(s2class) <- names(s2means)
            
            # Save statistics to a CSV file
            stats_df <- data.frame(
              Gene = names(s1means),
              Group1_Mean = s1means,
              Group2_Mean = s2means,
              Group1_Class = as.character(s1class),
              Group2_Class = as.character(s2class),
              stringsAsFactors = FALSE
            )
            write.csv(stats_df, "expression_statistics.csv", row.names = FALSE)
            
            # 2. Build a chromLocation object using buildChromLocation
            chrObj <- buildChromLocation("hgu95av2")
            saveRDS(chrObj, "chrom_location.rds")
            
            # 3 & 4. Initialize the chromosome plot and color the genes
            # Set up PDF output device
            pdf("chrom_expression_plot.pdf", width = 12, height = 8)
            
            cols <- dChip.colors(10)
            def.par <- par(no.readonly = TRUE) # save default, for resetting...
            nf <- layout(matrix(1:3, nr=1), widths=c(5,5,2))
            
            # Plot Group 1
            cPlot(chrObj)
            cColor(featureNames(eset), cols[s1class], chrObj)
            
            # Plot Group 2
            cPlot(chrObj)
            cColor(featureNames(eset), cols[s2class], chrObj)
            
            # Plot color legend
            image(1, 1:10, matrix(1:10, nc=10), col=cols, axes=FALSE, xlab="", ylab="")
            axis(2, at=(1:10), labels=levels(s1class), las=1)
            
            # Reset par and close device
            par(def.par)
            dev.off()

    writeLines(c(
        '"BIOC_GENEPLOTTER_WHOLE_GENOME_EXPRESSION_PLOTTING":',
        paste0('    geneplotter: ', as.character(packageVersion('geneplotter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_whole_genome_expression_plotting.csv versions.yml
    """
}

workflow BIOC_GENEPLOTTER_WHOLE_GENOME_EXPRESSION_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.ExpressionSet, hgu95av2 ] ]

    main:
    BIOC_GENEPLOTTER_WHOLE_GENOME_EXPRESSION_PLOTTING(ch_input)

    emit:
    tables   = BIOC_GENEPLOTTER_WHOLE_GENOME_EXPRESSION_PLOTTING.out.tables
    plots    = BIOC_GENEPLOTTER_WHOLE_GENOME_EXPRESSION_PLOTTING.out.plots
    objects  = BIOC_GENEPLOTTER_WHOLE_GENOME_EXPRESSION_PLOTTING.out.objects
    versions = BIOC_GENEPLOTTER_WHOLE_GENOME_EXPRESSION_PLOTTING.out.versions
}
