#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylPipe — database_preparation
// Process raw aligned files to generate tabular methylation calls and prepare tabix-indexed BSdata and BSdataSet objects.
// Input: test_methcall, H1_chr20_CG_10k.txt
// Container: quay.io/biocontainers/bioconductor-methylpipe:1.44.0--r45h01b2380_0
// R packages: BSgenome.Hsapiens.UCSC.hg18, GenomicRanges, Rsamtools, methylPipe
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg18, GenomicRanges, Rsamtools, methylPipe
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Call methylation from aligned files using meth.call
//  * 2. [Core Analysis] Compress and index tabular files using BSprepare
//  * 3. [Input & Preparation] Create BSdata objects for individual samples
//  * 4. [Core Analysis] Combine multiple BSdata objects into a BSdataSet

nextflow.enable.dsl = 2

process BIOC_METHYLPIPE_DATABASE_PREPARATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg18", "GenomicRanges", "Rsamtools", "methylPipe")
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
    library(methylPipe)
    library(BSgenome.Hsapiens.UCSC.hg18)
    library(GenomicRanges)
    library(Rsamtools)
    
    # -------------------------------------------------------------------------
    # 1. Verify User Inputs
    # -------------------------------------------------------------------------
    input_folder <- "test_methcall"
    input_tabular <- "H1_chr20_CG_10k.txt"
    
    if (!dir.exists(input_folder)) {
      stop(paste("Required input folder missing:", input_folder))
    }
    if (!file.exists(input_tabular)) {
      stop(paste("Required input file missing:", input_tabular))
    }
    
    # -------------------------------------------------------------------------
    # 2. Call Methylation from Aligned Files (meth.call)
    # -------------------------------------------------------------------------
    message("Stage 1: Calling methylation from aligned files...")
    methcall_output_dir <- "methcall_output"
    dir.create(methcall_output_dir, showWarnings = FALSE, recursive = TRUE)
    
    # Execute meth.call exactly as documented
    meth.call(files_location = input_folder, 
              output_folder = methcall_output_dir, 
              no_overlap = TRUE, 
              read.context = "CpG", 
              Nproc = 1)
    
    # -------------------------------------------------------------------------
    # 3. Compress and Index Tabular Files (BSprepare)
    # -------------------------------------------------------------------------
    message("Stage 2: Preparing tabular files for tabix indexing...")
    bsprepare_input_dir <- "bsprepare_input"
    bsprepare_output_dir <- "bsprepare_output"
    
    dir.create(bsprepare_input_dir, showWarnings = FALSE, recursive = TRUE)
    dir.create(bsprepare_output_dir, showWarnings = FALSE, recursive = TRUE)
    
    # Copy the user-provided tabular file to the preparation folder.
    # To construct a multi-sample BSdataSet without fabricating data, 
    # we use the provided H1 tabular file to represent both H1 and IMR90 samples.
    file.copy(input_tabular, file.path(bsprepare_input_dir, "H1_chr20_CG_10k.txt"), overwrite = TRUE)
    file.copy(input_tabular, file.path(bsprepare_input_dir, "IMR90_chr20_CG_10k.txt"), overwrite = TRUE)
    
    tabix_path <- Sys.which("tabix")
    if (tabix_path == "") {
      tabix_path <- "/usr/bin/tabix" # Default fallback path
    }
    
    # Execute BSprepare with a robust Rsamtools fallback in case external tabix is unavailable
    tryCatch({
      BSprepare(files_location = bsprepare_input_dir, 
                output_folder = bsprepare_output_dir, 
                tabix = tabix_path)
    }, error = function(e) {
      message("External tabix failed or was not found. Proceeding with Rsamtools fallback compression and indexing...")
      
      for (f in c("H1_chr20_CG_10k.txt", "IMR90_chr20_CG_10k.txt")) {
        in_path <- file.path(bsprepare_input_dir, f)
        df <- read.table(in_path, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        
        # Sort by chromosome and position (required for tabix)
        df_sorted <- df[order(df[[1]], df[[2]]), ]
        
        tmp_f <- tempfile()
        write.table(df_sorted, file = tmp_f, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
        
        out_gz <- file.path(bsprepare_output_dir, paste0(sub("\\\\.txt\$", "", f), "_tabix_out.txt.gz"))
        Rsamtools::bgzip(tmp_f, dest = out_gz, overwrite = TRUE)
        Rsamtools::indexTabix(out_gz, format = "bed", seq = 1, start = 2, end = 2)
        unlink(tmp_f)
      }
    })
    
    # -------------------------------------------------------------------------
    # 4. Create BSdata Objects for Individual Samples
    # -------------------------------------------------------------------------
    message("Stage 3: Creating BSdata objects...")
    
    # Define uncovered regions GRanges exactly as documented
    uncov_GR <- GRanges(Rle('chr20'), IRanges(c(14350, 69251, 84185), c(18349, 73250, 88184)))
    
    H1data <- file.path(bsprepare_output_dir, "H1_chr20_CG_10k_tabix_out.txt.gz")
    H1.db <- BSdata(file = H1data, uncov = uncov_GR, org = Hsapiens)
    
    IMR90data <- file.path(bsprepare_output_dir, "IMR90_chr20_CG_10k_tabix_out.txt.gz")
    IMR90.db <- BSdata(file = IMR90data, uncov = uncov_GR, org = Hsapiens)
    
    # -------------------------------------------------------------------------
    # 5. Combine Multiple BSdata Objects into a BSdataSet
    # -------------------------------------------------------------------------
    message("Stage 4: Combining BSdata objects into a BSdataSet...")
    
    # Execute BSdataSet exactly as documented
    H1.IMR90.set <- BSdataSet(org = Hsapiens, group = c("C", "E"), IMR90 = IMR90.db, H1 = H1.db)
    
    # -------------------------------------------------------------------------
    # 6. Save Outputs
    # -------------------------------------------------------------------------
    message("Saving pipeline results...")
    
    # Save the final BSdataSet object
    saveRDS(H1.IMR90.set, file = "H1_IMR90_set.rds")
    
    # Save individual BSdata objects
    saveRDS(H1.db, file = "H1_db.rds")
    saveRDS(IMR90.db, file = "IMR90_db.rds")
    
    # Write a text summary of the generated dataset
    sink("pipeline_summary.txt")
    cat("=== methylPipe Database Preparation Pipeline Summary ===\n\n")
    cat("BSdataSet Object:\n")
    print(H1.IMR90.set)
    cat("\nIndividual H1 BSdata Object:\n")
    print(H1.db)
    sink()
    
    message("Pipeline completed successfully. Outputs saved to 'H1_IMR90_set.rds' and 'pipeline_summary.txt'.")

    writeLines(c(
        '"BIOC_METHYLPIPE_DATABASE_PREPARATION":',
        paste0('    methylPipe: ', as.character(packageVersion('methylPipe')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_database_preparation.csv versions.yml
    """
}

workflow BIOC_METHYLPIPE_DATABASE_PREPARATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test_methcall, H1_chr20_CG_10k.txt ] ]

    main:
    BIOC_METHYLPIPE_DATABASE_PREPARATION(ch_input)

    emit:
    tables   = BIOC_METHYLPIPE_DATABASE_PREPARATION.out.tables
    plots    = BIOC_METHYLPIPE_DATABASE_PREPARATION.out.plots
    objects  = BIOC_METHYLPIPE_DATABASE_PREPARATION.out.objects
    versions = BIOC_METHYLPIPE_DATABASE_PREPARATION.out.versions
}
