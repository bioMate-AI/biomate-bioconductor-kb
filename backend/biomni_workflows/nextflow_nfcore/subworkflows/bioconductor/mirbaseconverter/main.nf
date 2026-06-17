#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miRBaseConverter — mirna_annotation_conversion
// Perform comprehensive miRNA version detection, accession/name conversion, sequence retrieval, family classification, and precursor mapping for a miRNA expressio
// Input: counts.csv, coldata.csv
// Container: 1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: miRBaseConverter
// Visualizations: bar plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRBASECONVERTER_MIRNA_ANNOTATION_CONVERSION {
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
    .bm_deps <- c("miRBaseConverter")
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
    library(miRBaseConverter)
    
    # ==========================================
    # --- Load Input Data ---
    # ==========================================
    message("Loading input expression data...")
    counts <- read.csv("counts.csv", check.names = FALSE)
    
    # Handle case where 'gene_id' is a column or row names
    if ("gene_id" %in% colnames(counts)) {
        rownames(counts) <- counts\$gene_id
        counts\$gene_id <- NULL
    }
    mirna_identifiers <- rownames(counts)
    message(paste("Loaded", length(mirna_identifiers), "miRNA identifiers."))
    
    # ==========================================
    # --- Identify Identifier Type & Version ---
    # ==========================================
    message("Checking identifier types (Accessions vs Names)...")
    # Accessions typically start with MIMAT (mature) or MI (precursor)
    is_accession <- all(grepl("^(MIMAT|MI)[0-9]+", mirna_identifiers))
    
    if (!is_accession) {
        message("Identifiers detected as miRNA Names. Checking miRBase version...")
        # Check the most likely miRBase version of the input names
        version_info <- checkMiRNAVersion(mirna_identifiers, verbose = FALSE)
        message(paste("Recommended input miRBase version:", version_info))
        
        # Convert Names to Accessions using the detected version
        message("Converting miRNA Names to Accessions...")
        accession_df <- miRNA_NameToAccession(mirna_identifiers, version = version_info)
        colnames(accession_df) <- c("OriginalName", "Accession")
    } else {
        message("Identifiers detected as miRBase Accessions.")
        accession_df <- data.frame(
            OriginalName = mirna_identifiers,
            Accession = mirna_identifiers,
            stringsAsFactors = FALSE
        )
    }
    
    # ==========================================
    # --- Retrieve Comprehensive Annotations ---
    # ==========================================
    message("Retrieving target version (v22) names...")
    valid_accs <- accession_df\$Accession[!is.na(accession_df\$Accession) & accession_df\$Accession != ""]
    
    if (length(valid_accs) > 0) {
        # 1. Convert Accessions to Target Version Names
        v22_names_df <- miRNA_AccessionToName(valid_accs, targetVersion = "v22")
        
        # 2. Retrieve Sequences
        message("Retrieving miRNA sequences...")
        seq_df <- getMiRNASequence(valid_accs, targetVersion = "v22")
        
        # 3. Retrieve Family Information
        message("Retrieving miRNA family classifications...")
        family_df <- checkMiRNAFamily(valid_accs)
        
        # 4. Map Mature to Precursor
        message("Mapping mature miRNAs to precursors...")
        valid_names <- v22_names_df\$TargetName[!is.na(v22_names_df\$TargetName)]
        if (length(valid_names) > 0) {
            precursor_df <- miRNA_MatureToPrecursor(valid_names)
            colnames(precursor_df) <- c("TargetName", "Precursor")
        } else {
            precursor_df <- data.frame(TargetName = character(), Precursor = character(), stringsAsFactors = FALSE)
        }
    } else {
        v22_names_df <- data.frame(Accession = character(), TargetName = character(), stringsAsFactors = FALSE)
        seq_df <- data.frame(Accession = character(), miRNASequence_v22 = character(), stringsAsFactors = FALSE)
        family_df <- data.frame(Accession = character(), FamilyAccession = character(), Family = character(), stringsAsFactors = FALSE)
        precursor_df <- data.frame(TargetName = character(), Precursor = character(), stringsAsFactors = FALSE)
    }
    
    # ==========================================
    # --- Merge and Compile Annotations ---
    # ==========================================
    message("Compiling annotation database...")
    annot <- accession_df
    annot <- merge(annot, v22_names_df, by = "Accession", all.x = TRUE)
    annot <- merge(annot, seq_df, by = "Accession", all.x = TRUE)
    annot <- merge(annot, family_df[, c("Accession", "FamilyAccession", "Family")], by = "Accession", all.x = TRUE)
    annot <- merge(annot, precursor_df, by = "TargetName", all.x = TRUE)
    
    # Reorder columns for readability
    annot <- annot[, c("OriginalName", "Accession", "TargetName", "miRNASequence_v22", "FamilyAccession", "Family", "Precursor")]
    write.csv(annot, "mirna_annotations.csv", row.names = FALSE)
    
    # Merge annotations with expression counts
    annotated_counts <- merge(annot, counts, by.x = "OriginalName", by.y = "row.names", all.y = TRUE)
    write.csv(annotated_counts, "annotated_counts.csv", row.names = FALSE)
    
    # ==========================================
    # --- Retrieve History for Top Expressed miRNAs ---
    # ==========================================
    message("Retrieving historical version mappings for top expressed miRNAs...")
    mean_expr <- rowMeans(counts, na.rm = TRUE)
    top_mirnas <- names(sort(mean_expr, decreasing = TRUE))[1:min(5, length(mean_expr))]
    top_accs <- annot\$Accession[annot\$OriginalName %in% top_mirnas]
    top_accs <- top_accs[!is.na(top_accs) & top_accs != ""]
    
    history_list <- list()
    for (acc in top_accs) {
        tryCatch({
            hist_df <- getMiRNAHistory(acc)
            hist_df\$Accession <- acc
            history_list[[acc]] <- hist_df
        }, error = function(e) {
            message(paste("Could not retrieve history for accession:", acc))
        })
    }
    
    if (length(history_list) > 0) {
        history_all <- do.call(rbind, history_list)
        write.csv(history_all, "top_mirna_history.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(Message = "No history retrieved or available"), "top_mirna_history.csv", row.names = FALSE)
    }
    
    # ==========================================
    # --- Visualizations and Diagnostics ---
    # ==========================================
    message("Generating diagnostic plots...")
    
    # 1. Plot miRNA Family Distribution
    pdf("mirna_families_distribution.pdf", width = 8, height = 6)
    if ("Family" %in% colnames(annot) && any(!is.na(annot\$Family))) {
        family_counts <- table(annot\$Family, useNA = "no")
        if (length(family_counts) > 0) {
            family_counts <- sort(family_counts, decreasing = TRUE)
            top_families <- head(family_counts, 15)
            par(mar = c(10, 4, 4, 2))
            barplot(top_families, las = 2, col = "skyblue", 
                    main = "Top 15 Represented miRNA Families", 
                    ylab = "Number of miRNAs")
        } else {
            plot.new()
            text(0.5, 0.5, "No Family Information Available")
        }
    } else {
        plot.new()
        text(0.5, 0.5, "No Family Information Available")
    }
    dev.off()
    
    # 2. Plot Sequence Length Distribution
    pdf("mirna_sequence_lengths.pdf", width = 8, height = 6)
    if ("miRNASequence_v22" %in% colnames(annot)) {
        seq_lengths <- nchar(annot\$miRNASequence_v22)
        seq_lengths <- seq_lengths[!is.na(seq_lengths)]
        if (length(seq_lengths) > 0) {
            hist(seq_lengths, col = "lightgreen", 
                 main = "Distribution of miRNA Sequence Lengths (v22)",
                 xlab = "Sequence Length (bp)", ylab = "Frequency", breaks = 10)
        } else {
            plot.new()
            text(0.5, 0.5, "No Sequence Information Available")
        }
    } else {
        plot.new()
        text(0.5, 0.5, "No Sequence Information Available")
    }
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MIRBASECONVERTER_MIRNA_ANNOTATION_CONVERSION":',
        paste0('    miRBaseConverter: ', as.character(packageVersion('miRBaseConverter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_annotation_conversion.csv versions.yml
    """
}

workflow BIOC_MIRBASECONVERTER_MIRNA_ANNOTATION_CONVERSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MIRBASECONVERTER_MIRNA_ANNOTATION_CONVERSION(ch_input)

    emit:
    tables   = BIOC_MIRBASECONVERTER_MIRNA_ANNOTATION_CONVERSION.out.tables
    plots    = BIOC_MIRBASECONVERTER_MIRNA_ANNOTATION_CONVERSION.out.plots
    objects  = BIOC_MIRBASECONVERTER_MIRNA_ANNOTATION_CONVERSION.out.objects
    versions = BIOC_MIRBASECONVERTER_MIRNA_ANNOTATION_CONVERSION.out.versions
}
