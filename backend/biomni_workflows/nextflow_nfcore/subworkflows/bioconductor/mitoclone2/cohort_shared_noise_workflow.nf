#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mitoClone2 — cohort_shared_noise_workflow
// Identify somatic mitochondrial variants across a cohort of multiple individuals/samples by filtering out shared technical and biological noise, followed by clus
// Input: cohort_bams/
// Container: quay.io/biocontainers/bioconductor-mitoclone2:1.16.0--r45ha27e39d_0
// R packages: mitoClone2, pheatmap
// Bioconductor: 3.20 | R: 4.4
// Requires: mitoClone2, pheatmap
// Visualizations: heatmap, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Count nucleotides from BAM files
//  * 2. [Core Analysis] Call and filter mutations using mutationCallsFromCohort
//  * 3. [Core Analysis] Extract private mutations and pull counts using pullcountsVars
//  * 4. [Core Analysis] Reconstruct mutation matrix using mutationCallsFromMatrix
//  * 5. [Core Analysis] Cluster mutations and cells using quick_cluster

nextflow.enable.dsl = 2

process BIOC_MITOCLONE2_COHORT_SHARED_NOISE_WORKFLOW {
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
    .bm_deps <- c("mitoClone2", "pheatmap")
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
            
    # Loading required libraries
    library(mitoClone2)
    library(pheatmap)
    
    # ==========================================
    # STAGE 1: Count nucleotides from BAM files
    # ==========================================
    
    # Check for user input files in the working directory
    bam_dir <- "cohort_bams"
    multiplexed_bam <- "multiplexed_cohort.bam"
    is_multiplexed <- FALSE
    
    if (dir.exists(bam_dir)) {
      message("Found cohort_bams/ directory. Processing individual BAM files...")
      bam_files <- list.files(bam_dir, pattern = "\\\\.bam\$", full.names = TRUE)
      if (length(bam_files) == 0) {
        stop("Error: No BAM files found in cohort_bams/ directory.")
      }
      
      # Count nucleotides across the specified region
      example.counts <- baseCountsFromBamList(bamfiles = bam_files, sites = "chrM:1-16569", ncores = 1)
      names(example.counts) <- gsub("\\\\.bam\$", "", basename(bam_files))
      
    } else if (file.exists(multiplexed_bam)) {
      message("Found multiplexed_cohort.bam. Processing multiplexed BAM file...")
      
      # Count nucleotides across the specified region
      example.counts <- bam2R_10x(file = multiplexed_bam, sites = "chrM:1-16569", ncores = 1)
      is_multiplexed <- TRUE
      
    } else {
      stop("Error: Neither 'cohort_bams/' directory nor 'multiplexed_cohort.bam' was found in the working directory.")
    }
    
    # Create metadata and assign patient/clone IDs
    cell_names <- names(example.counts)
    
    if (is_multiplexed) {
      # For 10x multiplexed BAMs, the sample/patient ID is the suffix after the hyphen (e.g., "-1", "-2")
      patients <- gsub(".*-", "", cell_names)
    } else {
      # For individual BAMs, the patient ID is assumed to be the prefix before the underscore
      patients <- gsub("_.*", "", cell_names)
    }
    
    if (length(unique(patients)) < 2) {
      stop("Error: Cohort-based filtering requires at least two independent samples (patients).")
    }
    
    Example.meta <- data.frame(row.names = cell_names, Clone = patients)
    
    # Save the count data and metadata for reproducibility
    saveRDS(example.counts, "processed_base_counts.rds")
    write.csv(Example.meta, "cell_metadata.csv", row.names = TRUE)
    
    # ==========================================================
    # STAGE 2: Call and filter mutations using mutationCallsFromCohort
    # ==========================================================
    
    message("Calling mutations using cohort-based filtering...")
    Example <- mutationCallsFromCohort(
      example.counts, 
      MINFRAC = 0.01, 
      MINCELL = 8, 
      MINCELLS.PATIENT = 5, 
      patient = Example.meta\$Clone, 
      sites = "chrM:1-16569"
    )
    
    # Save the initial cohort mutation calls
    saveRDS(Example, "cohort_mutation_calls.rds")
    
    # Print mutant allele count column names for the first patient
    first_patient <- unique(patients)[1]
    if (first_patient %in% names(Example)) {
      print(colnames(getAlleleCount(Example[[first_patient]], "mutant")))
    } else {
      message(paste("Patient", first_patient, "not found in the mutation calls."))
    }
    
    # ==========================================================
    # STAGE 3: Extract private mutations and pull counts
    # ==========================================================
    
    message("Extracting private mutations...")
    valid_patients <- names(Example)[unlist(lapply(Example, function(x) !is.null(x)))]
    private.mutations <- unique(unlist(lapply(
      Example[valid_patients], 
      function(y) names(getVarsCandidate(y))
    )))
    
    # Save the list of private mutations
    write.csv(data.frame(PrivateMutation = private.mutations), "private_mutations.csv", row.names = FALSE)
    
    if (length(private.mutations) > 0) {
      private.mutations.df <- pullcountsVars(
        example.counts, 
        gsub("X(\\\\d+)([AGCT])\\\\.([AGCT])", "\\1 \\2>\\3", private.mutations)
      )
      
      # ==========================================================
      # STAGE 4: Reconstruct mutation matrix using mutationCallsFromMatrix
      # ==========================================================
      
      message("Reconstructing mutation matrix...")
      private.mutations.df <- mutationCallsFromMatrix(
        t(private.mutations.df\$M), 
        t(private.mutations.df\$N), 
        cluster = rep(TRUE, length(private.mutations))
      )
      saveRDS(private.mutations.df, "private_mutations_calls.rds")
      
      # ==========================================================
      # STAGE 5: Cluster mutations and cells using quick_cluster
      # ==========================================================
      
      message("Clustering mutations and cells...")
      pdf("mutation_clustering_heatmap.pdf", width = 10, height = 8)
      clustered <- quick_cluster(
        private.mutations.df, 
        binarize = TRUE, 
        drop_empty = TRUE, 
        clustering.method = "ward.D2", 
        annotation_col = Example.meta, 
        show_colnames = FALSE, 
        fontsize_row = 7
      )
      dev.off()
      
      message("Pipeline completed successfully. Outputs saved to the working directory.")
    } else {
      warning("No private mutations were identified. Skipping matrix reconstruction and clustering stages.")
      message("Pipeline completed with warnings. Initial mutation calls saved.")
    }

    writeLines(c(
        '"BIOC_MITOCLONE2_COHORT_SHARED_NOISE_WORKFLOW":',
        paste0('    mitoClone2: ', as.character(packageVersion('mitoClone2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cohort_shared_noise_workflow.csv versions.yml
    """
}

workflow BIOC_MITOCLONE2_COHORT_SHARED_NOISE_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cohort_bams/ ] ]

    main:
    BIOC_MITOCLONE2_COHORT_SHARED_NOISE_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MITOCLONE2_COHORT_SHARED_NOISE_WORKFLOW.out.tables
    plots    = BIOC_MITOCLONE2_COHORT_SHARED_NOISE_WORKFLOW.out.plots
    objects  = BIOC_MITOCLONE2_COHORT_SHARED_NOISE_WORKFLOW.out.objects
    versions = BIOC_MITOCLONE2_COHORT_SHARED_NOISE_WORKFLOW.out.versions
}
