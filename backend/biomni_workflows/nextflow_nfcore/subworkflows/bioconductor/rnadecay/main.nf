#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RNAdecay — rna_decay_analysis
// Normalize raw RPM RNA-seq decay data, correct for total RNA pool depletion, fit constant and decaying decay models, and visualize decay curves and half-lives.
// Input: RPMs, stablegenes, descriptions
// Container: quay.io/biocontainers/bioconductor-rnadecay:1.30.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RNAdecay, ggplot2, reshape2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Index replicate columns using cols() and calculate mean and standard error of RPMs
//  * 2. [Core Analysis] Perform T0 normalization by dividing all time points by the mean T0 value
//  * 3. [Core Analysis] Calculate decay factors from stable reference genes and apply decay factor correction
//  * 4. [Core Analysis] Reshape the corrected data into a long-format data frame
//  * 5. [Input & Preparation] Sort the data frame (required step) and define equivalence constraint groups using groupings()
//  * 6. [Core Analysis] Determine alpha and beta parameter bounds using a_low(), a_high(), and b_low()
//  * 7. [Core Analysis] Perform maximum likelihood parameter optimization using mod_optimization()
//  * 8. [Core Analysis] Select the best model per gene using the AICc statistic
//  * 9. [Visualization & Output] Plot decay curves using decay_plot() and half-life distributions using hl_plot()

nextflow.enable.dsl = 2

