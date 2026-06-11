#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flagme — gc_ms_alignment_workflow
// Read raw GC-MS data, import peak deconvolution results, perform multiple alignment across experimental groups, and extract the aligned peak table.
// Input: cdfFiles, eluFiles
// Container: quay.io/biocontainers/bioconductor-flagme:1.66.0--r45h01b2380_0
// R packages: flagme, gcspikelite
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLAGME_GC_MS_ALIGNMENT_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-flagme:1.66.0--r45h01b2380_0"

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
    .bm_deps <- c("flagme", "gcspikelite")
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
    library(flagme)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Find CDF files in the working directory
    cdfFiles <- list.files(pattern = "\\\\.(cdf|CDF)\$", full.names = TRUE)
    if (length(cdfFiles) == 0) {
      stop("Error: No CDF files found in the working directory.")
    }
    
    # Find or construct corresponding ELU files
    eluFiles <- gsub("\\\\.(cdf|CDF)\$", ".ELU", cdfFiles, ignore.case = TRUE)
    if (!all(file.exists(eluFiles))) {
      # Fallback: search for any ELU files if direct replacement doesn't match
      eluFiles <- list.files(pattern = "\\\\.(elu|ELU)\$", full.names = TRUE)
    }
    
    if (length(eluFiles) == 0) {
      stop("Error: No ELU files found in the working directory.")
    }
    
    if (length(cdfFiles) != length(eluFiles)) {
      stop("Error: The number of CDF files and ELU files must match.")
    }
    
    # Set up experimental groups (targets)
    if (file.exists("targets.csv")) {
      targets <- read.csv("targets.csv", stringsAsFactors = FALSE)
    } else {
      # Create default groups if targets.csv is not provided
      # Split samples into groups of 3 (or fewer if total samples < 3)
      groups <- as.character(gl(ceiling(length(cdfFiles) / 3), 3, length(cdfFiles)))
      targets <- data.frame(
        FileName = basename(cdfFiles),
        Group = groups,
        stringsAsFactors = FALSE
      )
    }
    
    # ==========================================
    # 2. Run flagme Alignment Workflow
    # ==========================================
    
    # Step 1: Read raw NetCDF files into a peaksDataset object
    pd <- peaksDataset(cdfFiles, mz=seq(50,550), rtrange=c(7.5,8.5))
    
    # Step 2: Add AMDIS peak detection results
    pd <- addAMDISPeaks(pd, eluFiles)
    
    # Step 3: Perform multiple alignment across experimental groups
    ma <- multipleAlignment(pd, group=targets\$Group, wn.gap=0.5, wn.D=.05, 
                            bw.gap=.6, bw.D=0.05, usePeaks=TRUE, filterMin=1, 
                            df=50, verbose=FALSE, metric = 1, type = 1)
    
    # Step 4: Extract aligned peak information
    outList <- gatherInfo(pd, ma)
    
    # Construct retention time matrix
    rtmat <- matrix(unlist(lapply(outList, .subset, "rt"), use.names=FALSE), 
                    nr=length(outList), byrow=TRUE)
    colnames(rtmat) <- names(outList[[1]]\$rt)
    rownames(rtmat) <- 1:nrow(rtmat)
    rtmat_rounded <- round(rtmat, 3)
    
    # ==========================================
    # 3. Save Outputs and Plots
    # ==========================================
    
    # Save the processed objects
    saveRDS(pd, "peaks_dataset.rds")
    saveRDS(ma, "multiple_alignment.rds")
    saveRDS(outList, "aligned_peaks_info.rds")
    
    # Save the aligned retention time matrix
    write.csv(rtmat_rounded, "aligned_rt_matrix.csv", row.names = TRUE)
    
    # Generate and save alignment visualization plot
    pdf("alignment_chromatogram_plot.pdf", width = 11, height = 8.5)
    tryCatch({
      plotChrom(pd, rtrange=c(7.5,8.5), runs=ma@betweenAlignment@runs,
                mind=ma@betweenAlignment@ind, plotPeaks=TRUE,
                plotPeakLabels=TRUE, max.near=8, how.near=.5,
                col=rep(c("blue","red","black"), length.out=length(cdfFiles)))
    }, error = function(e) {
      warning("Could not generate chromatogram plot: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_FLAGME_GC_MS_ALIGNMENT_WORKFLOW":',
        paste0('        flagme: ', as.character(packageVersion("flagme")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gc_ms_alignment_workflow.csv versions.yml
    """
}

workflow BIOC_FLAGME_GC_MS_ALIGNMENT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cdfFiles, eluFiles ] ]

    main:
    BIOC_FLAGME_GC_MS_ALIGNMENT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_FLAGME_GC_MS_ALIGNMENT_WORKFLOW.out.tables
    plots    = BIOC_FLAGME_GC_MS_ALIGNMENT_WORKFLOW.out.plots
    objects  = BIOC_FLAGME_GC_MS_ALIGNMENT_WORKFLOW.out.objects
    versions = BIOC_FLAGME_GC_MS_ALIGNMENT_WORKFLOW.out.versions
}
