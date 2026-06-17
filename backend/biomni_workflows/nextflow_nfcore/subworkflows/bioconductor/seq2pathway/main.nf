#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seq2pathway — chip_seq_region_pathway
// Map genomic regions (such as ChIP-seq peaks) to genes and perform quantitative pathway enrichment analysis.
// Input: Chipseq_Peak_demo, MsigDB_C5, dat_chip
// Container: quay.io/biocontainers/bioconductor-seq2pathway:1.34.0--r43hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: seq2pathway
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Load User Inputs
//  * 2. [Core Analysis] Map genomic regions to genes using runseq2gene
//  * 3. [Core Analysis] Run pathway enrichment analysis using gene2pathway_test
//  * 4. [Core Analysis] Add detailed gene descriptions using addDescription

nextflow.enable.dsl = 2

process BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("seq2pathway")
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
    library(seq2pathway)
    
    # Helper function to robustly load user input files from the working directory
    load_input <- function(filename) {
      # Check various extensions in case the user saved them in different formats
      extensions <- c("", ".rds", ".RDS", ".csv", ".CSV", ".txt", ".TXT", ".RData", ".rdata", ".rda")
      
      for (ext in extensions) {
        full_path <- paste0(filename, ext)
        if (file.exists(full_path)) {
          if (grepl("\\\\.(rds|RDS)\$", full_path) || (ext == "" && grepl("\\\\.rds\$", full_path, ignore.case = TRUE))) {
            return(readRDS(full_path))
          } else if (grepl("\\\\.(csv|CSV)\$", full_path)) {
            return(read.csv(full_path, stringsAsFactors = FALSE))
          } else if (grepl("\\\\.(txt|TXT)\$", full_path)) {
            return(read.table(full_path, header = TRUE, stringsAsFactors = FALSE))
          } else if (grepl("\\\\.(RData|rdata|rda)\$", full_path)) {
            env <- new.env()
            load(full_path, envir = env)
            vars <- ls(env)
            if (length(vars) > 0) {
              return(get(vars[1], envir = env))
            }
          } else {
            # Default fallback to readRDS if no extension matches but file exists
            tryCatch({
              return(readRDS(full_path))
            }, error = function(e) {
              tryCatch({
                return(read.csv(full_path, stringsAsFactors = FALSE))
              }, error = function(e2) {
                stop(paste("Failed to read file:", full_path))
              })
            })
          }
        }
      }
      stop(paste("Required input file not found in working directory:", filename))
    }
    
    # ----------------------------------------------------------------------
    # --- Load User Inputs ---
    # ----------------------------------------------------------------------
    message("Loading user input files...")
    Chipseq_Peak_demo <- load_input("Chipseq_Peak_demo")
    MsigDB_C5         <- load_input("MsigDB_C5")
    dat_chip          <- load_input("dat_chip")
    
    # ----------------------------------------------------------------------
    # --- Map genomic regions to genes using runseq2gene ---
    # ----------------------------------------------------------------------
    message("Mapping genomic regions to genes...")
    Chipseq_anno <- runseq2gene(
                      inputfile=Chipseq_Peak_demo, 
                      genome="hg19", adjacent=FALSE, SNP=FALSE, search_radius=1000, 
                      PromoterStop=FALSE,NearestTwoDirection=TRUE)
    
    # Save Step 1 Outputs
    message("Saving genomic region annotation results...")
    saveRDS(Chipseq_anno, "Chipseq_anno.rds")
    if (is.list(Chipseq_anno) && length(Chipseq_anno) > 0) {
      write.csv(Chipseq_anno[[1]], "Chipseq_anno_table.csv", row.names = FALSE)
    }
    
    # ----------------------------------------------------------------------
    # --- Run pathway enrichment analysis using gene2pathway_test ---
    # ----------------------------------------------------------------------
    message("Running pathway enrichment analysis (FAIME & Fisher's Exact Test)...")
    result_FAIME <- gene2pathway_test(dat= dat_chip, DataBase= MsigDB_C5,
                    FisherTest=TRUE, EmpiricalTest=FALSE, method="FAIME",
                    alpha=5, logCheck=FALSE, na.rm=FALSE)
    
    # Save Step 2 Outputs
    message("Saving pathway enrichment results...")
    saveRDS(result_FAIME, "result_FAIME.rds")
    
    if (is.list(result_FAIME)) {
      for (name in names(result_FAIME)) {
        sub_res <- result_FAIME[[name]]
        if (is.data.frame(sub_res)) {
          write.csv(sub_res, paste0("result_FAIME_", name, ".csv"), row.names = TRUE)
        } else if (is.list(sub_res)) {
          for (sub_name in names(sub_res)) {
            if (is.data.frame(sub_res[[sub_name]])) {
              write.csv(sub_res[[sub_name]], paste0("result_FAIME_", name, "_", sub_name, ".csv"), row.names = TRUE)
            }
          }
        }
      }
    }
    
    # ----------------------------------------------------------------------
    # --- Add detailed gene descriptions using addDescription ---
    # ----------------------------------------------------------------------
    message("Adding detailed gene descriptions...")
    gene_description <- addDescription(genome="hg38", genevector=as.vector(rownames(dat_chip)))
    
    # Save Step 3 Outputs
    message("Saving gene description results...")
    saveRDS(gene_description, "gene_description.rds")
    write.csv(gene_description, "gene_description.csv", row.names = FALSE)
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY":',
        paste0('    seq2pathway: ', as.character(packageVersion('seq2pathway')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chip_seq_region_pathway.csv versions.yml
    """
}

workflow BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Chipseq_Peak_demo, MsigDB_C5, dat_chip ] ]

    main:
    BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY(ch_input)

    emit:
    tables   = BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY.out.tables
    plots    = BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY.out.plots
    objects  = BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY.out.objects
    versions = BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY.out.versions
}