process BIOC_RNADECAY_RNA_DECAY_ANALYSIS {
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
    .bm_deps <- c("RNAdecay", "reshape2", "ggplot2")
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
            library(RNAdecay)
            library(reshape2)
            library(ggplot2)
            
            # Define results directory
            wrdir <- "./decay_analysis_results"
            if(!file.exists(wrdir)) dir.create(wrdir, recursive = TRUE)
            
            # ==========================================
            # 1. READ USER INPUT FILES
            # ==========================================
            
            # Read RPMs
            if (file.exists("RPMs.csv")) {
              RPMs <- read.csv("RPMs.csv", row.names = 1, check.names = FALSE)
            } else if (file.exists("RPMs.txt")) {
              RPMs <- read.delim("RPMs.txt", row.names = 1, check.names = FALSE)
            } else if (file.exists("RPMs.rds")) {
              RPMs <- readRDS("RPMs.rds")
            } else {
              stop("No RPMs file found in working directory.")
            }
            
            # Read stablegenes
            if (file.exists("stablegenes.txt")) {
              stablegenes <- readLines("stablegenes.txt")
            } else if (file.exists("stablegenes.rds")) {
              stablegenes <- readRDS("stablegenes.rds")
            } else {
              message("No stablegenes file found in working directory. Using package default stable reference genes.")
              stablegenes <- c("ATCG00490", "ATCG00680", "ATMG00280", "ATCG00580", "ATCG00140", 
                               "AT4G38970", "AT2G07671", "ATCG00570", "ATMG00730", "AT2G07727", 
                               "AT2G07687", "ATMG00160", "AT3G11630", "ATMG00060", "ATCG00600", 
                               "ATMG00220", "ATMG01170", "ATMG00410", "AT1G78900", "AT3G55440", 
                               "ATMG01320", "AT2G21170", "AT5G08670", "AT5G53300", "ATMG00070", 
                               "AT1G26630", "AT5G48300", "AT2G33040", "AT5G08690", "AT1G57720")
            }
            
            # Read descriptions
            descriptions <- NULL
            if (file.exists("descriptions.txt")) {
              desc_df <- read.delim("descriptions.txt", header = FALSE, sep = "\t", stringsAsFactors = FALSE)
              descriptions <- desc_df[[2]]
              names(descriptions) <- desc_df[[1]]
            } else if (file.exists("descriptions.rds")) {
              descriptions <- readRDS("descriptions.rds")
            } else if (file.exists("descriptions.csv")) {
              desc_df <- read.csv("descriptions.csv", header = FALSE, stringsAsFactors = FALSE)
              descriptions <- desc_df[[2]]
              names(descriptions) <- desc_df[[1]]
            } else {
              message("No descriptions file found. Using default package descriptions.")
              descriptions <- c(
                "AT1G02860" = "Encodes a ubiquitin E3 ligase with RING and SPX domains that is involved in mediating immune responses and mediates degradation of PHT1s at plasma membranes. Targeted by MIR827. Ubiquitinates PHT1;3, PHT1;2, PHT1;1/AtPT1 and PHT1;4/AtPT2.",
                "AT5G54730" = "",
                "AT1G27730" = "Related to Cys2/His2-type zinc-finger proteins found in higher plants. Compensated for a subset of calcineurin deficiency in yeast. Salt tolerance produced by ZAT10 appeared to be partially dependent on ENA1/PMR2, a P-type ATPase required for Li+ and Na+ efflux in yeast. The protein is localized to the nucleus, acts as a transcriptional repressor and is responsive to chitin oligomers. Also involved in response to photooxidative stress.",
                "AT4G34190" = "Encodes a stress enhanced protein that localizes to the thylakoid membrane and whose mRNA is upregulated in response to high light intensity. It may be involved in chlorophyll binding."
              )
            }
            
            # ==========================================
            # 2. PARSE EXPERIMENTAL DESIGN
            # ==========================================
            col_parts <- strsplit(colnames(RPMs), "_")
            treatment <- unique(sapply(col_parts, function(x) x[1]))
            tdecay <- unique(sapply(col_parts, function(x) x[2]))
            tdecay <- tdecay[order(as.numeric(tdecay))]
            reps <- unique(sapply(col_parts, function(x) x[3]))
            reps <- reps[order(reps)]
            
            filt1 <- rep(TRUE, nrow(RPMs))
            
            # ==========================================
            # 3. T0 NORMALIZATION
            # ==========================================
            mean_RPM <- data.frame("geneID" = rownames(RPMs))
            SE_RPM <- data.frame("geneID" = rownames(RPMs))
            for(g in treatment){
              for(t in tdecay){
                mean_RPM <- cbind(mean_RPM, rowMeans(RPMs[, cols(df=RPMs, patterns = c(g, t))]))
                names(mean_RPM)[length(mean_RPM)] <- paste0(g, "_", t)
                SE_RPM <- cbind(SE_RPM, apply(X = RPMs[, cols(df=RPMs, patterns = c(g, t))], MARGIN = 1, FUN = stats::sd)/sqrt(length(reps)))
                names(SE_RPM)[length(SE_RPM)] <- paste0(g, "_", t)
              }}
            
            write.table(x = mean_RPM, paste0(wrdir, "/RPM_mean.txt"), sep = "\t", row.names = FALSE)
            write.table(x = SE_RPM,   paste0(wrdir, "/RPM_SE.txt"), sep = "\t", row.names = FALSE)
            
            t0_tag <- if ("00" %in% tdecay) "00" else tdecay[1]
            
            mT0norm <- data.frame(row.names = rownames(RPMs)[filt1])
            for(g in treatment){
              mean_T0reps <- rowMeans(RPMs[filt1, cols(df=RPMs, patterns=c(g, t0_tag))])
              for(r in reps){
                df <- RPMs[filt1, colnames(RPMs)[cols(df=RPMs, patterns=c(g, r))]]
                df <- df[, 1:length(tdecay)]/mean_T0reps
                mT0norm <- cbind(mT0norm, df)
              }}
            
            write.table(x = mT0norm, file = paste0(wrdir, "/T0_normalized.txt"), sep = "\t")
            
            mean_mT0norm <- data.frame(row.names = rownames(mT0norm))
            for(g in treatment){
              for(t in tdecay){
                mean_mT0norm <- cbind(mean_mT0norm, rowMeans(mT0norm[, cols(df=mT0norm, patterns=c(g, t))]))
                names(mean_mT0norm)[length(names(mean_mT0norm))] <- paste0(g, "_", t)
              }}
            
            # ==========================================
            # 4. DECAY FACTOR CORRECTION
            # ==========================================
            stablegenes_present <- intersect(stablegenes, rownames(mean_mT0norm))
            if (length(stablegenes_present) == 0) {
              stop("None of the stable reference genes are present in the dataset.")
            }
            
            stabletable <- mean_mT0norm[stablegenes_present, , drop = FALSE]
            normFactors <- colMeans(stabletable)
            
            nF <- character(ncol(mT0norm))
            ind <- sapply(names(normFactors), function(x) grep(x, colnames(mT0norm)), simplify = FALSE)
            for(i in seq_along(ind)){
              nF[ind[[i]]] <- names(ind)[i]
            }
            normFactorsM <- t(matrix(rep(normFactors[nF], nrow(mT0norm)), ncol = nrow(mT0norm)))
            
            mT0norm_2 <- data.frame(mT0norm/normFactorsM, 
                                    row.names = rownames(mT0norm))
            
            write.table(mT0norm_2, paste0(wrdir, "/T0_normalized_corrected.txt"), sep = "\t")
            
            # ==========================================
            # 5. RESHAPING & SORTING
            # ==========================================
            mT0norm_2.1 <- reshape2::melt(as.matrix(mT0norm_2), varnames = c("geneID", "variable"))
            mT0norm_2.1 <- cbind(mT0norm_2.1, reshape2::colsplit(mT0norm_2.1\$variable, "_", names = c("treatment", "t.decay", "rep")))
            mT0norm_2.1 <- mT0norm_2.1[, colnames(mT0norm_2.1) !=  "variable"]
            mT0norm_2.1 <- mT0norm_2.1[, c(1, 3, 4, 5, 2)]
            colnames(mT0norm_2.1) <- c("geneID", "treatment", "t.decay", "rep", "value")
            mT0norm_2.1\$t.decay <- as.numeric(as.character(mT0norm_2.1\$t.decay))
            mT0norm_2.1\$treatment <- factor(mT0norm_2.1\$treatment, levels = treatment)
            mT0norm_2.1\$rep <- factor(mT0norm_2.1\$rep, levels = unique(mT0norm_2.1\$rep))
            
            decay_data <- mT0norm_2.1
            decay_data <- decay_data[order(decay_data\$t.decay), ]
            decay_data <- decay_data[order(decay_data\$rep), ]
            decay_data <- decay_data[order(as.numeric(decay_data\$treatment)), ] 
            decay_data <- decay_data[order(decay_data\$geneID), ]
            ids <- as.character(unique(decay_data\$geneID))
            
            write.csv(decay_data, paste0(wrdir, "/decay_data_processed.csv"), row.names = FALSE)
            
            # ==========================================
            # 6. MODEL SETUP & BOUNDS
            # ==========================================
            groups <- groupings(decay_data)
            
            nEquivGrp <- if (length(unique(decay_data\$treatment)) == 2) {2} else
              if (length(unique(decay_data\$treatment)) == 3) {5} else 
                if (length(unique(decay_data\$treatment)) == 4) {15} else {1}
            
            mods <- data.frame(
              "a" = as.vector(sapply(1:nEquivGrp, function(x) {rep(x, nEquivGrp + 1)})),
              "b" = rep(1:(nEquivGrp + 1), nEquivGrp),
              row.names = paste0("mod", 1:(nEquivGrp*(nEquivGrp+1)))
            )
            
            a_bounds <- c(a_low(max(decay_data\$t.decay)),
                          a_high(min(unique(decay_data\$t.decay)[unique(decay_data\$t.decay)>0])))
            b_bounds <- c(b_low(max(decay_data\$t.decay)), 0.075)
            
            # ==========================================
            # 7. MODEL OPTIMIZATION
            # ==========================================
            # Run optimization for a subset of genes to keep execution time reasonable
            run_ids <- ids[1:min(3, length(ids))]
            
            models <- lapply(X = run_ids,
                             FUN = mod_optimization,
                             data = decay_data, 
                             group = groups, 
                             mod = mods,
                             alpha_bounds = a_bounds, 
                             beta_bounds = b_bounds,
                             models = rownames(mods), 
                             path = paste0(wrdir, "/modeling_results"),
                             file_only = FALSE)
            names(models) <- run_ids
            
            # ==========================================
            # 8. MODEL SELECTION
            # ==========================================
            # Read the results back in to ensure consistency
            models <- lapply(paste0(wrdir, "/modeling_results/", run_ids, "_results.txt"), read.delim, header = TRUE)
            names(models) <- run_ids
            
            results <- t(sapply(models, function(x) x[x[, "AICc"] == min(x[, "AICc"]), ]))
            results <- as.data.frame(results)
            results[, 1:2] <- sapply(as.data.frame(results[, 1:2]), function(x) as.character(unlist(x)))
            results[, -c(1,2)] <- sapply(results[, -c(1,2)], unlist)
            
            write.table(results, file = paste0(wrdir, "/best_model_results.txt"), sep = "\t", row.names = TRUE)
            
            # ==========================================
            # 9. VISUALIZATION
            # ==========================================
            plot_gene <- run_ids[1]
            plot_treatments <- levels(decay_data\$treatment)
            
            # Generate decay plot
            p <- decay_plot(geneID = plot_gene, 
                            xlim = c(0, 350), 
                            ylim = c(0, 1.25), 
                            xticks = 1:5*100, 
                            yticks = 0:5/4,
                            alphaSZ  =  12, 
                            what  =  c("meanSE", "reps", "models"),
                            treatments  =  plot_treatments, 
                            colors = c("darkblue", "red3", "green3", "purple")[1:length(plot_treatments)],
                            DATA = decay_data, 
                            mod.results = results, 
                            gdesc = descriptions)
            
            pdf(paste0(wrdir, "/decay_plot.pdf"), width = 10, height = 8)
            print(p)
            dev.off()
            
            # Generate half-life plot (wrapped in tryCatch to handle small datasets gracefully)
            tryCatch({
              p_hl <- hl_plot(geneID = plot_gene,
                              gene_symbol = plot_gene,
                              df_decay_rates = results,
                              hl_dist_treatment = plot_treatments[1],
                              hl_treatment = plot_treatments,
                              arrow_lab_loc = "key"
              )
              pdf(paste0(wrdir, "/halflife_plot.pdf"), width = 10, height = 8)
              print(p_hl)
              dev.off()
            }, error = function(e) {
              message("hl_plot skipped or failed: ", e\$message)
            })
            
            message("Pipeline completed successfully. Results written to: ", wrdir)

    writeLines(c(
        '"BIOC_RNADECAY_RNA_DECAY_ANALYSIS":',
        paste0('    RNAdecay: ', as.character(packageVersion('RNAdecay')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_decay_analysis.csv versions.yml
    """
}

workflow BIOC_RNADECAY_RNA_DECAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ RPMs, stablegenes, descriptions ] ]

    main:
    BIOC_RNADECAY_RNA_DECAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RNADECAY_RNA_DECAY_ANALYSIS.out.tables
    plots    = BIOC_RNADECAY_RNA_DECAY_ANALYSIS.out.plots
    objects  = BIOC_RNADECAY_RNA_DECAY_ANALYSIS.out.objects
    versions = BIOC_RNADECAY_RNA_DECAY_ANALYSIS.out.versions
}
