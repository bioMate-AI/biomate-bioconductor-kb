#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flagme — multiple_group_alignment
// Align peaks across multiple experimental groups and extract a consensus matrix of retention times and fragment intensities.
// Input: cdfFiles, eluFiles, targets
// Container: quay.io/biocontainers/bioconductor-flagme:1.66.0--r45h01b2380_0
// R packages: flagme
// Bioconductor: 3.20 | R: 4.4
// Requires: flagme
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a peaks dataset from raw CDF files using peaksDataset
//  * 2. [Core Analysis] Add peak deconvolution results using addAMDISPeaks
//  * 3. [Core Analysis] Perform multiple alignment across groups using multipleAlignment
//  * 4. [Core Analysis] Gather aligned peak information using gatherInfo

nextflow.enable.dsl = 2

process BIOC_FLAGME_MULTIPLE_GROUP_ALIGNMENT {
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
    .bm_deps <- c("flagme")
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
    
    # 1. Read targets metadata from the working directory
    targets_file <- list.files(pattern = "targets\\\\.(csv|txt|tsv)", ignore.case = TRUE)[1]
    if (is.na(targets_file)) {
      stop("Error: No targets metadata file (targets.csv, targets.txt, or targets.tsv) found in the working directory.")
    }
    
    if (grepl("\\\\.csv\$", targets_file, ignore.case = TRUE)) {
      targets <- read.csv(targets_file, stringsAsFactors = FALSE)
    } else {
      targets <- read.delim(targets_file, stringsAsFactors = FALSE)
    }
    
    if (!"Group" %in% colnames(targets)) {
      stop("Error: The targets file must contain a 'Group' column.")
    }
    
    # 2. Identify CDF files
    if (!"FileName" %in% colnames(targets)) {
      stop("Error: The targets file must contain a 'FileName' column.")
    }
    cdfFiles <- targets\$FileName
    
    # Verify CDF files exist
    if (!all(file.exists(cdfFiles))) {
      basename_cdf <- basename(cdfFiles)
      if (all(file.exists(basename_cdf))) {
        cdfFiles <- basename_cdf
      } else {
        stop("Error: Some CDF files specified in targets are missing from the working directory.")
      }
    }
    
    # 3. Identify ELU files
    eluFiles <- gsub("\\\\.cdf\$", ".ELU", cdfFiles, ignore.case = TRUE)
    if (!all(file.exists(eluFiles))) {
      eluFiles_lower <- gsub("\\\\.cdf\$", ".elu", cdfFiles, ignore.case = TRUE)
      if (all(file.exists(eluFiles_lower))) {
        eluFiles <- eluFiles_lower
      } else {
        eluFiles_dir <- list.files(pattern = "\\\\.elu\$", ignore.case = TRUE)
        if (length(eluFiles_dir) > 0) {
          cdf_bases <- tools::file_path_sans_ext(basename(cdfFiles))
          elu_bases <- tools::file_path_sans_ext(basename(eluFiles_dir))
          matched_elu <- eluFiles_dir[match(cdf_bases, elu_bases)]
          if (!any(is.na(matched_elu))) {
            eluFiles <- matched_elu
          } else {
            stop("Error: Could not map CDF files to corresponding ELU files in the working directory.")
          }
        } else {
          stop("Error: No ELU files found in the working directory.")
        }
      }
    }
    
    # 4. Run the documented flagme workflow
    # Create a peaks dataset from raw CDF files
    pd <- peaksDataset(cdfFiles, mz=seq(50,550))
    
    # Add peak deconvolution results
    pd <- addAMDISPeaks(pd, eluFiles)
    
    # Perform multiple alignment across groups
    ma <- multipleAlignment(pd, group=targets\$Group, wn.gap=0.5, wn.D=.05,
                            bw.gap=.6, bw.D=0.05, usePeaks=TRUE, filterMin=1, 
                            df=50, verbose=FALSE, metric = 1, type = 1)
    
    # Gather aligned peak information
    outList <- gatherInfo(pd,ma)
    
    # Extract consensus matrix of retention times
    rtmat <- matrix(unlist(lapply(outList,.subset,"rt"), use.names=FALSE),
                    nr=length(outList), byrow=TRUE)
    colnames(rtmat) <- names(outList[[1]]\$rt); rownames(rtmat) <- 1:nrow(rtmat)
    
    # 5. Save outputs
    write.csv(rtmat, "aligned_rt_matrix.csv", row.names=TRUE)
    saveRDS(pd, "peaks_dataset.rds")
    saveRDS(ma, "multiple_alignment.rds")
    saveRDS(outList, "aligned_peaks_info.rds")
    
    # Generate diagnostic plot
    pdf("alignment_chromatogram.pdf", width=10, height=7)
    plotChrom(pd, runs=ma@betweenAlignment@runs,
              mind=ma@betweenAlignment@ind, plotPeaks=TRUE,
              plotPeakLabels=TRUE, max.near=8, how.near=.5,
              col=rep(c("blue","red","black"), length.out=length(cdfFiles)))
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_FLAGME_MULTIPLE_GROUP_ALIGNMENT":',
        paste0('    flagme: ', as.character(packageVersion('flagme')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_group_alignment.csv versions.yml
    """
}

workflow BIOC_FLAGME_MULTIPLE_GROUP_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cdfFiles, eluFiles, targets ] ]

    main:
    BIOC_FLAGME_MULTIPLE_GROUP_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_FLAGME_MULTIPLE_GROUP_ALIGNMENT.out.tables
    plots    = BIOC_FLAGME_MULTIPLE_GROUP_ALIGNMENT.out.plots
    objects  = BIOC_FLAGME_MULTIPLE_GROUP_ALIGNMENT.out.objects
    versions = BIOC_FLAGME_MULTIPLE_GROUP_ALIGNMENT.out.versions
}
