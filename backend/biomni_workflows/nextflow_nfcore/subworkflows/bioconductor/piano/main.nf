#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: piano — microarray_preprocessing_and_differential_expression
// Load raw or pre-normalized microarray data, perform quality control, and identify differentially expressed genes to generate statistics for GSA.
// Input: norm_data.txt.gz, setup.txt
// Container: quay.io/biocontainers/bioconductor-piano:2.26.0--r45hdfd78af_0
// R packages: biomaRt, piano
// Bioconductor: 3.20 | R: 4.4
// Requires: piano
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define experimental setup
//  * 2. [Input & Preparation] Load and normalize microarray data using loadMAdata
//  * 3. [Core Analysis] Run quality control diagnostics using runQC
//  * 4. [Core Analysis] Extract experimental factors using extractFactors
//  * 5. [Core Analysis] Perform differential expression analysis using diffExp

nextflow.enable.dsl = 2

process BIOC_PIANO_MICROARRAY_PREPROCESSING_AND_DIFFERENTIAL_EXPRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("biomaRt", "piano")
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
        
        # Load the required piano library
        library(piano)
        
        # 1. Define experimental setup by reading the user-provided setup.txt
        # The file is tab-delimited and maps samples (rownames/first column) to conditions
        mySetup <- read.delim("setup.txt", row.names=1, header=TRUE, stringsAsFactors=FALSE)
        
        # 2. Load and normalize microarray data using loadMAdata
        # Reading from the current working directory where norm_data.txt.gz is located
        myArrayData <- loadMAdata(datadir=".", 
                                  dataNorm="norm_data.txt.gz", 
                                  setup=mySetup)
        
        # Display loaded object details to standard output
        print(myArrayData)
        print(myArrayData\$setup)
        if (!is.null(myArrayData\$annotation)) {
          print(myArrayData\$annotation[1:10,])
        }
        
        # 3. Run quality control diagnostics using runQC
        # We wrap these in a PDF to capture the generated plots
        pdf("QC_diagnostics.pdf", width=10, height=8)
        tryCatch({
          runQC(myArrayData)
        }, error = function(e) {
          warning("Standard runQC failed (expected if starting from pre-normalized data): ", e\$message)
        })
        
        tryCatch({
          runQC(myArrayData, rnaDeg=FALSE, nuseRle=FALSE, hist=FALSE,
                boxplot=FALSE, pca=TRUE)
        }, error = function(e) {
          warning("PCA-only runQC failed: ", e\$message)
        })
        
        tryCatch({
          runQC(myArrayData, rnaDeg=FALSE, nuseRle=FALSE, hist=FALSE,
                boxplot=FALSE, pca=TRUE, colors=c("cyan","orange"))
        }, error = function(e) {
          warning("Colored PCA runQC failed: ", e\$message)
        })
        dev.off()
        
        # 4. Extract experimental factors using extractFactors
        factors_info <- extractFactors(myArrayData)
        print(factors_info)
        
        # 5. Perform differential expression analysis using diffExp
        # We wrap this in a PDF to capture Venn, polar, heatmap, and volcano plots
        pdf("differential_expression_plots.pdf", width=10, height=8)
        
        unique_factors <- factors_info\$uniqueFactors
        if (length(unique_factors) < 2) {
          stop("At least two unique conditions are required for differential expression.")
        }
        
        contrast_pairs <- combn(unique_factors, 2)
        my_contrasts <- apply(contrast_pairs, 2, function(x) paste(x[1], "-", x[2]))
        
        pfc <- diffExp(myArrayData, contrasts=my_contrasts)
        dev.off()
        
        # Sort and save results for each contrast
        for (k in seq_along(my_contrasts)) {
          contrast_name <- my_contrasts[k]
          safe_name <- gsub(" - ", "_vs_", contrast_name)
          
          ii <- sort(pfc\$resTable[[k]]\$adj.P.Val, index.return=TRUE)\$ix
          contrast_sorted <- pfc\$resTable[[k]][ii, ]
          write.csv(contrast_sorted, paste0("diffExp_", safe_name, ".csv"), row.names=FALSE)
          print(paste("Top 5 genes for", contrast_name, ":"))
          print(pfc\$resTable[[k]][ii[1:5],])
        }
        
        # Save the complete differential expression object as an RDS file for downstream GSA
        saveRDS(pfc, "diffExp_results.rds")

    writeLines(c(
        '"BIOC_PIANO_MICROARRAY_PREPROCESSING_AND_DIFFERENTIAL_EXPRESSION":',
        paste0('    piano: ', as.character(packageVersion('piano')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_preprocessing_and_differential_expression.csv versions.yml
    """
}

workflow BIOC_PIANO_MICROARRAY_PREPROCESSING_AND_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ norm_data.txt.gz, setup.txt ] ]

    main:
    BIOC_PIANO_MICROARRAY_PREPROCESSING_AND_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_PIANO_MICROARRAY_PREPROCESSING_AND_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_PIANO_MICROARRAY_PREPROCESSING_AND_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_PIANO_MICROARRAY_PREPROCESSING_AND_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_PIANO_MICROARRAY_PREPROCESSING_AND_DIFFERENTIAL_EXPRESSION.out.versions
}
