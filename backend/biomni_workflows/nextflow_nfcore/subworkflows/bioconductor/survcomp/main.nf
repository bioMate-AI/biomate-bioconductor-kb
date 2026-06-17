#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: survcomp — survival_risk_prediction_evaluation
// Compute concordance index, D-index, and hazard ratio for risk predictors across multiple datasets, combine the estimates, and visualize them using forest plots.
// Input: ExpressionSet objects or expression matrices
// Container: quay.io/biocontainers/bioconductor-survcomp:1.60.0--r45ha27e39d_0
// R packages: Biobase, rmeta, survcomp, survival, xtable
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, rmeta, survcomp, survival
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute concordance index using concordance.index
//  * 2. [Core Analysis] Compute D-index using D.index
//  * 3. [Core Analysis] Rescale expression data using a custom quantile-based function
//  * 4. [Core Analysis] Compute hazard ratio using hazard.ratio
//  * 5. [Core Analysis] Combine estimates across datasets using combine.est
//  * 6. [Visualization & Output] Plot combined estimates using forestplot.surv

nextflow.enable.dsl = 2

process BIOC_SURVCOMP_SURVIVAL_RISK_PREDICTION_EVALUATION {
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
    .bm_deps <- c("Biobase", "rmeta", "survcomp", "survival", "xtable")
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
        library(survcomp)
        library(Biobase)
        library(rmeta)
        library(grid)
        library(survival)
        
        # Read ExpressionSet objects from the working directory or command line arguments
        args <- commandArgs(trailingOnly = TRUE)
        if (length(args) > 0) {
          files <- args
        } else {
          files <- list.files(pattern = "\\\\.rds\$")
        }
        
        if (length(files) < 2) {
          stop("At least 2 .rds files must be provided to combine estimates.")
        }
        
        datasets <- list()
        dataset_names <- c()
        for (f in files) {
          obj <- readRDS(f)
          name <- tools::file_path_sans_ext(basename(f))
          datasets[[name]] <- obj
          dataset_names <- c(dataset_names, name)
        }
        
        # Helper functions to find time and event columns dynamically
        get_time_col <- function(pd) {
          common_names <- c("time", "surv.time", "t.dmfs", "t.rfs", "t.os", "os.time", "survival_time", "days_to_death")
          for (nm in common_names) {
            if (nm %in% colnames(pd)) return(nm)
          }
          for (nm in colnames(pd)) {
            if (is.numeric(pd[[nm]])) return(nm)
          }
          return(colnames(pd)[1])
        }
        
        get_event_col <- function(pd, t_col) {
          common_names <- c("event", "surv.event", "e.dmfs", "e.rfs", "e.os", "os.event", "status", "vital_status")
          for (nm in common_names) {
            if (nm %in% colnames(pd)) return(nm)
          }
          for (nm in colnames(pd)) {
            if ((is.numeric(pd[[nm]]) || is.logical(pd[[nm]])) && nm != t_col) return(nm)
          }
          return(colnames(pd)[2])
        }
        
        # 3. Rescale expression data using a custom quantile-based function
        rescale <- function(x, na.rm=FALSE, q=0.05) { 
          ma <- quantile(x, probs=1-(q/2), na.rm=na.rm); 
          mi <- quantile(x, probs=q/2, na.rm=na.rm); 
          x <- (x - mi) / (ma - mi); 
          return((x - 0.5) * 2); 
        }
        
        cindex_list <- list()
        dindex_list <- list()
        hratio_list <- list()
        gsList <- NULL
        
        for (name in dataset_names) {
          obj <- datasets[[name]]
          
          if (inherits(obj, "ExpressionSet")) {
            ex <- exprs(obj)
            pd <- pData(obj)
            fd <- fData(obj)
            
            t_col <- get_time_col(pd)
            e_col <- get_event_col(pd, t_col)
            
            y <- as.numeric(as.character(pd[, t_col]))
            z <- as.numeric(as.character(pd[, e_col]))
            
            if ("Gene.symbol" %in% colnames(fd)) {
              feat_names <- tolower(fd[, "Gene.symbol"])
            } else {
              feat_names <- rownames(ex)
            }
          } else if (is.list(obj)) {
            ex <- obj\$exprs
            if (is.null(ex)) ex <- obj[[1]]
            
            y <- obj\$time
            if (is.null(y)) y <- obj[[2]]
            y <- as.numeric(as.character(y))
            
            z <- obj\$event
            if (is.null(z)) z <- obj[[3]]
            z <- as.numeric(as.character(z))
            
            feat_names <- rownames(ex)
            if (is.null(feat_names)) feat_names <- paste0("Gene", 1:nrow(ex))
          } else {
            stop("Unsupported data format. Please provide ExpressionSet objects or lists with exprs, time, and event.")
          }
          
          if (is.null(gsList)) {
            gsList <- feat_names
          } else {
            gsList <- intersect(gsList, feat_names)
          }
          
          # 1. Compute concordance index using concordance.index
          cindex_res <- t(apply(X=ex, MARGIN=1, function(x, y, z) { 
            tt <- concordance.index(x=x, surv.time=y, surv.event=z, method="noether", na.rm=TRUE); 
            return(c("cindex"=tt\$c.index, "cindex.se"=tt\$se, "lower"=tt\$lower, "upper"=tt\$upper)); 
          }, y=y, z=z))
          rownames(cindex_res) <- feat_names
          cindex_list[[name]] <- cindex_res
          
          # 2. Compute D-index using D.index
          dindex_res <- t(apply(X=ex, MARGIN=1, function(x, y, z) { 
            tt <- D.index(x=x, surv.time=y, surv.event=z, na.rm=TRUE); 
            return(c("dindex"=tt\$d.index, "dindex.se"=tt\$se, "lower"=tt\$lower, "upper"=tt\$upper)); 
          }, y=y, z=z))
          rownames(dindex_res) <- feat_names
          dindex_list[[name]] <- dindex_res
          
          # 4. Compute hazard ratio using hazard.ratio
          hratio_res <- t(apply(X=rescale(ex, q=0.05, na.rm=TRUE), MARGIN=1, function(x, y, z) { 
            tt <- hazard.ratio(x=x, surv.time=y, surv.event=z, na.rm=TRUE); 
            return(c("hratio"=tt\$hazard.ratio, "hratio.se"=tt\$se, "lower"=tt\$lower, "upper"=tt\$upper)); 
          }, y=y, z=z))
          rownames(hratio_res) <- feat_names
          hratio_list[[name]] <- hratio_res
        }
        
        if (length(gsList) == 0) {
          stop("No common genes found across datasets.")
        }
        
        # Define annotation and helper variables
        datasetList <- c(toupper(dataset_names), "", "Overall")
        myspace <- " "
        mybigspace <- "    "
        tc <- 10 * 365
        
        # 5. Combine estimates across datasets using combine.est
        # Combine C-indices
        tt_cindex <- as.data.frame(NULL)
        for(g in gsList){
          x_mat <- do.call(cbind, lapply(dataset_names, function(name) cindex_list[[name]][g, "cindex"]))
          se_mat <- do.call(cbind, lapply(dataset_names, function(name) cindex_list[[name]][g, "cindex.se"]))
          
          tt_cindex <- rbind(tt_cindex, combine.est(x=x_mat, x.se=se_mat, na.rm=TRUE))
        }
        tt_cindex\$lower <- tt_cindex\$estimate + qnorm(0.025, lower.tail=TRUE) * tt_cindex\$se
        tt_cindex\$upper <- tt_cindex\$estimate + qnorm(0.025, lower.tail=FALSE) * tt_cindex\$se
        rownames(tt_cindex) <- gsList
        colnames(tt_cindex) <- c("cindex","cindex.se","p.value","stat","lower","upper")
        ccindex <- tt_cindex
        
        # Combine D-indices
        tt_dindex <- as.data.frame(NULL)
        for(g in gsList){
          x_mat <- do.call(cbind, lapply(dataset_names, function(name) dindex_list[[name]][g, "dindex"]))
          se_mat <- do.call(cbind, lapply(dataset_names, function(name) dindex_list[[name]][g, "dindex.se"]))
          
          tt_dindex <- rbind(tt_dindex, combine.est(x=x_mat, x.se=se_mat, na.rm=TRUE))
        }
        tt_dindex\$lower <- tt_dindex\$estimate + qnorm(0.025, lower.tail=TRUE) * tt_dindex\$se
        tt_dindex\$upper <- tt_dindex\$estimate + qnorm(0.025, lower.tail=FALSE) * tt_dindex\$se
        rownames(tt_dindex) <- gsList
        colnames(tt_dindex) <- c("dindex","dindex.se","p.value","stat","lower","upper")
        cdindex <- tt_dindex
        
        # Combine Hazard Ratios
        tt_hratio <- as.data.frame(NULL)
        for(g in gsList){
          x_mat <- do.call(cbind, lapply(dataset_names, function(name) hratio_list[[name]][g, "hratio"]))
          se_mat <- do.call(cbind, lapply(dataset_names, function(name) hratio_list[[name]][g, "hratio.se"]))
          
          tt_hratio <- rbind(tt_hratio, combine.est(x=x_mat, x.se=se_mat, na.rm=TRUE))
        }
        tt_hratio\$lower <- tt_hratio\$estimate + qnorm(0.025, lower.tail=TRUE) * tt_hratio\$se
        tt_hratio\$upper <- tt_hratio\$estimate + qnorm(0.025, lower.tail=FALSE) * tt_hratio\$se
        rownames(tt_hratio) <- gsList
        colnames(tt_hratio) <- c("hratio","hratio.se","p.value","stat","lower","upper")
        chratio <- tt_hratio
        
        # Save combined estimates to CSV and RDS
        write.csv(ccindex, "combined_cindex.csv", row.names=TRUE)
        write.csv(cdindex, "combined_dindex.csv", row.names=TRUE)
        write.csv(chratio, "combined_hratio.csv", row.names=TRUE)
        
        saveRDS(ccindex, "combined_cindex.rds")
        saveRDS(cdindex, "combined_dindex.rds")
        saveRDS(chratio, "combined_hratio.rds")
        
        # 6. Plot combined estimates using forestplot.surv
        # Forest plot for Concordance Index
        pdf("forestplot_cindex.pdf", width=7, height=5)
        labeltext <- cbind(c("Gene Symbol",gsList),c(rep(myspace,length(gsList)+1)))
        bs <- rep(0.5, nrow(labeltext))
        r.mean <- c(NA,ccindex\$cindex)
        r.lower <- c(NA,ccindex\$lower)
        r.upper <- c(NA,ccindex\$upper)
        
        valid_vals <- c(r.lower, r.upper, 0.5)
        valid_vals <- valid_vals[is.finite(valid_vals)]
        my_ticks <- pretty(valid_vals, n=5)
        my_clip <- c(min(my_ticks), max(my_ticks))
        
        forestplot.surv(labeltext=labeltext, mean=r.mean, lower=r.lower, upper=r.upper, zero=0.5,
                        align=c("l"), graphwidth=grid::unit(2, "inches"), x.ticks=my_ticks, xlab=paste( "Concordance Index", myspace, sep=""),
                        col=meta.colors(box="royalblue", line="darkblue", zero="darkred"), box.size=bs, clip=my_clip)
        dev.off()
        
        # Forest plot for D Index
        pdf("forestplot_dindex.pdf", width=7, height=5)
        labeltext <- cbind(c("Gene Symbol",gsList),c(rep(myspace,length(gsList)+1)))
        bs <- rep(0.5, nrow(labeltext))
        r.mean <- c(NA,log2(cdindex\$dindex))
        r.lower <- c(NA,log2(cdindex\$lower))
        r.upper <- c(NA,log2(cdindex\$upper))
        
        valid_vals <- c(r.lower, r.upper, 0)
        valid_vals <- valid_vals[is.finite(valid_vals)]
        my_ticks <- pretty(valid_vals, n=5)
        my_clip <- c(min(my_ticks), max(my_ticks))
        
        forestplot.surv(labeltext=labeltext, mean=r.mean, lower=r.lower, upper=r.upper, zero=0,
                        align=c("l"), graphwidth=grid::unit(2, "inches"), x.ticks=my_ticks, xlab=paste("log2 D Index", myspace, sep=""),
                        col=meta.colors(box="royalblue", line="darkblue", zero="darkred"), box.size=bs, clip=my_clip)
        dev.off()
        
        # Forest plot for Hazard Ratio
        pdf("forestplot_hratio.pdf", width=7, height=5)
        labeltext <- cbind(c("Gene Symbol",gsList),c(rep(mybigspace,length(gsList)+1)))
        bs <- rep(0.5, nrow(labeltext))
        r.mean <- c(NA,log2(chratio\$hratio))
        r.lower <- c(NA,log2(chratio\$lower))
        r.upper <- c(NA,log2(chratio\$upper))
        
        valid_vals <- c(r.lower, r.upper, 0)
        valid_vals <- valid_vals[is.finite(valid_vals)]
        my_ticks <- pretty(valid_vals, n=5)
        my_clip <- c(min(my_ticks), max(my_ticks))
        
        forestplot.surv(labeltext=labeltext, mean=r.mean, lower=r.lower, upper=r.upper, zero=0,
                        align=c("l"), graphwidth=grid::unit(2, "inches"), x.ticks=my_ticks, xlab=paste( "log2 Hazard Ratio", myspace, sep=""),
                        col=meta.colors(box="royalblue", line="darkblue", zero="darkred"), box.size=bs, clip=my_clip)
        dev.off()

    writeLines(c(
        '"BIOC_SURVCOMP_SURVIVAL_RISK_PREDICTION_EVALUATION":',
        paste0('    survcomp: ', as.character(packageVersion('survcomp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_survival_risk_prediction_evaluation.csv versions.yml
    """
}

workflow BIOC_SURVCOMP_SURVIVAL_RISK_PREDICTION_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet objects or expression matrices ] ]

    main:
    BIOC_SURVCOMP_SURVIVAL_RISK_PREDICTION_EVALUATION(ch_input)

    emit:
    tables   = BIOC_SURVCOMP_SURVIVAL_RISK_PREDICTION_EVALUATION.out.tables
    plots    = BIOC_SURVCOMP_SURVIVAL_RISK_PREDICTION_EVALUATION.out.plots
    objects  = BIOC_SURVCOMP_SURVIVAL_RISK_PREDICTION_EVALUATION.out.objects
    versions = BIOC_SURVCOMP_SURVIVAL_RISK_PREDICTION_EVALUATION.out.versions
}
