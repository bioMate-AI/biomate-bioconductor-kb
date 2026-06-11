#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clusterSeq — posterior_likelihood_clustering
// Cluster genes by estimating the empirical Bayesian likelihood that they share the same expression structure across samples using baySeq.
// Input: ratThymus, cD.ratThymus
// Container: quay.io/biocontainers/bioconductor-clusterseq:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: baySeq, clusterSeq
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a countData object, define the density function, library sizes, and all possible models
//  * 2. [Input & Preparation] Estimate priors and likelihoods using baySeq (or load pre-calculated data)
//  * 3. [Core Analysis] Estimate the likelihood of identical models and monotonic ordering between genes using associatePosteriors
//  * 4. [Input & Preparation] Construct clusters using makeClusters with a specified threshold
//  * 5. [Visualization & Output] Optionally compare clusterings using wallace and plot profiles using plotCluster

nextflow.enable.dsl = 2

process BIOC_CLUSTERSEQ_POSTERIOR_LIKELIHOOD_CLUSTERING {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required libraries
        library(clusterSeq)
        library(baySeq)
        
        # ==========================================
        # 1. Load User Inputs from Working Directory
        # ==========================================
        
        message("Loading user input files...")
        
        # Read ratThymus (matrix or data frame of raw count data)
        if (file.exists("ratThymus.rds")) {
          ratThymus <- readRDS("ratThymus.rds")
        } else if (file.exists("ratThymus.csv")) {
          ratThymus <- as.matrix(read.csv("ratThymus.csv", row.names = 1))
        } else if (file.exists("ratThymus.txt")) {
          ratThymus <- as.matrix(read.table("ratThymus.txt", header = TRUE, row.names = 1))
        } else if (file.exists("ratThymus")) {
          ratThymus <- tryCatch(readRDS("ratThymus"), error = function(e) {
            as.matrix(read.table("ratThymus", header = TRUE, row.names = 1))
          })
        } else {
          stop("Required input file 'ratThymus' (RDS, CSV, or TXT) not found in the working directory.")
        }
        
        # Ensure ratThymus is a matrix
        if (is.data.frame(ratThymus)) {
          ratThymus <- as.matrix(ratThymus)
        }
        
        # Read cD.ratThymus (pre-calculated countData object or raw countData)
        if (file.exists("cD.ratThymus.rds")) {
          cD.ratThymus_input <- readRDS("cD.ratThymus.rds")
        } else if (file.exists("cD.ratThymus")) {
          cD.ratThymus_input <- readRDS("cD.ratThymus")
        } else {
          stop("Required input file 'cD.ratThymus' (RDS) not found in the working directory.")
        }
        
        # ==========================================
        # 2. Initialize and Process countData Object
        # ==========================================
        
        message("Initializing countData object...")
        replicates_vec <- cD.ratThymus_input@replicates
        cD.ratThymus <- new("countData", data = ratThymus, replicates = replicates_vec)
        densityFunction(cD.ratThymus) <- nbinomDensity
        libsizes(cD.ratThymus) <- getLibsizes(cD.ratThymus)
        cD.ratThymus <- allModels(cD.ratThymus)
        
        # Overwrite/update with the user-provided pre-calculated object if posteriors are present
        if (inherits(cD.ratThymus_input, "countData") && length(cD.ratThymus_input@posteriors) > 0) {
          message("Using pre-calculated posteriors from loaded cD.ratThymus...")
          cD.ratThymus <- cD.ratThymus_input
        } else {
          message("Posteriors not found in loaded object. Estimating priors and likelihoods using baySeq...")
          library(parallel)
          cl <- makeCluster(min(4, detectCores()))
          cD.ratThymus <- getPriors(cD.ratThymus, consensus = TRUE, cl = cl)
          cD.ratThymus <- getLikelihoods(cD.ratThymus, cl = cl)
          stopCluster(cl)
        }
        
        # ==========================================
        # 3. Posterior Likelihood Clustering
        # ==========================================
        
        message("Subsetting data and associating posteriors...")
        cD.ratThymus <- cD.ratThymus[1:min(1000, nrow(cD.ratThymus)),]
        aM <- associatePosteriors(cD.ratThymus)
        
        message("Constructing clusters...")
        sX <- makeClusters(aM, cD.ratThymus, threshold = 0.5)
        
        # Save primary clustering results
        saveRDS(sX, "sX_clusters.rds")
        cluster_df <- data.frame(Gene = as.vector(unlist(sX)), Cluster = rep(seq_along(sX), lengths(sX)))
        write.csv(cluster_df, "cluster_assignments.csv", row.names = FALSE)
        message("Saved cluster assignments to 'cluster_assignments.csv' and 'sX_clusters.rds'.")
        
        # ==========================================
        # 4. Optional: Compare Clusterings (Wallace)
        # ==========================================
        
        tryCatch({
          message("Generating comparison clustering (mkClustRC) via K-means workflow...")
          libsizes_rt <- getLibsizes(data = ratThymus)
          ratThymus_norm <- ratThymus
          ratThymus_norm[ratThymus_norm == 0] <- 1
          normRT <- log2(ratThymus_norm %*% diag(1/libsizes_rt) * mean(libsizes_rt))
          normRT <- normRT[1:min(1000, nrow(normRT)),]
        
          # Run kCluster with a lower bootstrap count for speed in pipeline execution
          kClustR <- kCluster(normRT, replicates = replicates_vec, matrixFile = "kclust_matrix_newForceReps.txt.gz", B = 100)
          mkClustRC <- makeClustersFF("kclust_matrix_newForceReps.txt.gz", method = "complete", cut.height = 5)
          
          message("Comparing clusterings using Wallace statistic...")
          wallace_result <- wallace(sX, mkClustRC)
          print(wallace_result)
          write.csv(as.data.frame(wallace_result), "wallace_comparison.csv", row.names = TRUE)
          message("Saved Wallace comparison to 'wallace_comparison.csv'.")
        }, error = function(e) {
          warning("Could not perform Wallace comparison: ", e\$message)
        })
        
        # ==========================================
        # 5. Plot Profiles
        # ==========================================
        
        message("Plotting cluster profiles...")
        pdf("cluster_profiles.pdf", width = 10, height = 7)
        par(mfrow = c(2,3))
        if (length(sX) > 0) {
          plotCluster(sX[seq_len(min(6, length(sX)))], cD.ratThymus)
        }
        dev.off()
        message("Saved cluster profile plots to 'cluster_profiles.pdf'.")
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CLUSTERSEQ_POSTERIOR_LIKELIHOOD_CLUSTERING":',
        paste0('    clusterSeq: ', as.character(packageVersion('clusterSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_posterior_likelihood_clustering.csv versions.yml
    """
}

workflow BIOC_CLUSTERSEQ_POSTERIOR_LIKELIHOOD_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ratThymus, cD.ratThymus ] ]

    main:
    BIOC_CLUSTERSEQ_POSTERIOR_LIKELIHOOD_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_CLUSTERSEQ_POSTERIOR_LIKELIHOOD_CLUSTERING.out.tables
    plots    = BIOC_CLUSTERSEQ_POSTERIOR_LIKELIHOOD_CLUSTERING.out.plots
    objects  = BIOC_CLUSTERSEQ_POSTERIOR_LIKELIHOOD_CLUSTERING.out.objects
    versions = BIOC_CLUSTERSEQ_POSTERIOR_LIKELIHOOD_CLUSTERING.out.versions
}
