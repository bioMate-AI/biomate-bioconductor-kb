#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BgeeDB — reference_tissue_correlation
// Correlates user-supplied gene expression profiles with Bgee reference tissue expression profiles to identify tissue similarity or sample origin.
// Input: counts.csv, coldata.csv
// Container: 2.38.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BgeeDB, Biobase
// Visualizations: image plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BGEEDB_REFERENCE_TISSUE_CORRELATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(BgeeDB)
    library(Biobase)
    
    # Stage 1: Read input data
    message("Reading input files...")
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Stage 2: Determine species and initialize Bgee
    all_genes <- rownames(counts)
    species <- "Homo_sapiens"
    if (any(grepl("^ENSMUSG", all_genes))) {
      species <- "Mus_musculus"
    } else if (any(grepl("^ENSDARG", all_genes))) {
      species <- "Danio_rerio"
    }
    message(paste("Detected species:", species))
    
    bgee <- Bgee\$new(species = species, dataType = "rna_seq")
    
    # Stage 3: Retrieve reference dataset metadata and select a representative experiment
    message("Retrieving Bgee annotations...")
    ann <- getAnnotation(bgee)
    exp_ann <- ann\$experiment.annotation
    
    # Sort experiments by library count to find a well-characterized reference experiment
    exp_ann <- exp_ann[order(exp_ann\$Library.count, decreasing = TRUE), ]
    selected_exp_id <- exp_ann\$Experiment.ID[1]
    message(paste("Selected reference experiment:", selected_exp_id))
    
    # Stage 4: Download and format reference expression data
    message("Downloading reference processed data...")
    ref_data <- getSampleProcessedData(bgee, experimentId = selected_exp_id)
    ref_eset <- formatData(bgee, ref_data, callType = "present", stats = "tpm")
    
    ref_expr <- Biobase::exprs(ref_eset)
    ref_pheno <- Biobase::pData(ref_eset)
    
    # Stage 5: Normalize user counts and compute correlation
    message("Computing correlation matrix...")
    # Simple CPM normalization for user counts
    user_cpm <- apply(counts, 2, function(x) (x / sum(x)) * 1e6)
    
    # Find overlapping genes
    common_genes <- intersect(rownames(user_cpm), rownames(ref_expr))
    message(paste("Number of overlapping genes:", length(common_genes)))
    
    if (length(common_genes) > 10) {
      # Compute Spearman correlation
      cor_matrix <- cor(user_cpm[common_genes, ], ref_expr[common_genes, ], method = "spearman")
      
      # Map reference column names to descriptive anatomical entities and stages
      colnames(cor_matrix) <- paste0(ref_pheno\$Anatomical.entity.name, " (", ref_pheno\$Stage.name, ")")
      
      # Save correlation matrix
      write.csv(cor_matrix, "bgee_reference_correlation.csv")
      
      # Plot correlation heatmap
      pdf("bgee_reference_correlation_plot.pdf", width = 10, height = 8)
      par(mar = c(12, 10, 4, 2))
      image(1:nrow(cor_matrix), 1:ncol(cor_matrix), cor_matrix,
            xaxt = "n", yaxt = "n", xlab = "", ylab = "",
            col = heat.colors(100), main = "Correlation with Bgee Reference Tissues")
      axis(1, at = 1:nrow(cor_matrix), labels = rownames(cor_matrix), las = 2, cex.axis = 0.8)
      axis(2, at = 1:ncol(cor_matrix), labels = colnames(cor_matrix), las = 2, cex.axis = 0.6)
      dev.off()
    } else {
      warning("Too few overlapping genes to compute reliable correlation.")
      # Write fallback empty outputs
      write.csv(data.frame(Error = "Insufficient overlapping genes"), "bgee_reference_correlation.csv")
      pdf("bgee_reference_correlation_plot.pdf")
      plot.new()
      text(0.5, 0.5, "Insufficient overlapping genes to compute correlation")
      dev.off()
    }
    
    message("Workflow complete.")

    writeLines(c(
        '"BIOC_BGEEDB_REFERENCE_TISSUE_CORRELATION":',
        paste0('    BgeeDB: ', as.character(packageVersion('BgeeDB')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_tissue_correlation.csv versions.yml
    """
}

workflow BIOC_BGEEDB_REFERENCE_TISSUE_CORRELATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BGEEDB_REFERENCE_TISSUE_CORRELATION(ch_input)

    emit:
    tables   = BIOC_BGEEDB_REFERENCE_TISSUE_CORRELATION.out.tables
    plots    = BIOC_BGEEDB_REFERENCE_TISSUE_CORRELATION.out.plots
    objects  = BIOC_BGEEDB_REFERENCE_TISSUE_CORRELATION.out.objects
    versions = BIOC_BGEEDB_REFERENCE_TISSUE_CORRELATION.out.versions
}
