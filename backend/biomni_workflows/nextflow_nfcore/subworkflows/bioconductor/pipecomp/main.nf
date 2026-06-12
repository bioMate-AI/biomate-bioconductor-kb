#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pipeComp — bulk_rna_seq_dea_benchmarking
// Benchmark and evaluate bulk RNA-seq differential expression analysis pipelines (filtering, SVA, and DEA steps) on datasets with known ground truth.
// Input: dataset1.rds, dataset2.rds
// Container: quay.io/biocontainers/bioconductor-pipecomp:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, S4Vectors, SummarizedExperiment, edgeR, ggplot2, pipeComp, sva
// Visualizations: heatmap
// QC: filter low-expression genes, TMM normalization, dispersion/size-factor estimation, batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define evaluation function evaluateDEA
//  * 2. [Input & Preparation] Define step functions for filtering, SVA, and DEA
//  * 3. [Core Analysis] Assemble the PipelineDefinition object using PipelineDefinition
//  * 4. [Core Analysis] Add the evaluation function to the DEA step using stepFn
//  * 5. [Input & Preparation] Define alternative parameter values and wrapper functions
//  * 6. [Core Analysis] Run the pipeline using runPipeline
//  * 7. [Visualization & Output] Plot results using plotElapsed, evalHeatmap, and dea_evalPlot_curve

nextflow.enable.dsl = 2

