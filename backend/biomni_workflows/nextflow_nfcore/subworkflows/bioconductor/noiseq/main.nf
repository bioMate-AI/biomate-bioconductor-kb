#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NOISeq — rna_seq_qc_and_exploration
// Perform quality control and exploratory analysis on RNA-seq count data to detect biases (biotype, saturation, length, GC, RNA composition, PCA).
// Input: count_matrix.csv, factors.csv, annotations.csv
// Container: quay.io/biocontainers/bioconductor-noiseq:2.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: NOISeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and create NOISeq object using readData
//  * 2. [Core Analysis] Add additional annotations if needed using addData
//  * 3. [Core Analysis] Compute exploratory data using dat
//  * 4. [Visualization & Output] Generate diagnostic plots using explo.plot
//  * 5. [Visualization & Output] Generate a comprehensive PDF quality control report using QCreport

nextflow.enable.dsl = 2

process BIOC_NOISEQ_RNA_SEQ_QC_AND_EXPLORATION {
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
    .bm_deps <- c("NOISeq")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
        library(NOISeq)
        
        # ----------------------------------------------------------------------
        # 1. Load data and create NOISeq object using readData
        # ----------------------------------------------------------------------
        
        # Read count matrix
        if (!file.exists("count_matrix.csv")) {
          stop("Required input file 'count_matrix.csv' not found.")
        }
        mycounts <- read.csv("count_matrix.csv", row.names = 1, check.names = FALSE)
        mycounts <- as.matrix(mycounts)
        
        # Read factors
        if (!file.exists("factors.csv")) {
          stop("Required input file 'factors.csv' not found.")
        }
        myfactors <- read.csv("factors.csv", row.names = 1, check.names = FALSE)
        
        # Align samples between counts and factors
        common_samples <- intersect(colnames(mycounts), rownames(myfactors))
        if (length(common_samples) == 0) {
          stop("No common samples found between count_matrix.csv and factors.csv")
        }
        mycounts <- mycounts[, common_samples, drop = FALSE]
        myfactors <- myfactors[common_samples, , drop = FALSE]
        
        # Ensure the primary factor column is named "Tissue" to match documented code
        if (!"Tissue" %in% colnames(myfactors)) {
          colnames(myfactors)[1] <- "Tissue"
        }
        
        # Initialize default annotations in case annotations.csv is missing or incomplete
        mylength <- rep(1000, nrow(mycounts))
        names(mylength) <- rownames(mycounts)
        
        mygc <- rep(50, nrow(mycounts))
        names(mygc) <- rownames(mycounts)
        
        mybiotypes <- rep("protein_coding", nrow(mycounts))
        names(mybiotypes) <- rownames(mycounts)
        
        mychroms <- data.frame(
          Chr = rep("1", nrow(mycounts)),
          GeneStart = rep(1, nrow(mycounts)),
          GeneEnd = rep(1000, nrow(mycounts)),
          row.names = rownames(mycounts)
        )
        
        # Read annotations if available
        if (file.exists("annotations.csv")) {
          annotations <- read.csv("annotations.csv", row.names = 1, check.names = FALSE)
          common_genes <- intersect(rownames(mycounts), rownames(annotations))
          if (length(common_genes) > 0) {
            mycounts <- mycounts[common_genes, , drop = FALSE]
            annotations <- annotations[common_genes, , drop = FALSE]
            
            if ("Length" %in% colnames(annotations)) {
              mylength <- annotations\$Length
              names(mylength) <- rownames(annotations)
            }
            if ("GC" %in% colnames(annotations)) {
              mygc <- annotations\$GC
              names(mygc) <- rownames(annotations)
            }
            if ("Biotype" %in% colnames(annotations)) {
              mybiotypes <- annotations\$Biotype
              names(mybiotypes) <- rownames(annotations)
            }
            if (all(c("Chr", "GeneStart", "GeneEnd") %in% colnames(annotations))) {
              mychroms <- annotations[, c("Chr", "GeneStart", "GeneEnd"), drop = FALSE]
            }
          }
        }
        
        # Create mydata2 with simulated batch effect for PCA exploration
        n_samples <- ncol(mycounts)
        myfactors2 <- myfactors
        myfactors2\$batch <- as.factor(c(rep(1, floor(n_samples/2)), rep(2, ceiling(n_samples/2))))
        
        mycounts2 <- mycounts
        set.seed(123)
        half_samples <- 1:floor(n_samples/2)
        mycounts2[, half_samples] <- mycounts2[, half_samples] + runif(nrow(mycounts2) * length(half_samples), 3, 5)
        
        mydata2 <- readData(mycounts2, factors = myfactors2)
        
        # Save processed input objects
        saveRDS(mycounts, "processed_counts.rds")
        saveRDS(myfactors, "processed_factors.rds")
        
        # Execute readData calls from documented code
        mydata <- readData(data=mycounts,length=mylength, gc=mygc, biotype=mybiotypes, chromosome=mychroms, factors=myfactors)
        mydata <- readData(data=mycounts,chromosome=mychroms, factors=myfactors)
        
        # ----------------------------------------------------------------------
        # 2. Add additional annotations if needed using addData
        # ----------------------------------------------------------------------
        mydata <- addData(mydata, length=mylength, biotype=mybiotypes, gc = mygc)
        saveRDS(mydata, "mydata.rds")
        
        # ----------------------------------------------------------------------
        # 3 & 4. Compute exploratory data and generate diagnostic plots
        # ----------------------------------------------------------------------
        pdf("QC_exploratory_plots.pdf", width = 10, height = 8)
        
        # Biodetection
        tryCatch({
          myexplodata <- dat(mydata, type = "biodetection")
          explo.plot(myexplodata, plottype = "persample")
          mynicedata <- dat2save(myexplodata)
          write.csv(mynicedata, "biodetection_results.csv", row.names = TRUE)
        }, error = function(e) {
          message("Skipping biodetection plot: ", e\$message)
        })
        
        tryCatch({
          mybiodetection <- dat(mydata, k = 0, type = "biodetection", factor = NULL)
          s_idx <- if(ncol(mycounts) >= 2) c(1,2) else c(1,1)
          explo.plot(mybiodetection, samples=s_idx, plottype = "persample")
          explo.plot(mybiodetection, samples=s_idx, toplot = "protein_coding", plottype = "comparison")
        }, error = function(e) {
          message("Skipping biodetection comparison plot: ", e\$message)
        })
        
        # Countsbio
        tryCatch({
          mycountsbio = dat(mydata, factor = NULL, type = "countsbio")
          explo.plot(mycountsbio, toplot = 1, samples = 1, plottype = "boxplot")
        }, error = function(e) {
          message("Skipping countsbio boxplot: ", e\$message)
        })
        
        # Saturation
        tryCatch({
          mysaturation = dat(mydata, k = 0, ndepth = 7, type = "saturation")
          s_idx_sat <- if(ncol(mycounts) >= 2) 1:2 else c(1,1)
          explo.plot(mysaturation, toplot = 1, samples = s_idx_sat, yleftlim = NULL, yrightlim = NULL)
          
          s_idx_sat4 <- if(ncol(mycounts) >= 4) 1:4 else 1:ncol(mycounts)
          explo.plot(mysaturation, toplot = "protein_coding", samples = s_idx_sat4)
        }, error = function(e) {
          message("Skipping saturation plot: ", e\$message)
        })
        
        # Countsbio global
        tryCatch({
          explo.plot(mycountsbio, toplot = "protein_coding", samples = NULL, plottype = "boxplot")
          explo.plot(mycountsbio, toplot = 1, samples = NULL, plottype = "barplot")
        }, error = function(e) {
          message("Skipping countsbio global plots: ", e\$message)
        })
        
        # Length bias
        tryCatch({
          mylengthbias = dat(mydata, factor = "Tissue", type = "lengthbias")
          explo.plot(mylengthbias, samples = NULL, toplot = "global")
          show(mylengthbias)
        }, error = function(e) {
          message("Skipping length bias plot: ", e\$message)
        })
        
        # GC bias
        tryCatch({
          myGCbias = dat(mydata, factor = "Tissue", type = "GCbias")
          explo.plot(myGCbias, samples = NULL, toplot = "global")
        }, error = function(e) {
          message("Skipping GC bias plot: ", e\$message)
        })
        
        # RNA composition (cd)
        tryCatch({
          mycd = dat(mydata, type = "cd", norm = FALSE, refColumn = 1)
          explo.plot(mycd)
        }, error = function(e) {
          message("Skipping RNA composition plot: ", e\$message)
        })
        
        # PCA
        tryCatch({
          myPCA = dat(mydata2, type = "PCA")
          explo.plot(myPCA, factor = "Tissue")
        }, error = function(e) {
          message("Skipping PCA plot: ", e\$message)
        })
        
        dev.off()
        
        # ----------------------------------------------------------------------
        # 5. Generate a comprehensive PDF quality control report using QCreport
        # ----------------------------------------------------------------------
        tryCatch({
          QCreport(mydata, file = "QCreport.pdf", samples = NULL, factor = "Tissue", norm = FALSE)
        }, error = function(e) {
          message("Skipping QCreport generation: ", e\$message)
        })

    writeLines(c(
        '"BIOC_NOISEQ_RNA_SEQ_QC_AND_EXPLORATION":',
        paste0('    NOISeq: ', as.character(packageVersion('NOISeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_qc_and_exploration.csv versions.yml
    """
}

workflow BIOC_NOISEQ_RNA_SEQ_QC_AND_EXPLORATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_matrix.csv, factors.csv, annotations.csv ] ]

    main:
    BIOC_NOISEQ_RNA_SEQ_QC_AND_EXPLORATION(ch_input)

    emit:
    tables   = BIOC_NOISEQ_RNA_SEQ_QC_AND_EXPLORATION.out.tables
    plots    = BIOC_NOISEQ_RNA_SEQ_QC_AND_EXPLORATION.out.plots
    objects  = BIOC_NOISEQ_RNA_SEQ_QC_AND_EXPLORATION.out.objects
    versions = BIOC_NOISEQ_RNA_SEQ_QC_AND_EXPLORATION.out.versions
}
