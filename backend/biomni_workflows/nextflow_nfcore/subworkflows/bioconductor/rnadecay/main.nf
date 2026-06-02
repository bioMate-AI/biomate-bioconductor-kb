#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RNAdecay
// RNA degradation is monitored through measurement of RNA abundance after inhibiting RNA synthesis. Th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RNAdecay/inst/doc/RNAdecay_workflow.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("RNAdecay")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNADECAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnadecay"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnadecay:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnadecay:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rnadecay_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnadecay_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnadecay_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RNAdecay)
    library(jsonlite)

    # --- Frame [] ---
    # Key functions: frame, colMeans
    ---------------------------------------------------------------------
    # you can see that in this fabricated data the RNAs have a half-life of ~30 min
    RPM_geneX <- data.frame(T0 = c(150, 135, 148), T30 = c(72, 76, 69), T60 = c(35, 35, 30),
                         row.names = paste0("rep", 1:3))
    RPM_geneX
    # --- Cols [] ---
    # Key functions: cols, nested
    ---------------------------------------------------------------------
    cols(patterns = c("WT", "00"), df = RPMs) #gives the column indices that contain both tags in the column names
    colnames(RPMs)[cols(patterns = c("WT", "00"), RPMs, "WT", "00")]
    # NOTE: this is based on grep pattern matching so tags MUST be unique and non-nested (i.e. one entire label should not be part of another).
    # --- Frame [] ---
    # Key functions: frame, rowMeans, cols
    ---------------------------------------------------------------------
    mean_RPM <- data.frame("geneID" = rownames(RPMs))
    SE_RPM <- data.frame("geneID" = rownames(RPMs))
    for(g in treatment){
      for(t in tdecay){
    # --- Rep [] ---
    # Key functions: rep
    ---------------------------------------------------------------------
    filt1 <- rep(TRUE, 118) # we will not filter in this example, so the filter value for each gene is set to TRUE.
    # --- Frame [] ---
    # Key functions: frame, rowMeans, cols
    ---------------------------------------------------------------------
    mT0norm <- data.frame(row.names = rownames(RPMs)[filt1])
    for(g in treatment){
      mean_T0reps <- rowMeans(RPMs[filt1, cols(df=RPMs, patterns=c(g, "00"))])
      for(r in reps){
    # --- Colmeans [] ---
    # Key functions: colMeans
    ---------------------------------------------------------------------
    stabletable <- mean_mT0norm[stablegenes, ]
    normFactors <- colMeans(stabletable)
    write.table(x <- normFactors, paste0(wrdir, "/Normalziation Decay Factors.txt"), sep = "\t")
    normFactors_mean <- matrix(normFactors, nrow = length(tdecay))
    # --- Frame [] ---
    # Key functions: frame
    ---------------------------------------------------------------------
    mT0norm_2 <- data.frame(mT0norm/normFactorsM,
                         row.names = rownames(mT0norm))
    write.table(mT0norm_2, paste0(wrdir, "/T0 normalized and decay factor corrected.txt"), sep = "\t")
    # --- Melt [] ---
    # Key functions: melt, colsplit
    ---------------------------------------------------------------------
    mT0norm_2.1 <- reshape2::melt(as.matrix(mT0norm_2), varnames = c("geneID", "variable"))
    mT0norm_2.1 <- cbind(mT0norm_2.1, reshape2::colsplit(mT0norm_2.1$variable, "_", names = c("treatment", "t.decay", "rep")))
    mT0norm_2.1 <- mT0norm_2.1[, colnames(mT0norm_2.1) !=  "variable"]
    mT0norm_2.1 <- mT0norm_2.1[, c(1, 3, 4, 5, 2)]
    # --- Levels [] ---
    # Key functions: levels, necessary, factor
    ---------------------------------------------------------------------
    levels(decay_data$treatment) # This can not be longer than 4 elements for modeling.
    # reorder factor levels if necessary (skipped here):
    # decay_data$treatment <- factor(decay_data$treatment, levels = levels(decay_data$treatment)[c(4, 1, 2, 3)]) # numbers here refer to the current order position in the factor levels() - the order of the numbers designates the new position
    levels(decay_data$treatment)[4] <- "vcs.sov"
    # --- Group Map [] ---
    # Key functions: group_map
    ---------------------------------------------------------------------
    group_map(decaydata = decay_data, path = paste0(wrdir, "/Model grouping colormap.pdf"), nEquivGrp = nEquivGrp, groups = groups, mods = mods)
    # --- Mod Optimization [] ---
    # Key functions: mod_optimization
    ---------------------------------------------------------------------
    mod_optimization("AT2G18150", decay_data, group = groups, mod = mods, a_bounds, b_bounds, c("mod1", "mod2", "mod16", "mod239", "mod240"), file_only = FALSE, path = wrdir)
    mod_optimization("AT4G09680", decay_data, group = groups, mod = mods, a_bounds, b_bounds, c("mod1", "mod2", "mod16", "mod239", "mod240"), file_only = FALSE, path = wrdir)
    # --- Mclapply [] ---
    # Key functions: mclapply, getOption, here
    ---------------------------------------------------------------------
    ####### To run all genes in parallel use:
    # parallel::mclapply(ids, FUN = mod_optimization,
    #                    data = decay_data, group = groups, mod = mods,
    #                    alpha_bounds = a_bounds, beta_bounds = b_bounds,
    # --- Sample [] ---
    # Key functions: sample, time, mod_optimization
    ---------------------------------------------------------------------
    test_ids <- sample(ids, 1) # NOTE: that everytime this line is run it generates a different random sampling, therefore the gene modeled below will be different each time this code is run. To test the exact gene shown in the vignette make a new character vector of the gene id reported below and pass it to the gene argument of mod_optimization using lapply instead of passing 'test_ids' as we do here.
    test_ids
    a <- proc.time()[3]
    models <- lapply(X = test_ids, # alternatively use `ids` here to complete the entire sample data set, but be prepared to wait ~ 10 h. These gene IDs will get passed one at time to the "gene" argument of mod_optimization() and return a list of the results data frame.
    # --- Pdf [] ---
    # Key functions: ggplot, geom_histogram, aes, coord_cartesian
    ---------------------------------------------------------------------
    library(ggplot2)
    pdf(paste0(wrdir,"/distributions of stats.pdf"))
    p <- ggplot(results)
    print(p+geom_histogram(aes(x = sigma2), bins = 300)+
    # --- Delim [] ---
    # Key functions: delim
    ---------------------------------------------------------------------
    results <- read.delim(paste0(wrdir,"/best model results.txt"))
    results$alpha_grp <- mods[as.character(results$mod), "a"]
    results$beta_grp <- mods[as.character(results$mod), "b"]
    results$mod <- as.numeric(gsub("mod", "", as.character(results$mod)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnadecay_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnadecay_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnadecay_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNADECAY:", paste0("    rnadecay: ", packageVersion("RNAdecay"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnadecay_results.csv
    touch ${prefix}_rnadecay_output.rds
    echo "BIOC_RNADECAY:" > versions.yml
    echo "    rnadecay: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNADECAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RNADECAY(ch_input)

    emit:
    results  = BIOC_RNADECAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNADECAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNADECAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNADECAY.out.versions  // channel: path(versions.yml)
}
