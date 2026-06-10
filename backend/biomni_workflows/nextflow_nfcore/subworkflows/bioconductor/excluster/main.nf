#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: excluster — differential_splicing_analysis
// Perform a complete differential splicing analysis from GTF and BAM files, identify differentially spliced genes, plot exon log2 fold changes, and format results
// Input: GTF_file, bamFiles
// Container: quay.io/biocontainers/bioconductor-excluster:1.28.0--r45hdfd78af_0
// R packages: ExCluster
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EXCLUSTER_DIFFERENTIAL_SPLICING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-excluster:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("ExCluster")
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
    
    # Load required libraries
    library(ExCluster)
    
    # ==========================================
    # 1. Input File Detection & Setup
    # ==========================================
    
    # Detect GTF file in the working directory
    gtf_files <- list.files(pattern = "\\\\.gtf\$", ignore.case = TRUE)
    if (length(gtf_files) > 0) {
      GTF_file <- gtf_files[1]
    } else {
      GTF_file <- "annotation.gtf"
    }
    
    # Detect BAM files in the working directory
    bamFiles <- list.files(pattern = "\\\\.bam\$", ignore.case = TRUE, full.names = TRUE)
    
    # Validate input files
    if (!file.exists(GTF_file)) {
      stop(paste("Error: GTF file not found at:", GTF_file, 
                 "\nPlease ensure a GTF file is present in the working directory."))
    }
    if (length(bamFiles) == 0) {
      stop("Error: No BAM files found in the working directory. Please provide aligned RNA-seq BAM files.")
    }
    
    # Dynamically generate sample names from BAM file names
    sampleNames <- gsub("\\\\.bam\$", "", basename(bamFiles), ignore.case = TRUE)
    
    # Assign condition numbers (split samples evenly between condition 1 and condition 2)
    n_samples <- length(bamFiles)
    condNums <- rep(c(1, 2), each = ceiling(n_samples / 2))[1:n_samples]
    
    message("--- Pipeline Configuration ---")
    message("GTF File: ", GTF_file)
    message("BAM Files detected: ", n_samples)
    for (i in seq_along(bamFiles)) {
      message("  - ", bamFiles[i], " (Sample Name: ", sampleNames[i], ", Condition: ", condNums[i], ")")
    }
    message("------------------------------")
    
    # ==========================================
    # 2. Run ExCluster Workflow
    # ==========================================
    
    # Stage 1: Convert GTF to flattened GFF format
    message("Stage 1: Converting GTF to flattened GFF format...")
    GFF <- GFF_convert(GTF.File=GTF_file)
    
    # Stage 2: Count and normalize reads per exon bin from BAM files
    message("Stage 2: Counting and normalizing reads per exon bin...")
    normCounts <- processCounts(bam.Files=bamFiles, sample.Names=sampleNames, annot.GFF=GFF, paired.Reads=TRUE)
    
    # Stage 3: Run core differential splicing analysis
    message("Stage 3: Running core differential splicing analysis...")
    ExClust_Results <- ExCluster(exon.Counts=normCounts, cond.Nums=condNums, annot.GFF=GFF, combine.Exons=FALSE)
    
    # Stage 4: Plot exon log2 fold changes for significant genes
    message("Stage 4: Plotting exon log2 fold changes...")
    outDir <- "./Images/"
    if (!dir.exists(outDir)) {
      dir.create(outDir, recursive = TRUE)
    }
    plotExonlog2FC(results.Data=ExClust_Results, out.Dir=outDir, plot.Type="PNG")
    
    # Stage 5: Convert results to a GRanges object
    message("Stage 5: Converting results to GRanges object...")
    GRanges.ExClustResults <- GRangesFromExClustResults(results.ExClust=ExClust_Results)
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    message("Saving pipeline results...")
    
    # Save the main ExCluster results table
    write.csv(ExClust_Results, file = "ExCluster_Results.csv", row.names = FALSE)
    
    # Save normalized exon counts
    write.csv(normCounts, file = "Normalized_Exon_Counts.csv", row.names = TRUE)
    
    # Save GRanges object
    saveRDS(GRanges.ExClustResults, file = "GRanges_ExClustResults.rds")
    
    # Save flattened GFF annotation
    saveRDS(GFF, file = "Flattened_GFF_Annotation.rds")
    
    message("Pipeline completed successfully! Outputs saved to the working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_EXCLUSTER_DIFFERENTIAL_SPLICING_ANALYSIS":
        excluster: \$(Rscript -e 'cat(as.character(packageVersion("excluster")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_splicing_analysis.csv versions.yml
    """
}

workflow BIOC_EXCLUSTER_DIFFERENTIAL_SPLICING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GTF_file, bamFiles ] ]

    main:
    BIOC_EXCLUSTER_DIFFERENTIAL_SPLICING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EXCLUSTER_DIFFERENTIAL_SPLICING_ANALYSIS.out.tables
    plots    = BIOC_EXCLUSTER_DIFFERENTIAL_SPLICING_ANALYSIS.out.plots
    objects  = BIOC_EXCLUSTER_DIFFERENTIAL_SPLICING_ANALYSIS.out.objects
    versions = BIOC_EXCLUSTER_DIFFERENTIAL_SPLICING_ANALYSIS.out.versions
}
