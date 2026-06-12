#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SPsimSeq — simulate_single_cell_rna_seq
// Simulate single-cell RNA-seq data from a real single-cell RNA-seq template (SingleCellExperiment).
// Input: scNGP.data
// Container: quay.io/biocontainers/bioconductor-spsimseq:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SPsimSeq, SingleCellExperiment, edgeR
// Visualizations: box plot
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the single-cell source data
//  * 2. [Core Analysis] Run SPsimSeq with model.zero.prob = TRUE and result.format = "SCE"
//  * 3. [Core Analysis] Extract the simulated SingleCellExperiment object and access counts, colData, and rowData

nextflow.enable.dsl = 2

process BIOC_SPSIMSEQ_SIMULATE_SINGLE_CELL_RNA_SEQ {
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
    .bm_deps <- c("SPsimSeq", "edgeR")
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
        library(SPsimSeq)
        library(edgeR)
        
        # 1. Load the single-cell source data from the working directory
        # The user input file 'scNGP.data' is a SingleCellExperiment object saved as an RDS file.
        scNGP.data <- readRDS("scNGP.data")
        
        # Set seed for reproducibility
        set.seed(654321)
        
        # 2. Run SPsimSeq with model.zero.prob = TRUE and result.format = "SCE"
        sim.data.sc <- SPsimSeq(n.sim = 1, s.data = scNGP.data,
                                group = colData(scNGP.data)[[1]], 
                                n.genes = 4000, batch.config = 1,
                                group.config = c(0.5, 0.5), tot.samples = 100, 
                                pDE = 0.1, lfc.thrld = 0.5, model.zero.prob = TRUE,
                                result.format = "SCE")
        
        # 3. Extract the simulated SingleCellExperiment object and access counts, colData, and rowData
        sim.data.sc1 <- sim.data.sc[[1]]
        
        # Print basic information to console
        print(class(sim.data.sc1))
        print(head(counts(sim.data.sc1)[, seq_len(5)]))
        print(colData(sim.data.sc1))
        print(rowData(sim.data.sc1))
        
        # Save the simulated SingleCellExperiment object
        saveRDS(sim.data.sc1, "simulated_sc_sce.rds")
        
        # Save counts, colData, and rowData as CSV files
        write.csv(as.matrix(counts(sim.data.sc1)), "simulated_counts.csv", row.names = TRUE)
        write.csv(as.data.frame(colData(sim.data.sc1)), "simulated_coldata.csv", row.names = TRUE)
        write.csv(as.data.frame(rowData(sim.data.sc1)), "simulated_rowdata.csv", row.names = TRUE)
        
        # Generate comparison plots and save to PDF
        pdf("comparison_plots.pdf", width = 12, height = 8)
        
        # Normalize counts for comparison
        Y0.log.cpm  <- log2(edgeR::cpm(counts(scNGP.data))+1)
        Y1.log.cpm  <- log2(edgeR::cpm(counts(sim.data.sc1))+1)
        Y0.log.cpm  <- Y0.log.cpm[rowMeans(Y0.log.cpm>0)>=0.1, ]
        Y1.log.cpm  <- Y1.log.cpm[rowMeans(Y1.log.cpm>0)>=0.1, ]
        
        rowVars <- function(X){apply(X, 1, var, na.rm=TRUE)}
        rowCVs <- function(X){apply(X, 1, function(x) sd(x, na.rm=TRUE)/mean(x, na.rm=TRUE))}
        rowZeroFrac <- function(X){apply(X, 1, function(x) mean(x==0, na.rm=TRUE))}
        
        # Plot 1: Library size, mean expression, and variance comparison
        par(mfrow=c(1, 3))
        boxplot(list(real.data=colSums(counts(scNGP.data)), 
                     simulated.data=colData(sim.data.sc1)\$sim.Lib.Size), 
                main="library size") 
        boxplot(list(real.data=rowMeans(Y0.log.cpm), 
                     simulated.data=rowMeans(Y1.log.cpm)), 
                main="mean expression of genes") 
        boxplot(list(real.data=rowVars(Y0.log.cpm), 
                     simulated.data=rowVars(Y1.log.cpm)), 
                main="variance of gene expressions")
        
        # Plot 2: Mean vs CV relationship
        par(mfrow=c(1,3), mar=c(4,4,4,1))
        if (requireNamespace("LSD", quietly = TRUE)) {
          LSD::heatscatter(rowMeans(Y0.log.cpm), rowCVs(Y0.log.cpm), ylim=c(0, 6), xlim=c(0, 16),
                           colpal="bl2gr2rd", main="real data", xlab="mean log2-CPM", 
                           ylab="coefficients of variation", cexplot=0.5, alpha = 60, cex.lab=1.25)
          LSD::heatscatter(rowMeans(Y1.log.cpm), rowCVs(Y1.log.cpm), ylim=c(0, 6), xlim=c(0, 16),
                           main="SPsimSeq", xlab="mean log2-CPM", ylab="coefficients of variation", 
                           cexplot=0.5, alpha = 60, colpal="bl2gr2rd", cex.lab=1.25)
        } else {
          plot(rowMeans(Y0.log.cpm), rowCVs(Y0.log.cpm), ylim=c(0, 6), xlim=c(0, 16),
               main="real data", xlab="mean log2-CPM", ylab="coefficients of variation", col="blue", pch=20)
          plot(rowMeans(Y1.log.cpm), rowCVs(Y1.log.cpm), ylim=c(0, 6), xlim=c(0, 16),
               main="SPsimSeq", xlab="mean log2-CPM", ylab="coefficients of variation", col="red", pch=20)
        }
        
        n.gride <- 1000
        min.g   <- seq(0, 20, length.out = n.gride+1)[-n.gride]
        max.g   <- seq(0, 20, length.out = n.gride+1)[-1] 
        mid.g   <- (min.g+max.g)/2
        f.real  <- vapply(seq_len(n.gride), FUN.VALUE = double(1), function(r){
          x <- Y0.log.cpm[rowMeans(Y0.log.cpm)<=max.g[r] & rowMeans(Y0.log.cpm)>min.g[r],]
          y <- if (!is.null(dim(x))) mean(rowCVs(x)) else mean(sd(x)/mean(x)) 
          y
        })
        f.SPsim <- vapply(seq_len(n.gride), FUN.VALUE = double(1), function(r){
          x <- Y1.log.cpm[rowMeans(Y1.log.cpm)<=max.g[r] & rowMeans(Y1.log.cpm)>min.g[r],]
          y <- if (!is.null(dim(x))) mean(rowCVs(x)) else mean(sd(x)/mean(x)) 
          y
        })
        
        sm1 <- loess(I(f.SPsim-f.real)~mid.g) 
        plot(mid.g, f.SPsim-f.real, xlim=c(0, 14), col="lightskyblue", pch=20, cex.lab=1.25,
             cex.main=1.4, main="SPsimSeq - real data", ylab="difference", xlab="mean log2-CPM")
        lines(mid.g, predict(sm1, newdata = mid.g), col="blue", lwd=3)
        
        # Plot 3: Mean vs Fraction of Zeroes relationship
        par(mfrow=c(1,3), mar=c(4,4,4,1))
        if (requireNamespace("LSD", quietly = TRUE)) {
          LSD::heatscatter(rowMeans(Y0.log.cpm), rowZeroFrac(Y0.log.cpm), ylim=c(0, 1), 
                           xlim=c(0, 16), colpal="bl2gr2rd", main="real data", xlab="mean log2-CPM", 
                           ylab="fraction of zero counts", cexplot=0.5, alpha = 60, cex.lab=1.25)
          LSD::heatscatter(rowMeans(Y1.log.cpm), rowZeroFrac(Y1.log.cpm), ylim=c(0, 1), 
                           xlim=c(0, 16), main="SPsimSeq", xlab="mean log2-CPM", 
                           ylab="fraction of zero counts",  cexplot=0.5, alpha = 60,
                           colpal="bl2gr2rd", cex.lab=1.25)
        } else {
          plot(rowMeans(Y0.log.cpm), rowZeroFrac(Y0.log.cpm), ylim=c(0, 1), xlim=c(0, 16),
               main="real data", xlab="mean log2-CPM", ylab="fraction of zero counts", col="blue", pch=20)
          plot(rowMeans(Y1.log.cpm), rowZeroFrac(Y1.log.cpm), ylim=c(0, 1), xlim=c(0, 16),
               main="SPsimSeq", xlab="mean log2-CPM", ylab="fraction of zero counts", col="red", pch=20)
        }
        
        f.real.zero  <- vapply(seq_len(n.gride), FUN.VALUE = double(1), function(r){
          x <- Y0.log.cpm[rowMeans(Y0.log.cpm)<=max.g[r] & rowMeans(Y0.log.cpm)>min.g[r],]
          y <- if (!is.null(dim(x))) mean(rowZeroFrac(x)) else mean(x==0) 
          y
        })
        f.SPsim.zero <- vapply(seq_len(n.gride), FUN.VALUE = double(1), function(r){
          x <- Y1.log.cpm[rowMeans(Y1.log.cpm)<=max.g[r] & rowMeans(Y1.log.cpm)>min.g[r],]
          y <- if (!is.null(dim(x))) mean(rowZeroFrac(x)) else mean(x==0) 
          y
        })
        sm2 <- loess(I(f.SPsim.zero-f.real.zero)~mid.g) 
        plot(mid.g, f.SPsim.zero-f.real.zero, xlim=c(0, 14), col="lightskyblue", pch=20, cex.lab=1.25,
             cex.main=1.4, main="SPsimSeq - real data", ylab="difference", xlab="mean log2-CPM")
        lines(mid.g, predict(sm2, newdata = mid.g), col="blue", lwd=3)
        
        dev.off()

    writeLines(c(
        '"BIOC_SPSIMSEQ_SIMULATE_SINGLE_CELL_RNA_SEQ":',
        paste0('    SPsimSeq: ', as.character(packageVersion('SPsimSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simulate_single_cell_rna_seq.csv versions.yml
    """
}

workflow BIOC_SPSIMSEQ_SIMULATE_SINGLE_CELL_RNA_SEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ scNGP.data ] ]

    main:
    BIOC_SPSIMSEQ_SIMULATE_SINGLE_CELL_RNA_SEQ(ch_input)

    emit:
    tables   = BIOC_SPSIMSEQ_SIMULATE_SINGLE_CELL_RNA_SEQ.out.tables
    plots    = BIOC_SPSIMSEQ_SIMULATE_SINGLE_CELL_RNA_SEQ.out.plots
    objects  = BIOC_SPSIMSEQ_SIMULATE_SINGLE_CELL_RNA_SEQ.out.objects
    versions = BIOC_SPSIMSEQ_SIMULATE_SINGLE_CELL_RNA_SEQ.out.versions
}
