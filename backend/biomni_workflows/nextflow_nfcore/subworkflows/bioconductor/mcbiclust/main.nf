#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MCbiclust
// Custom made algorithm and associated methods for finding, visualising and analysing biclusters in la
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MCbiclust/inst/doc/MCbiclust_vignette.R
// Upstream  : GSVA, MASS, devtools, dplyr, gProfileR
// Downstream: none
//
// Install: BiocManager::install("MCbiclust")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MCBICLUST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mcbiclust"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mcbiclust:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mcbiclust:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mcbiclust_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mcbiclust_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mcbiclust_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CVEval)
    library(ForkClassifier)
    library(GOEnrichmentAnalysis)
    library(MultiSampleSortPrep)
    library(PC1Align)
    library(PC1VecFun)
    library(PointScoreCalc)
    library(SilhouetteClustGroups)
    library(ThresholdBic)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(CCLE_small)
    data(Mitochondrial_genes)
    # --- List [] ---
    # Key functions: labels
    ---------------------------------------------------------------------
    CCLE.groups <- list(labels(CCLE.heat$rowDendrogram[[1]]),
                        labels(CCLE.heat$rowDendrogram[[2]]))
    # --- Cveval [] ---
    # Key functions: CVEval
    ---------------------------------------------------------------------
    CCLE.cor.vec <- CVEval(gem.part = CCLE.mito,
                            gem.all = CCLE_small,
                            seed = CCLE.seed, splits = 10)
    # --- Numeric [] ---
    # Key functions: PC1VecFun
    ---------------------------------------------------------------------
    top.mat <- CCLE.mito[as.numeric(CCLE.hicor.genes),]
    pc1.vec <- PC1VecFun(top.gem = top.mat,
                         seed.sort = CCLE.samp.sort, n = 10)
    # --- Thresholdbic [] ---
    # Key functions: ThresholdBic
    ---------------------------------------------------------------------
    CCLE.bic <- ThresholdBic(cor.vec = CCLE.cor.vec,
                             sort.order = CCLE.samp.sort,
                             pc1 = pc1.vec, samp.sig = 0.05)
    # --- P C1 Align [] ---
    # Key functions: PC1Align
    ---------------------------------------------------------------------
    pc1.vec <- PC1Align(gem = CCLE_small, pc1 = pc1.vec,
                        sort.order = CCLE.samp.sort,
                        cor.vec = CCLE.cor.vec, bic = CCLE.bic)
    # --- Colmeans [] ---
    # Key functions: colMeans
    ---------------------------------------------------------------------
    av.genes.group1 <- colMeans(CCLE.mito[CCLE.groups[[1]],
                                          CCLE.samp.sort])
    av.genes.group2 <- colMeans(CCLE.mito[CCLE.groups[[2]],
                                          CCLE.samp.sort])
    # --- Colnames [] ---
    # Key functions: ForkClassifier, frame, ggplot, aes, geom_point
    ---------------------------------------------------------------------
    CCLE.names <- colnames(CCLE_small)[CCLE.samp.sort]
    fork.status <- ForkClassifier(pc1.vec, samp.num = length(CCLE.bic[[2]]))
    CCLE.df <- data.frame(CCLE.name = CCLE.names,
                          PC1 = pc1.vec,
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(CCLE_samples)
    # --- Table [] ---
    # Key functions: test
    ---------------------------------------------------------------------
    library(MASS)
    # create contingency tables
    ctable.site <- table(CCLE.df.samples$Fork,
                         CCLE.df.samples$Site.Primary)
    # --- Silhouetteclustgroups [] ---
    # Key functions: SilhouetteClustGroups
    ---------------------------------------------------------------------
    multi.clust.groups <- SilhouetteClustGroups(multi.run.cor.vec.mat,
                                                max.clusters = 20,
                                                plots = TRUE,rand.vec = FALSE)
    # --- Function [] ---
    # Key functions: GOEnrichmentAnalysis
    ---------------------------------------------------------------------
    GOfun <- function(x) GOEnrichmentAnalysis(gene.names = gene.names,
                                              gene.values = x,
                                              sig.rate = 0.05)
    # --- List [] ---
    # Key functions: MultiSampleSortPrep
    ---------------------------------------------------------------------
    CCLE.samp.multi.sort <- list()
    multi.prep <- MultiSampleSortPrep(gem = CCLE_small,
                                      av.corvec = average.corvec,
                                      top.genes.num = 750,
    # --- List [] ---
    # Key functions: PC1VecFun
    ---------------------------------------------------------------------
    pc1.vec.multi <- list()
    pc1.vec.multi[[1]] <- PC1VecFun(top.gem =  multi.prep[[1]][[1]],
                         seed.sort = CCLE.samp.multi.sort[[1]], n = 10)
    pc1.vec.multi[[2]] <- PC1VecFun(top.gem =  multi.prep[[1]][[2]],
    # --- List [] ---
    # Key functions: ThresholdBic, PC1Align
    ---------------------------------------------------------------------
    CCLE.bic.multi <- list()
    CCLE.bic.multi[[1]] <- ThresholdBic(cor.vec = average.corvec[[1]],
                             sort.order = CCLE.samp.multi.sort[[1]],
                             pc1 = pc1.vec.multi[[1]], samp.sig = 0.05)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mcbiclust_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mcbiclust_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mcbiclust_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MCBICLUST:", paste0("    mcbiclust: ", packageVersion("MCbiclust"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mcbiclust_results.csv
    touch ${prefix}_mcbiclust_output.rds
    echo "BIOC_MCBICLUST:" > versions.yml
    echo "    mcbiclust: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MCBICLUST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MCBICLUST(ch_input)

    emit:
    results  = BIOC_MCBICLUST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MCBICLUST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MCBICLUST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MCBICLUST.out.versions  // channel: path(versions.yml)
}
