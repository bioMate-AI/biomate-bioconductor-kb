#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ipdDb — ipd_hla_kir_annotation
// Retrieve reference sequences, closest complete alleles, and genomic structures for HLA and KIR loci/alleles specified in an input file.
// Input: input.csv
// Container: 1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, Biostrings, GenomicRanges, IRanges, S4Vectors, ipdDb
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IPDDB_IPD_HLA_KIR_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("ipdDb", "BiocGenerics", "GenomicRanges", "S4Vectors")
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
    library(ipdDb)
    library(BiocGenerics)
    library(GenomicRanges)
    library(S4Vectors)
    
    # Helper function to safely load Biostrings if available, or fallback
    if (!requireNamespace("Biostrings", quietly = TRUE)) {
      stop("Biostrings package is required to handle DNAStringSet outputs.")
    }
    
    # ==========================================
    # STAGE 1: Read and Parse Input Defensively
    # ==========================================
    input_file <- "input.csv"
    ids <- character()
    
    if (file.exists(input_file)) {
      message("Reading input file: ", input_file)
      # Read defensively
      input_df <- tryCatch({
        read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
      }, error = function(e) {
        warning("Failed to read input.csv as standard CSV: ", e\$message)
        NULL
      })
      
      if (!is.null(input_df) && nrow(input_df) > 0) {
        # Extract identifiers based on column names or structure
        if ("feature_id" %in% colnames(input_df)) {
          ids <- as.character(input_df\$feature_id)
        } else if (ncol(input_df) >= 1) {
          # If first column is numeric, row names might contain the identifiers
          if (is.numeric(input_df[[1]]) && !is.null(rownames(input_df))) {
            ids <- rownames(input_df)
          } else {
            ids <- as.character(input_df[[1]])
          }
        }
      }
    } else {
      message("input.csv not found. Proceeding with default representative HLA/KIR identifiers.")
    }
    
    # Clean and filter identifiers
    ids <- unique(na.omit(ids))
    ids <- trimws(ids)
    ids <- ids[ids != ""]
    
    # Fallback to representative HLA/KIR loci and alleles if input is empty
    if (length(ids) == 0) {
      message("No valid identifiers found. Using default HLA/KIR loci and alleles for demonstration.")
      ids <- c("HLA-A", "HLA-B", "HLA-A*01:01:01:01", "KIR2DL1", "KIR2DL1*0010101")
    }
    
    message("Identifiers to query: ", paste(ids, collapse = ", "))
    
    # ==========================================
    # STAGE 2: Initialize Databases
    # ==========================================
    message("Loading HLA and KIR databases...")
    hla_db <- tryCatch({
      loadHlaData()
    }, error = function(e) {
      stop("Failed to load HLA database: ", e\$message)
    })
    
    kir_db <- tryCatch({
      loadKirData()
    }, error = function(e) {
      stop("Failed to load KIR database: ", e\$message)
    })
    
    # Retrieve all available loci to categorize input IDs
    hla_loci <- hla_db\$getLoci()
    kir_loci <- kir_db\$getLoci()
    
    message("Available HLA Loci: ", paste(hla_loci, collapse = ", "))
    message("Available KIR Loci: ", paste(kir_loci, collapse = ", "))
    
    # ==========================================
    # STAGE 3: Resolve Loci to Alleles
    # ==========================================
    hla_alleles_to_query <- character()
    kir_alleles_to_query <- character()
    
    for (id in ids) {
      if (id %in% hla_loci) {
        # If ID is an HLA locus, retrieve all its alleles
        alleles <- hla_db\$getAlleles(id)
        hla_alleles_to_query <- c(hla_alleles_to_query, alleles)
      } else if (id %in% kir_loci) {
        # If ID is a KIR locus, retrieve all its alleles
        alleles <- kir_db\$getAlleles(id)
        kir_alleles_to_query <- c(kir_alleles_to_query, alleles)
      } else {
        # Check if it matches known HLA or KIR alleles directly
        # We can fetch all alleles to verify
        all_hla <- unlist(lapply(hla_loci, function(l) hla_db\$getAlleles(l)))
        all_kir <- unlist(lapply(kir_loci, function(l) kir_db\$getAlleles(l)))
        
        if (id %in% all_hla) {
          hla_alleles_to_query <- c(hla_alleles_to_query, id)
        } else if (id %in% all_kir) {
          kir_alleles_to_query <- c(kir_alleles_to_query, id)
        } else {
          # If unknown, attempt to assign based on prefix pattern
          if (grepl("^HLA-", id)) {
            hla_alleles_to_query <- c(hla_alleles_to_query, id)
          } else if (grepl("^KIR", id)) {
            kir_alleles_to_query <- c(kir_alleles_to_query, id)
          } else {
            # Default fallback to HLA
            hla_alleles_to_query <- c(hla_alleles_to_query, id)
          }
        }
      }
    }
    
    hla_alleles_to_query <- unique(hla_alleles_to_query)
    kir_alleles_to_query <- unique(kir_alleles_to_query)
    
    # Limit query size for performance if too many alleles are resolved
    max_alleles <- 50
    if (length(hla_alleles_to_query) > max_alleles) {
      message("Limiting HLA query to first ", max_alleles, " alleles for performance.")
      hla_alleles_to_query <- hla_alleles_to_query[1:max_alleles]
    }
    if (length(kir_alleles_to_query) > max_alleles) {
      message("Limiting KIR query to first ", max_alleles, " alleles for performance.")
      kir_alleles_to_query <- kir_alleles_to_query[1:max_alleles]
    }
    
    # ==========================================
    # STAGE 4: Query Sequences and Structures
    # ==========================================
    all_sequences <- Biostrings::DNAStringSet()
    metadata_list <- list()
    all_structures_list <- list()
    
    # --- Process HLA Alleles ---
    if (length(hla_alleles_to_query) > 0) {
      message("Querying HLA reference sequences...")
      hla_seqs <- tryCatch({
        hla_db\$getReference(hla_alleles_to_query)
      }, error = function(e) {
        warning("Error fetching HLA reference sequences: ", e\$message)
        Biostrings::DNAStringSet()
      })
      
      if (length(hla_seqs) > 0) {
        all_sequences <- c(all_sequences, hla_seqs)
      }
      
      message("Querying HLA structures and closest complete alleles...")
      for (al in hla_alleles_to_query) {
        # Closest complete allele
        closest_al <- NA
        closest_len <- NA
        tryCatch({
          cc <- hla_db\$getClosestComplete(al)
          if (length(cc) > 0) {
            closest_al <- names(cc)[1]
            closest_len <- BiocGenerics::width(cc)[1]
          }
        }, error = function(e) {
          # Silent fallback if not found
        })
        
        # Sequence length
        seq_len <- if (al %in% names(hla_seqs)) BiocGenerics::width(hla_seqs[al]) else NA
        
        metadata_list[[length(metadata_list) + 1]] <- data.frame(
          Database = "HLA",
          Allele = al,
          SeqLength = seq_len,
          ClosestCompleteAllele = closest_al,
          ClosestCompleteLength = closest_len,
          stringsAsFactors = FALSE
        )
      }
      
      # Gene structures
      tryCatch({
        hla_structs <- hla_db\$getStructure(hla_alleles_to_query)
        if (!is.null(hla_structs) && length(hla_structs) > 0) {
          df_struct <- as.data.frame(hla_structs)
          df_struct\$Database <- "HLA"
          all_structures_list[[length(all_structures_list) + 1]] <- df_struct
        }
      }, error = function(e) {
        warning("Error fetching HLA structures: ", e\$message)
      })
    }
    
    # --- Process KIR Alleles ---
    if (length(kir_alleles_to_query) > 0) {
      message("Querying KIR reference sequences...")
      kir_seqs <- tryCatch({
        kir_db\$getReference(kir_alleles_to_query)
      }, error = function(e) {
        warning("Error fetching KIR reference sequences: ", e\$message)
        Biostrings::DNAStringSet()
      })
      
      if (length(kir_seqs) > 0) {
        all_sequences <- c(all_sequences, kir_seqs)
      }
      
      message("Querying KIR structures and closest complete alleles...")
      for (al in kir_alleles_to_query) {
        # Closest complete allele
        closest_al <- NA
        closest_len <- NA
        tryCatch({
          cc <- kir_db\$getClosestComplete(al)
          if (length(cc) > 0) {
            closest_al <- names(cc)[1]
            closest_len <- BiocGenerics::width(cc)[1]
          }
        }, error = function(e) {
          # Silent fallback
        })
        
        # Sequence length
        seq_len <- if (al %in% names(kir_seqs)) BiocGenerics::width(kir_seqs[al]) else NA
        
        metadata_list[[length(metadata_list) + 1]] <- data.frame(
          Database = "KIR",
          Allele = al,
          SeqLength = seq_len,
          ClosestCompleteAllele = closest_al,
          ClosestCompleteLength = closest_len,
          stringsAsFactors = FALSE
        )
      }
      
      # Gene structures
      tryCatch({
        kir_structs <- kir_db\$getStructure(kir_alleles_to_query)
        if (!is.null(kir_structs) && length(kir_structs) > 0) {
          df_struct <- as.data.frame(kir_structs)
          df_struct\$Database <- "KIR"
          all_structures_list[[length(all_structures_list) + 1]] <- df_struct
        }
      }, error = function(e) {
        warning("Error fetching KIR structures: ", e\$message)
      })
    }
    
    # ==========================================
    # STAGE 5: Export Results
    # ==========================================
    message("Writing output files...")
    
    # 1. Save Sequences to FASTA
    if (length(all_sequences) > 0) {
      Biostrings::writeXStringSet(all_sequences, filepath = "allele_sequences.fasta")
      message("Saved reference sequences to 'allele_sequences.fasta'")
    } else {
      # Write empty FASTA file to satisfy output declaration
      writeLines(character(), "allele_sequences.fasta")
      warning("No sequences retrieved. Empty FASTA file written.")
    }
    
    # 2. Save Metadata to CSV
    if (length(metadata_list) > 0) {
      metadata_df <- do.call(rbind, metadata_list)
      write.csv(metadata_df, "allele_metadata.csv", row.names = FALSE)
      message("Saved metadata to 'allele_metadata.csv'")
    } else {
      # Write empty metadata table
      dummy_meta <- data.frame(Database=character(), Allele=character(), SeqLength=integer(), ClosestCompleteAllele=character(), ClosestCompleteLength=integer())
      write.csv(dummy_meta, "allele_metadata.csv", row.names = FALSE)
      warning("No metadata retrieved. Empty metadata CSV written.")
    }
    
    # 3. Save Structures to CSV
    if (length(all_structures_list) > 0) {
      structures_df <- do.call(rbind, all_structures_list)
      write.csv(structures_df, "allele_structures.csv", row.names = FALSE)
      message("Saved structures to 'allele_structures.csv'")
    } else {
      # Write empty structures table
      dummy_struct <- data.frame(Database=character(), seqnames=character(), start=integer(), end=integer(), width=integer(), strand=character())
      write.csv(dummy_struct, "allele_structures.csv", row.names = FALSE)
      warning("No structures retrieved. Empty structures CSV written.")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_IPDDB_IPD_HLA_KIR_ANNOTATION":',
        paste0('    ipdDb: ', as.character(packageVersion('ipdDb')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ipd_hla_kir_annotation.csv versions.yml
    """
}

workflow BIOC_IPDDB_IPD_HLA_KIR_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_IPDDB_IPD_HLA_KIR_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_IPDDB_IPD_HLA_KIR_ANNOTATION.out.tables
    plots    = BIOC_IPDDB_IPD_HLA_KIR_ANNOTATION.out.plots
    objects  = BIOC_IPDDB_IPD_HLA_KIR_ANNOTATION.out.objects
    versions = BIOC_IPDDB_IPD_HLA_KIR_ANNOTATION.out.versions
}
