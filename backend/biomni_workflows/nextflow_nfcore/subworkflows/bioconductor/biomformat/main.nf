#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biomformat — biomformat_metagenomics_pipeline
// Build a complete metagenomics utility pipeline to construct, serialize, and analyze BIOM objects from abundance and metadata tables, with downstream SummarizedE
// Input: abundance.csv, coldata.csv
// Container: 1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, biomformat, rhdf5
// Visualizations: bar plot, box plot, diversity plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOMFORMAT_BIOMFORMAT_METAGENOMICS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
    library(biomformat)
    
    # ==========================================
    # STAGE 1: Load and Preprocess Input Data
    # ==========================================
    
    # Read abundance matrix (taxon/OTU-by-sample)
    abundance_df <- read.csv("abundance.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!"taxon_id" %in% colnames(abundance_df)) {
      stop("abundance.csv must contain a 'taxon_id' column representing row names.")
    }
    
    # Set taxon_id as row names and convert the rest to a numeric matrix
    rownames(abundance_df) <- abundance_df\$taxon_id
    abundance_matrix <- as.matrix(abundance_df[, setdiff(names(abundance_df), "taxon_id"), drop = FALSE])
    
    # Read sample metadata
    coldata_df <- read.csv("coldata.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!"sample" %in% colnames(coldata_df)) {
      stop("coldata.csv must contain a 'sample' column.")
    }
    rownames(coldata_df) <- coldata_df\$sample
    
    # Align sample metadata with abundance matrix columns
    common_samples <- intersect(colnames(abundance_matrix), rownames(coldata_df))
    if (length(common_samples) == 0) {
      stop("No overlapping samples found between abundance.csv and coldata.csv.")
    }
    abundance_matrix <- abundance_matrix[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # Parse taxon IDs to construct a hierarchical taxonomy table if delimiters exist
    tax_list <- lapply(rownames(abundance_matrix), function(taxon) {
      parts <- unlist(strsplit(taxon, "[;|]"))
      if (length(parts) == 0 || identical(parts, "")) {
        return("Unknown")
      }
      trimws(parts)
    })
    tax_df <- data.frame(
      taxonomy = I(tax_list),
      row.names = rownames(abundance_matrix)
    )
    
    # ==========================================
    # STAGE 2: Construct and Serialize BIOM Object
    # ==========================================
    
    # Build the BIOM object
    biom_obj <- make_biom(
      data = abundance_matrix,
      sample_metadata = coldata_df,
      observation_metadata = tax_df,
      matrix_element_type = "int"
    )
    
    # Write to JSON BIOM (v1) format
    write_biom(biom_obj, "output_v1.biom")
    
    # Optionally write to HDF5 BIOM (v2) format if rhdf5 is available
    if (requireNamespace("rhdf5", quietly = TRUE)) {
      tryCatch({
        write_hdf5_biom(biom_obj, "output_v2.biom")
      }, error = function(e) {
        warning("Failed to write HDF5 BIOM file: ", e\$message)
      })
    }
    
    # ==========================================
    # STAGE 3: SummarizedExperiment Interoperability
    # ==========================================
    
    # Convert BIOM object to SummarizedExperiment
    se <- biom_to_SummarizedExperiment(biom_obj)
    
    # Perform basic QC: Calculate library sizes (total counts per sample)
    colData(se)\$LibrarySize <- colSums(assay(se, "counts"))
    
    # Export enriched sample metadata
    write.csv(as.data.frame(colData(se)), "sample_metadata_enriched.csv", row.names = TRUE)
    
    # ==========================================
    # STAGE 4: Tidy Data Transformation & Diversity Analysis
    # ==========================================
    
    # Convert BIOM object to tidy long-format data frame
    long_df <- as.data.frame(biom_obj)
    write.csv(long_df, "tidy_abundance.csv", row.names = FALSE)
    
    # Calculate Shannon diversity index per sample using base R
    shannon_div <- tapply(long_df\$count, long_df\$sample_id, function(counts) {
      p <- counts / sum(counts)
      p <- p[p > 0]
      if (length(p) == 0) return(0)
      -sum(p * log(p))
    })
    
    # Merge diversity metrics with sample metadata
    diversity_df <- data.frame(
      sample = names(shannon_div),
      shannon = as.vector(shannon_div),
      stringsAsFactors = FALSE
    )
    diversity_df <- merge(diversity_df, coldata_df, by.x = "sample", by.y = "sample")
    write.csv(diversity_df, "shannon_diversity.csv", row.names = FALSE)
    
    # ==========================================
    # STAGE 5: Visualization
    # ==========================================
    
    # Generate diagnostic plots
    pdf("diversity_analysis.pdf", width = 7, height = 5)
    if ("group" %in% colnames(diversity_df) && length(unique(diversity_df\$group)) > 1) {
      boxplot(shannon ~ group, data = diversity_df,
              main = "Shannon Diversity by Group",
              xlab = "Group", ylab = "Shannon Index",
              col = "lightblue", las = 1)
    } else {
      barplot(shannon ~ sample, data = diversity_df,
              main = "Shannon Diversity per Sample",
              xlab = "Sample", ylab = "Shannon Index",
              col = "skyblue", las = 2)
    }
    dev.off()

    writeLines(c(
        '"BIOC_BIOMFORMAT_BIOMFORMAT_METAGENOMICS_PIPELINE":',
        paste0('    biomformat: ', as.character(packageVersion('biomformat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomformat_metagenomics_pipeline.csv versions.yml
    """
}

workflow BIOC_BIOMFORMAT_BIOMFORMAT_METAGENOMICS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIOMFORMAT_BIOMFORMAT_METAGENOMICS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_BIOMFORMAT_BIOMFORMAT_METAGENOMICS_PIPELINE.out.tables
    plots    = BIOC_BIOMFORMAT_BIOMFORMAT_METAGENOMICS_PIPELINE.out.plots
    objects  = BIOC_BIOMFORMAT_BIOMFORMAT_METAGENOMICS_PIPELINE.out.objects
    versions = BIOC_BIOMFORMAT_BIOMFORMAT_METAGENOMICS_PIPELINE.out.versions
}
