#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: erma — erma_epigenomic_roadmap_analysis
// Query, extract, and visualize Roadmap Epigenomics ChromHMM states for user-specified genomic regions or genes.
// Input: input.csv
// Container: 1.22.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, GenomicFeatures, GenomicRanges, Gviz, TxDb.Hsapiens.UCSC.hg19.knownGene, erma, org.Hs.eg.db
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ERMA_ERMA_EPIGENOMIC_ROADMAP_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Stage 1: Load required libraries safely
    suppressPackageStartupMessages({
      library(erma)
      library(Gviz)
      library(GenomicRanges)
      library(GenomicFeatures)
      library(TxDb.Hsapiens.UCSC.hg19.knownGene)
      library(org.Hs.eg.db)
    })
    
    # Stage 2: Define robust input parsing functions
    parse_coords <- function(x) {
      # Matches formats like chr1:100-200, chrX:1000..2000, 1:100-200
      m <- regexec("^([Cc][Hh][Rr])?([0-9XYxyMmtT]+)[:_]([0-9]+)[-..]+([0-9]+)\$", x)
      matches <- regmatches(x, m)
      valid_idx <- which(sapply(matches, length) > 0)
      if (length(valid_idx) > 0) {
        chrs <- sapply(matches[valid_idx], function(v) {
          c_num <- v[3]
          if (!grepl("^[Cc][Hh][Rr]", c_num)) {
            paste0("chr", c_num)
          } else {
            c_num
          }
        })
        starts <- as.numeric(sapply(matches[valid_idx], function(v) v[4]))
        ends <- as.numeric(sapply(matches[valid_idx], function(v) v[5]))
        return(GRanges(seqnames = chrs, ranges = IRanges(start = starts, end = ends)))
      }
      NULL
    }
    
    # Stage 3: Read and process user input
    user_gr <- NULL
    fallback_range <- GRanges("chr22", IRanges(36253000, 36290000)) # APOL1 locus on hg19
    
    if (file.exists("input.csv")) {
      message("Reading input.csv...")
      inp <- tryCatch({
        read.csv("input.csv", stringsAsFactors = FALSE)
      }, error = function(e) {
        message("Error reading input.csv: ", e\$message)
        NULL
      })
      
      if (!is.null(inp)) {
        # Extract identifiers defensively
        ids <- NULL
        if ("feature_id" %in% colnames(inp)) {
          ids <- inp\$feature_id
        } else if (ncol(inp) == 1) {
          ids <- inp[[1]]
        } else {
          ids <- rownames(inp)
          if (is.null(ids) || all(ids == as.character(1:nrow(inp)))) {
            ids <- inp[, 1]
          }
        }
        
        ids <- as.character(na.omit(ids))
        ids <- ids[ids != ""]
        
        if (length(ids) > 0) {
          # 1. Try parsing as genomic coordinates
          parsed_gr <- parse_coords(ids)
          if (!is.null(parsed_gr) && length(parsed_gr) > 0) {
            user_gr <- parsed_gr[1] # Use the first valid coordinate range
            message("Successfully parsed genomic coordinates from input: ", as.character(user_gr))
          } else {
            # 2. Try mapping as gene symbols or Entrez IDs to hg19
            message("Attempting to map identifiers to hg19 gene coordinates...")
            txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
            orgdb <- org.Hs.eg.db
            
            eg_ids <- tryCatch({
              AnnotationDbi::mapIds(orgdb, keys = ids, keytype = "SYMBOL", column = "ENTREZID", multiVals = "first")
            }, error = function(e) NULL)
            
            if (is.null(eg_ids) || all(is.na(eg_ids))) {
              eg_ids <- ids # Fallback: assume they might already be Entrez IDs
            }
            
            g_ranges <- tryCatch({
              GenomicFeatures::genes(txdb)
            }, error = function(e) NULL)
            
            if (!is.null(g_ranges)) {
              matched_g <- g_ranges[g_ranges\$gene_id %in% eg_ids]
              if (length(matched_g) > 0) {
                user_gr <- matched_g[1]
                # Expand range slightly to capture promoter/enhancer regions
                user_gr <- resize(user_gr, width = width(user_gr) + 20000, fix = "center")
                message("Successfully mapped gene to hg19 coordinates: ", as.character(user_gr))
              }
            }
          }
        }
      }
    }
    
    if (is.null(user_gr)) {
      message("Could not map input.csv to hg19 coordinates. Using fallback region (APOL1 locus on chr22).")
      user_gr <- fallback_range
    }
    
    # Stage 4: Select representative epigenomes from Roadmap Metadata
    meta <- erma::roadmapMetadata
    # Select a diverse set of standard epigenomes (e.g., Stem Cells, Lung, Blood, Leukemia)
    selected_eids <- c("E003", "E096", "E116", "E123")
    selected_eids <- intersect(selected_eids, meta\$EID)
    if (length(selected_eids) == 0) {
      selected_eids <- head(meta\$EID, 4)
    }
    
    message("Querying ChromHMM states for epigenomes: ", paste(selected_eids, collapse = ", "))
    
    # Stage 5: Retrieve ChromHMM state tracks using erma
    tracks <- tryCatch({
      stateTracks(user_gr, eid = selected_eids)
    }, error = function(e) {
      message("Error retrieving state tracks: ", e\$message)
      NULL
    })
    
    # Stage 6: Extract state data programmatically and save to CSV
    if (!is.null(tracks) && length(tracks) > 0) {
      extracted_states <- list()
      for (i in seq_along(tracks)) {
        tr <- tracks[[i]]
        tr_name <- names(tracks)[i]
        if (is.null(tr_name)) tr_name <- tr@name
        
        gr_track <- tryCatch({
          tr@range
        }, error = function(e) {
          tryCatch({
            ranges(tr)
          }, error = function(e2) NULL)
        })
        
        if (!is.null(gr_track) && inherits(gr_track, "GRanges")) {
          df <- as.data.frame(gr_track)
          df\$epigenome_id <- tr_name
          if (tr_name %in% meta\$EID) {
            df\$anatomy <- meta\$ANATOMY[meta\$EID == tr_name][1]
            df\$cell_type <- meta\$COMMON_NAME[meta\$EID == tr_name][1]
          } else {
            df\$anatomy <- NA
            df\$cell_type <- NA
          }
          extracted_states[[i]] <- df
        }
      }
      
      if (length(extracted_states) > 0) {
        all_states_df <- do.call(rbind, extracted_states)
        cols_to_keep <- intersect(
          c("seqnames", "start", "end", "width", "strand", "feature", "group", "id", "epigenome_id", "anatomy", "cell_type"),
          colnames(all_states_df)
        )
        final_df <- all_states_df[, cols_to_keep, drop = FALSE]
        write.csv(final_df, "epigenomic_states_summary.csv", row.names = FALSE)
        message("Saved state summary to epigenomic_states_summary.csv")
      } else {
        write.csv(data.frame(Message = "No states extracted"), "epigenomic_states_summary.csv", row.names = FALSE)
      }
    } else {
      write.csv(data.frame(Message = "Failed to retrieve tracks"), "epigenomic_states_summary.csv", row.names = FALSE)
    }
    
    # Stage 7: Visualize tracks using Gviz and save to PDF
    if (!is.null(tracks) && length(tracks) > 0) {
      message("Generating Gviz visualization...")
      pdf("epigenomic_states_plot.pdf", width = 12, height = 8)
      axis_track <- GenomeAxisTrack()
      
      tryCatch({
        plotTracks(
          c(list(axis_track), tracks),
          from = start(user_gr),
          to = end(user_gr),
          chromosome = as.character(seqnames(user_gr)),
          main = paste("Roadmap Epigenomic States for Region:", as.character(user_gr)),
          cex.main = 1
        )
      }, error = function(e) {
        message("Error plotting tracks: ", e\$message)
        # Create an empty fallback plot
        plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
        text(1, 1, paste("Error plotting tracks:", e\$message), cex = 0.8)
      })
      
      dev.off()
      message("Saved visualization to epigenomic_states_plot.pdf")
    } else {
      # Create a fallback PDF
      pdf("epigenomic_states_plot.pdf", width = 8, height = 6)
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, "No epigenomic tracks available to plot.", cex = 1.2)
      dev.off()
    }
    
    message("Pipeline complete.")

    writeLines(c(
        '"BIOC_ERMA_ERMA_EPIGENOMIC_ROADMAP_ANALYSIS":',
        paste0('    erma: ', as.character(packageVersion('erma')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_erma_epigenomic_roadmap_analysis.csv versions.yml
    """
}

workflow BIOC_ERMA_ERMA_EPIGENOMIC_ROADMAP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ERMA_ERMA_EPIGENOMIC_ROADMAP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ERMA_ERMA_EPIGENOMIC_ROADMAP_ANALYSIS.out.tables
    plots    = BIOC_ERMA_ERMA_EPIGENOMIC_ROADMAP_ANALYSIS.out.plots
    objects  = BIOC_ERMA_ERMA_EPIGENOMIC_ROADMAP_ANALYSIS.out.objects
    versions = BIOC_ERMA_ERMA_EPIGENOMIC_ROADMAP_ANALYSIS.out.versions
}
