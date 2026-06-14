#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genoCN — germline_cnv_calling
// Identify germline copy number variations (CNVs) and genotype calls from SNP array data.
// Input: snp_data.txt, cnv_parameter.txt
// Container: quay.io/biocontainers/bioconductor-genocn:1.58.0--r44h3df3fcb_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: genoCN
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the HMM parameter specifications using read.parameter
//  * 2. [Core Analysis] Initialize the HMM parameters using init.para
//  * 3. [Core Analysis] Run the HMM estimation and state calling using genoCNV

nextflow.enable.dsl = 2

process BIOC_GENOCN_GERMLINE_CNV_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("genoCN")
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
            
            # Load required library
            library(genoCN)
            
            # Define input file paths
            snp_data_path <- "snp_data.txt"
            parameter_path <- "cnv_parameter.txt"
            
            # Check if input files exist
            if (!file.exists(snp_data_path)) {
              stop(paste("Required input file missing:", snp_data_path))
            }
            if (!file.exists(parameter_path)) {
              stop(paste("Required input file missing:", parameter_path))
            }
            
            # 1. Read the germline HMM parameter specifications using read.parameter with CNA=FALSE
            pInfo <- read.parameter(parameter_path, CNA=FALSE)
            
            # Read the SNP data
            df <- read.delim(snp_data_path, header=TRUE, sep="\t", stringsAsFactors=FALSE)
            
            # Identify columns robustly (handling variations in casing and naming)
            chr_col <- grep("^(chr|chromosome)\$", colnames(df), ignore.case=TRUE, value=TRUE)[1]
            pos_col <- grep("^(pos|position)\$", colnames(df), ignore.case=TRUE, value=TRUE)[1]
            lrr_col <- grep("^lrr\$", colnames(df), ignore.case=TRUE, value=TRUE)[1]
            baf_col <- grep("^baf\$", colnames(df), ignore.case=TRUE, value=TRUE)[1]
            snp_col <- grep("^(snp|name|marker|rsid)\$", colnames(df), ignore.case=TRUE, value=TRUE)[1]
            
            if (is.na(chr_col) || is.na(pos_col) || is.na(lrr_col) || is.na(baf_col)) {
              stop("Could not find all required columns (chromosome/chr, position/pos, LRR, BAF) in snp_data.txt")
            }
            
            # Extract or generate SNP names
            if (!is.na(snp_col)) {
              snpNames <- df[[snp_col]]
            } else {
              snpNames <- paste0("SNP", seq_len(nrow(df)))
            }
            
            # Construct snp_info and snp_data to match documented code variables exactly
            snp_info <- list(
              name = snpNames,
              chr = df[[chr_col]],
              pos = df[[pos_col]]
            )
            snp_data <- list(
              LRR = df[[lrr_col]],
              BAF = df[[baf_col]]
            )
            
            # 2. Initialize the germline HMM parameters using init.para
            ip <- init.para(pInfo, sampleid="sample1", LRR=snp_data\$LRR, BAF=snp_data\$BAF, pos=snp_info\$pos, chr=snp_info\$chr, CNA=FALSE)
            
            # Create output directory for results
            output_dir <- "genoCN_output"
            if (!dir.exists(output_dir)) {
              dir.create(output_dir, recursive=TRUE)
            }
            
            # 3. Run the germline HMM estimation and state calling using genoCNV
            genoCNV(snp_info\$name, snp_info\$chr, snp_info\$pos, snp_data\$LRR, snp_data\$BAF, pInfo, sampleid="sample1", output.dir=output_dir)
            
            # Save the initialized parameter object as an RDS file for downstream analysis
            saveRDS(ip, file=file.path(output_dir, "initialized_parameters.rds"))
            
            message("genoCN germline CNV calling pipeline completed successfully. Outputs written to: ", output_dir)

    writeLines(c(
        '"BIOC_GENOCN_GERMLINE_CNV_CALLING":',
        paste0('    genoCN: ', as.character(packageVersion('genoCN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_germline_cnv_calling.csv versions.yml
    """
}

workflow BIOC_GENOCN_GERMLINE_CNV_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ snp_data.txt, cnv_parameter.txt ] ]

    main:
    BIOC_GENOCN_GERMLINE_CNV_CALLING(ch_input)

    emit:
    tables   = BIOC_GENOCN_GERMLINE_CNV_CALLING.out.tables
    plots    = BIOC_GENOCN_GERMLINE_CNV_CALLING.out.plots
    objects  = BIOC_GENOCN_GERMLINE_CNV_CALLING.out.objects
    versions = BIOC_GENOCN_GERMLINE_CNV_CALLING.out.versions
}