process BIOC_PIPECOMP_BULK_RNA_SEQ_DEA_BENCHMARKING {
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
    .bm_deps <- c("pipeComp", "S4Vectors", "edgeR", "sva", "ggplot2", "ComplexHeatmap")
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
        library(pipeComp)
        library(S4Vectors)
        library(edgeR)
        library(sva)
        library(ggplot2)
        library(ComplexHeatmap)
        
        # 1. Read the user input files from the working directory
        dataset1 <- readRDS("dataset1.rds")
        dataset2 <- readRDS("dataset2.rds")
        
        # Ensure metadata(x)\$truth is populated from rowData if not already present
        if (is.null(metadata(dataset1)\$truth)) {
          metadata(dataset1)\$truth <- as.data.frame(rowData(dataset1))
        }
        if (is.null(metadata(dataset2)\$truth)) {
          metadata(dataset2)\$truth <- as.data.frame(rowData(dataset2))
        }
        
        datasets <- list(
          dataset1 = dataset1,
          dataset2 = dataset2
        )
        
        # 2. Define evaluation function evaluateDEA
        evaluateDEA <- function(dea, truth=NULL, th=c(0.01,0.05,0.1)){
          dea <- pipeComp:::.homogenizeDEA(dea)
          if(is.null(truth)) truth <- metadata(dea)\$truth
          dea <- cbind(dea, truth[row.names(dea),])
          dea <- dea[!is.na(dea\$expected.beta),]
          res <- c(logFC.pearson=cor(dea\$logFC, dea\$expected.beta, use = "pairwise"), logFC.spearman=cor(dea\$logFC, dea\$expected.beta, use = "pairwise", method="spearman"), logFC.mad=median(abs(dea\$logFC-dea\$expected.beta),na.rm=TRUE), ntested=sum(!is.na(dea\$PValue) & !is.na(dea\$FDR)))
          names(th) <- th
          res2 <- t(vapply( th, FUN.VALUE=vector(mode="numeric", length=6), FUN=function(x){
            called=sum(dea\$FDR<x,na.rm=TRUE)
            P <- sum(dea\$isDE)
            TP <- sum(dea\$FDR<x & dea\$isDE, na.rm=TRUE)
            c( TP=TP, FP=called-TP, TPR=TP/P, PPV=TP/called, FDR=1-TP/called, FPR=(P-TP)/sum(!dea\$isDE) )
          }))
          res2 <- cbind(threshold=as.numeric(row.names(res2)), as.data.frame(res2))
          row.names(res2) <- NULL
          list(logFC=res, significance=res2)
        }
        
        # 3. Define step functions for filtering, SVA, and DEA
        step.filtering <- function(x, filt, minCount=10){
          get(filt)(x, minCount=minCount)
        }
        
        step.sva <- function(x, sva.method, k=1){
          mm <- stats::model.matrix(~condition, data=as.data.frame(colData(x)))
          # Ensure the condition column name is standardized to "condition" for downstream edgeR
          colnames(mm)[grep("condition", colnames(mm))] <- "condition"
          get(sva.method)(x, k=k, mm=mm)
        }
        
        step.dea <- function(x, dea.method){
          # Reconstruct mm including any SVs added to colData(x)
          cd <- as.data.frame(colData(x))
          sv_cols <- grep("^SV", colnames(cd), value=TRUE)
          if(length(sv_cols) > 0){
            formula_str <- paste("~condition +", paste(sv_cols, collapse=" + "))
          } else {
            formula_str <- "~condition"
          }
          mm <- stats::model.matrix(as.formula(formula_str), data=cd)
          colnames(mm)[grep("condition", colnames(mm))] <- "condition"
          
          x2 <- DataFrame(get(dea.method)(x,mm))
          metadata(x2)\$truth <- metadata(x)\$truth
          x2
        }
        
        # 4. Assemble the PipelineDefinition object using PipelineDefinition
        pip <- PipelineDefinition( list( filtering=step.filtering, sva=step.sva, dea=step.dea ) )
        
        # 5. Add the evaluation function to the DEA step using stepFn
        stepFn(pip, step="dea", type="evaluation") <- evaluateDEA
        
        # 6. Define alternative parameter values and wrapper functions
        def.filter <- function(x, minCounts=10){
          library(edgeR)
          minCounts <- as.numeric(minCounts)
          x[filterByExpr(assay(x), model.matrix(~x\$condition), min.count=minCounts),]
        }
        
        sva.svaseq <- function(x, k, mm){
          k <- as.integer(k)
          if(k==0) return(x)
          library(sva)
          sv <- svaseq(assay(x), mod=mm, n.sv=k)
          if(sv\$n.sv==0) return(x)
          colnames(sv\$sv) <- paste0("SV", seq_len(ncol(sv\$sv)))
          colData(x) <- cbind(colData(x), sv\$sv)
          x
        }
        
        dea.edgeR <- function(x, mm){
          library(edgeR)
          dds <- calcNormFactors(DGEList(assay(x)))
          dds <- estimateDisp(dds, mm)
          fit <- glmFit(dds, mm)
          as.data.frame(topTags(glmLRT(fit, "condition"), Inf))
        }
        
        none <- function(x, ...) x
        
        alternatives <- list(
          filt=c("none","def.filter"),
          minCount=10,
          sva.method=c("none","sva.svaseq"),
          k=1:2,
          dea.method="dea.edgeR"
        )
        
        # 7. Run the pipeline using runPipeline (using 1 thread for maximum compatibility)
        res <- runPipeline( datasets, alternatives, pipelineDef=pip, nthreads=1 )
        
        # Save the pipeline results object
        saveRDS(res, "pipeline_results.rds")
        
        # Save evaluation tables as CSV files
        write.csv(res\$evaluation\$dea\$logFC, "evaluation_dea_logFC.csv", row.names=FALSE)
        write.csv(res\$evaluation\$dea\$significance, "evaluation_dea_significance.csv", row.names=FALSE)
        
        # 8. Plot results and save to PDF files
        pdf("plot_elapsed.pdf", width=7, height=5)
        print(plotElapsed(res, agg.by="sva.method"))
        dev.off()
        
        pdf("plot_heatmap_overall.pdf", width=8, height=6)
        print(evalHeatmap( res, what=c("TPR","FDR","logFC.pearson"), agg.by=c("sva.method", "dea.method"), row_split = "sva.method" ))
        dev.off()
        
        pdf("plot_heatmap_threshold_0.05.pdf", width=8, height=6)
        print(evalHeatmap( res, what=c("TPR","FDR"), agg.by=c("sva.method", "dea.method"), row_split="sva.method", filterExpr=threshold==0.05 ))
        dev.off()
        
        pdf("plot_curves_sva_dea.pdf", width=8, height=6)
        print(dea_evalPlot_curve(res, agg.by=c("sva.method","dea.method"), colourBy="sva.method", shapeBy="dea.method"))
        dev.off()
        
        pdf("plot_curves_sva_only.pdf", width=8, height=6)
        print(dea_evalPlot_curve(res, agg.by=c("sva.method")) + ggtitle("SVA methods, averaging across DEA methods"))
        dev.off()
        
        pdf("plot_heatmap_sva_k.pdf", width=8, height=6)
        print(evalHeatmap(res, what=c("TPR","FDR"), agg.by=c("sva.method","k"), show_column_names=TRUE, anno_legend = FALSE, row_split="sva.method", filterExpr=threshold==0.05 ))
        dev.off()

    writeLines(c(
        '"BIOC_PIPECOMP_BULK_RNA_SEQ_DEA_BENCHMARKING":',
        paste0('    pipeComp: ', as.character(packageVersion('pipeComp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bulk_rna_seq_dea_benchmarking.csv versions.yml
    """
}

workflow BIOC_PIPECOMP_BULK_RNA_SEQ_DEA_BENCHMARKING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataset1.rds, dataset2.rds ] ]

    main:
    BIOC_PIPECOMP_BULK_RNA_SEQ_DEA_BENCHMARKING(ch_input)

    emit:
    tables   = BIOC_PIPECOMP_BULK_RNA_SEQ_DEA_BENCHMARKING.out.tables
    plots    = BIOC_PIPECOMP_BULK_RNA_SEQ_DEA_BENCHMARKING.out.plots
    objects  = BIOC_PIPECOMP_BULK_RNA_SEQ_DEA_BENCHMARKING.out.objects
    versions = BIOC_PIPECOMP_BULK_RNA_SEQ_DEA_BENCHMARKING.out.versions
}
