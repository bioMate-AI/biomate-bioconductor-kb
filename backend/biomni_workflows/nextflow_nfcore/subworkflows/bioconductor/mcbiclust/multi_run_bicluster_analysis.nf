#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MCbiclust — multi_run_bicluster_analysis
// Run the stochastic MCbiclust algorithm multiple times to identify multiple distinct correlation patterns and consensus biclusters.
// Input: CCLE_small
// Container: quay.io/biocontainers/bioconductor-mcbiclust:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MCbiclust, dplyr, ggplot2, gplots
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run FindSeed multiple times with different random seeds
//  * 2. [Core Analysis] Calculate correlation vectors for each run using CVEval
//  * 3. [Input & Preparation] Create a correlation vector matrix
//  * 4. [Core Analysis] Cluster the correlation vectors using SilhouetteClustGroups
//  * 5. [Core Analysis] Calculate average correlation vectors for each cluster
//  * 6. [Input & Preparation] Prepare for sorting using MultiSampleSortPrep
//  * 7. [Core Analysis] Sort samples for each cluster using SampleSort
//  * 8. [Core Analysis] Calculate PC1, threshold, and align PC1 for each cluster

nextflow.enable.dsl = 2

process BIOC_MCBICLUST_MULTI_RUN_BICLUSTER_ANALYSIS {
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
    library(MCbiclust)
    library(ggplot2)
    library(gplots)
    library(dplyr)
    library(MASS)
    
    # Read user input
    if (file.exists("CCLE_small.rds")) {
      CCLE_small <- readRDS("CCLE_small.rds")
    } else if (file.exists("CCLE_small.csv")) {
      CCLE_small <- as.matrix(read.csv("CCLE_small.csv", row.names = 1))
    } else if (file.exists("CCLE_small")) {
      CCLE_small <- tryCatch(readRDS("CCLE_small"), error = function(e) {
        as.matrix(read.csv("CCLE_small", row.names = 1))
      })
    } else {
      stop("Required input file 'CCLE_small' not found in the working directory.")
    }
    
    # Ensure CCLE_small is a matrix
    CCLE_small <- as.matrix(CCLE_small)
    
    # 1. Run FindSeed multiple times with different random seeds
    CCLE.multi.seed <- list()
    initial.seed1 <- list()
    
    gene_indices <- seq_len(min(500, nrow(CCLE_small)))
    
    for(i in seq(100)){
      set.seed(i)
      initial.seed1[[i]] <- sample(seq(length = dim(CCLE_small)[2]),10)
      CCLE.multi.seed[[i]] <- FindSeed(gem = CCLE_small[gene_indices, , drop = FALSE],
                                       seed.size = 10,
                                       iterations = 500,
                                       initial.seed = initial.seed1[[i]])
    }
    
    # 2. Calculate correlation vectors for each run using CVEval
    CCLE.cor.vec.multi <- list()
    
    for(i in seq(100)){
      CCLE.cor.vec.multi[[i]] <- CVEval(gem.part = CCLE_small[gene_indices, , drop = FALSE],
                                        gem.all = CCLE_small,
                                        seed = CCLE.multi.seed[[i]],
                                        splits = 10)
    }
    
    # 3. Create a correlation vector matrix
    len.a <- length(CCLE.cor.vec.multi[[1]])
    len.b <- length(CCLE.cor.vec.multi)
    multi.run.cor.vec.mat <- matrix(0,len.a,len.b)
    for(i in 1:100){
      multi.run.cor.vec.mat[,i] <- CCLE.cor.vec.multi[[i]]
    }
    
    # Save the correlation vector matrix
    write.csv(multi.run.cor.vec.mat, "multi_run_cor_vec_mat.csv", row.names = TRUE)
    
    # 4. Cluster the correlation vectors using SilhouetteClustGroups
    pdf("silhouette_plots.pdf")
    multi.clust.groups <- SilhouetteClustGroups(multi.run.cor.vec.mat,
                                                max.clusters = 20,
                                                plots = TRUE, rand.vec = FALSE)
    dev.off()
    
    # Save cluster groups
    saveRDS(multi.clust.groups, "multi_clust_groups.rds")
    
    # 5. Calculate average correlation vectors for each cluster
    gene.names <- row.names(CCLE_small)
    av.corvec.fun <- function(x) rowMeans(multi.run.cor.vec.mat[, x, drop = FALSE])
    average.corvec <- lapply(X = multi.clust.groups,
                             FUN = av.corvec.fun)
    
    saveRDS(average.corvec, "average_corvec.rds")
    
    # 6. Prepare for sorting using MultiSampleSortPrep
    CCLE.samp.multi.sort <- list()
    multi.prep <- MultiSampleSortPrep(gem = CCLE_small,
                                      av.corvec = average.corvec,
                                      top.genes.num = 750,
                                      groups = multi.clust.groups,
                                      initial.seeds =  CCLE.multi.seed)
    
    # 7. Sort samples for each cluster using SampleSort
    for (j in seq_along(multi.clust.groups)) {
      CCLE.samp.multi.sort[[j]] <- SampleSort(gem = multi.prep[[1]][[j]],
                                              seed = multi.prep[[2]][[j]])
    }
    
    saveRDS(CCLE.samp.multi.sort, "CCLE_samp_multi_sort.rds")
    
    # 8. Calculate PC1, threshold, and align PC1 for each cluster
    pc1.vec.multi <- list()
    CCLE.bic.multi <- list()
    
    for (j in seq_along(multi.clust.groups)) {
      pc1.vec.multi[[j]] <- PC1VecFun(top.gem = multi.prep[[1]][[j]],
                                      seed.sort = CCLE.samp.multi.sort[[j]], n = 10)
      
      CCLE.bic.multi[[j]] <- ThresholdBic(cor.vec = average.corvec[[j]],
                                          sort.order = CCLE.samp.multi.sort[[j]],
                                          pc1 = pc1.vec.multi[[j]], samp.sig = 0.05)
      
      pc1.vec.multi[[j]] <- PC1Align(gem = CCLE_small, pc1 = pc1.vec.multi[[j]],
                                     sort.order = CCLE.samp.multi.sort[[j]],
                                     cor.vec = average.corvec[[j]], bic = CCLE.bic.multi[[j]])
    }
    
    # Save final PC1 vectors and Bicluster thresholds
    saveRDS(pc1.vec.multi, "pc1_vec_multi.rds")
    saveRDS(CCLE.bic.multi, "CCLE_bic_multi.rds")
    
    # Export bicluster genes and samples to CSV
    for (i in seq_along(CCLE.bic.multi)) {
      write.csv(data.frame(Genes = CCLE.bic.multi[[i]][[1]]), 
                file = paste0("bicluster_", i, "_genes.csv"), row.names = FALSE)
      write.csv(data.frame(Samples = CCLE.bic.multi[[i]][[2]]), 
                file = paste0("bicluster_", i, "_samples.csv"), row.names = FALSE)
    }
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_MCBICLUST_MULTI_RUN_BICLUSTER_ANALYSIS":',
        paste0('    MCbiclust: ', as.character(packageVersion('MCbiclust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_run_bicluster_analysis.csv versions.yml
    """
}

workflow BIOC_MCBICLUST_MULTI_RUN_BICLUSTER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CCLE_small ] ]

    main:
    BIOC_MCBICLUST_MULTI_RUN_BICLUSTER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MCBICLUST_MULTI_RUN_BICLUSTER_ANALYSIS.out.tables
    plots    = BIOC_MCBICLUST_MULTI_RUN_BICLUSTER_ANALYSIS.out.plots
    objects  = BIOC_MCBICLUST_MULTI_RUN_BICLUSTER_ANALYSIS.out.objects
    versions = BIOC_MCBICLUST_MULTI_RUN_BICLUSTER_ANALYSIS.out.versions
}
