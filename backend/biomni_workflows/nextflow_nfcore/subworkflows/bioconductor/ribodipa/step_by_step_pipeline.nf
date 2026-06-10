#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RiboDiPA — step_by_step_pipeline
// Run the RiboDiPA pipeline step-by-step to customize P-site mapping, binning, statistical testing, and visualization.
// Input: bam_path[1:4], bam_path[5]
// Container: quay.io/biocontainers/bioconductor-ribodipa:1.18.0--r45ha27e39d_0
// Requires: RiboDiPA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Map ribosome protected fragments to P-sites using psiteMapping()
//  * 2. [Core Analysis] Group P-site counts into bins of adaptive or fixed width using dataBinning()
//  * 3. [Core Analysis] Perform bin-by-bin differential pattern testing using diffPatternTest()
//  * 4. [Visualization & Output] Visualize mapped P-site tracks and binned test results using plotTrack() and plotTest()

nextflow.enable.dsl = 2

process BIOC_RIBODIPA_STEP_BY_STEP_PIPELINE {
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
    .bm_deps <- c("RiboDiPA")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(RiboDiPA)
    
    # -----------------------------------------------------------------------------
    # 1. Locate User Input Files in the Working Directory
    # -----------------------------------------------------------------------------
    # The pipeline expects exactly 4 BAM files and 1 GTF file in the working directory.
    bam_files <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    gtf_files <- list.files(pattern = "\\\\.gtf\$", full.names = TRUE)
    
    if (length(bam_files) < 4) {
        stop("Error: At least 4 BAM files are required in the working directory.")
    }
    if (length(gtf_files) < 1) {
        stop("Error: At least 1 GTF file is required in the working directory.")
    }
    
    # Construct the bam_path vector as specified: bam_path[1:4] are BAMs, bam_path[5] is GTF
    bam_path <- c(bam_files[1:4], gtf_files[1])
    
    # -----------------------------------------------------------------------------
    # 2. Define Experimental Design (Class Label)
    # -----------------------------------------------------------------------------
    classlabel <- data.frame(
        condition = c("mutant", "mutant", "wildtype", "wildtype"),
        comparison = c(2, 2, 1, 1)
    )
    # Set rownames to match the sample names derived from the BAM file basenames
    rownames(classlabel) <- gsub("\\\\.bam\$", "", basename(bam_path[1:4]))
    
    # -----------------------------------------------------------------------------
    # 3. Step-by-Step RiboDiPA Pipeline
    # -----------------------------------------------------------------------------
    
    # Stage 1: Map ribosome protected fragments to P-sites
    message("Mapping P-sites...")
    data.psite <- psiteMapping(bam_file_list = bam_path[1:4], 
        gtf_file = bam_path[5], psite.mapping = "auto", cores = 2)
    
    # Stage 2: Group P-site counts into bins
    message("Binning P-site data...")
    data.binned <- dataBinning(data = data.psite\$coverage, bin.width = 0,
        zero.omit = FALSE, bin.from.5UTR = TRUE, cores = 2)
    
    # Stage 3: Perform bin-by-bin differential pattern testing
    message("Performing differential pattern testing...")
    result.pst <- diffPatternTest(data = data.binned,
        classlabel = classlabel, method=c('gtxr', 'qvalue'))
    
    # Stage 4: Visualization and Track Plotting
    message("Generating plots...")
    pdf("ribodipa_plots.pdf", width = 10, height = 8)
    
    # Plot ribosome per nucleotide tracks of specified genes
    tryCatch({
        plotTrack(data = data.psite, genes.list = c("YDR050C", "YDR064W"),
            replicates = NULL, exons = FALSE)
    }, error = function(e) {
        message("Could not plot default genes YDR050C/YDR064W. Attempting with available genes...")
        available_genes <- names(data.psite\$coverage)
        if (length(available_genes) > 0) {
            plotTrack(data = data.psite, genes.list = head(available_genes, 2),
                replicates = NULL, exons = FALSE)
        } else {
            warning("No genes available for plotting.")
        }
    })
    
    # Plot binned ribosome tracks of significant genes
    tryCatch({
        plotTest(result = result.pst, genes.list = NULL, threshold = 0.05)
    }, error = function(e) {
        warning("plotTest failed or no significant genes found: ", e\$message)
    })
    
    dev.off()
    
    # -----------------------------------------------------------------------------
    # 4. Save Outputs
    # -----------------------------------------------------------------------------
    message("Saving results...")
    saveRDS(data.psite, "data_psite.rds")
    saveRDS(data.binned, "data_binned.rds")
    saveRDS(result.pst, "result_pst.rds")
    
    if (!is.null(result.pst\$gene)) {
        write.csv(result.pst\$gene[order(result.pst\$gene\$qvalue), ], 
                  "ribodipa_gene_results.csv", row.names = TRUE)
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_RIBODIPA_STEP_BY_STEP_PIPELINE":',
        paste0('    RiboDiPA: ', as.character(packageVersion('RiboDiPA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_pipeline.csv versions.yml
    """
}

workflow BIOC_RIBODIPA_STEP_BY_STEP_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_path[1:4], bam_path[5] ] ]

    main:
    BIOC_RIBODIPA_STEP_BY_STEP_PIPELINE(ch_input)

    emit:
    tables   = BIOC_RIBODIPA_STEP_BY_STEP_PIPELINE.out.tables
    plots    = BIOC_RIBODIPA_STEP_BY_STEP_PIPELINE.out.plots
    objects  = BIOC_RIBODIPA_STEP_BY_STEP_PIPELINE.out.objects
    versions = BIOC_RIBODIPA_STEP_BY_STEP_PIPELINE.out.versions
}
