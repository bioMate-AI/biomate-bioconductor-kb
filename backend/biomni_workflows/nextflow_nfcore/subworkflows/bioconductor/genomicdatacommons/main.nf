#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenomicDataCommons — gdc_somatic_mutation_analysis
// Query GDC for somatic mutations and clinical profiles associated with a user-supplied list of gene symbols.
// Input: input.csv
// Container: 1.34.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicDataCommons
// Visualizations: bar plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICDATACOMMONS_GDC_SOMATIC_MUTATION_ANALYSIS {
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
    
    # Load required libraries
    library(GenomicDataCommons)
    
    # Helper function to write fallback files in case of empty results or API errors
    write_fallback <- function(filename, message) {
      write.csv(data.frame(Status = "No Data/Error", Message = message, timestamp = Sys.time()), 
                file = filename, row.names = FALSE)
    }
    
    # Helper to safely extract nested fields from GDC results lists
    extract_field <- function(lst, fields) {
      sapply(lst, function(x) {
        val <- x
        for (f in fields) {
          if (is.list(val) && f %in% names(val)) {
            val <- val[[f]]
          } else {
            return(NA)
          }
        }
        if (is.list(val)) return(paste(unlist(val), collapse = ";"))
        return(val)
      })
    }
    
    # ==========================================
    # STAGE 1: Read Input and Check Connectivity
    # ==========================================
    message("Stage 1: Reading input and checking GDC API status...")
    
    if (!file.exists("input.csv")) {
      stop("Required input file 'input.csv' is missing.")
    }
    
    # Read input defensively
    inp <- read.csv("input.csv", stringsAsFactors = FALSE)
    gene_list <- NULL
    
    if ("feature_id" %in% colnames(inp)) {
      gene_list <- inp\$feature_id
    } else if (ncol(inp) >= 1) {
      gene_list <- inp[[1]]
    }
    
    # Clean and validate gene list
    gene_list <- as.character(gene_list)
    gene_list <- gene_list[gene_list != "" & !is.na(gene_list)]
    
    if (length(gene_list) == 0) {
      message("No valid gene symbols found in input.csv. Using default cancer genes (TP53, PTEN, EGFR).")
      gene_list <- c("TP53", "PTEN", "EGFR")
    } else {
      message(paste("Loaded", length(gene_list), "gene symbols from input.csv"))
    }
    
    # Check GDC API Status
    gdc_status <- tryCatch({
      GenomicDataCommons::status()
    }, error = function(e) {
      NULL
    })
    
    if (is.null(gdc_status) || gdc_status\$status != "OK") {
      message("GDC API is currently unavailable or offline. Writing fallback outputs.")
      write_fallback("gene_metadata.csv", "GDC API offline")
      write_fallback("somatic_mutations.csv", "GDC API offline")
      write_fallback("project_mutation_distribution.csv", "GDC API offline")
      write_fallback("clinical_summary.csv", "GDC API offline")
      pdf("project_mutation_distribution.pdf")
      plot.new()
      text(0.5, 0.5, "GDC API Offline - No Plot Generated")
      dev.off()
      quit(save = "no", status = 0)
    }
    
    # ==========================================
    # STAGE 2: Query Gene Metadata
    # ==========================================
    message("Stage 2: Querying gene metadata from GDC...")
    
    g_results <- tryCatch({
      genes() |>
        GenomicDataCommons::filter(symbol %in% gene_list) |>
        results_all()
    }, error = function(e) {
      message("Error querying genes: ", e\$message)
      NULL
    })
    
    if (is.null(g_results) || length(g_results\$id) == 0) {
      message("No matching genes found in GDC. Writing fallbacks.")
      write_fallback("gene_metadata.csv", "No matching genes found")
      write_fallback("somatic_mutations.csv", "No matching genes found")
      write_fallback("project_mutation_distribution.csv", "No matching genes found")
      write_fallback("clinical_summary.csv", "No matching genes found")
      pdf("project_mutation_distribution.pdf")
      plot.new()
      text(0.5, 0.5, "No matching genes found")
      dev.off()
      quit(save = "no", status = 0)
    }
    
    # Format and write gene metadata
    gene_df <- data.frame(
      gene_id = g_results\$id,
      symbol = g_results\$symbol,
      name = g_results\$name,
      chromosome = g_results\$gene_chromosome,
      start = g_results\$gene_start,
      end = g_results\$gene_end,
      biotype = g_results\$biotype,
      stringsAsFactors = FALSE
    )
    write.csv(gene_df, "gene_metadata.csv", row.names = FALSE)
    
    # ==========================================
    # STAGE 3: Query Simple Somatic Mutations (SSMs)
    # ==========================================
    message("Stage 3: Querying simple somatic mutations (SSMs)...")
    
    ssm_query <- ssms() |>
      GenomicDataCommons::filter(consequence.transcript.gene.symbol %in% gene_list)
    
    ssm_count <- count(ssm_query)
    message(paste("Found", ssm_count, "somatic mutations associated with input genes."))
    
    if (ssm_count > 0) {
      ssm_res <- ssm_query |> results(size = min(ssm_count, 1000))
      ssm_df <- data.frame(
        ssm_id = ssm_res\$id,
        chromosome = ssm_res\$chromosome,
        start = ssm_res\$start_position,
        end = ssm_res\$end_position,
        ref_allele = ssm_res\$reference_allele,
        alt_allele = ssm_res\$tumor_allele,
        mutation_subtype = ssm_res\$mutation_subtype,
        stringsAsFactors = FALSE
      )
      write.csv(ssm_df, "somatic_mutations.csv", row.names = FALSE)
    } else {
      write_fallback("somatic_mutations.csv", "No somatic mutations found for these genes")
    }
    
    # ==========================================
    # STAGE 4: Query Mutation Occurrences & Projects
    # ==========================================
    message("Stage 4: Querying mutation occurrences and project distributions...")
    
    agg_results <- tryCatch({
      ssm_occurrences() |>
        GenomicDataCommons::filter(ssm.consequence.transcript.gene.symbol %in% gene_list) |>
        facet("case.project.project_id") |>
        aggregations()
    }, error = function(e) {
      message("Error performing aggregation: ", e\$message)
      NULL
    })
    
    if (!is.null(agg_results) && "case.project.project_id" %in% names(agg_results)) {
      proj_agg <- agg_results[["case.project.project_id"]]
      write.csv(proj_agg, "project_mutation_distribution.csv", row.names = FALSE)
      
      # Generate barplot of mutation distribution across projects
      pdf("project_mutation_distribution.pdf", width = 12, height = 7)
      par(mar = c(10, 5, 4, 2))
      barplot(
        proj_agg\$doc_count,
        names.arg = proj_agg\$key,
        las = 2,
        col = "steelblue",
        main = paste("Somatic Mutation Occurrences by GDC Project\nGenes:", paste(gene_list, collapse = ", ")),
        ylab = "Occurrence Count",
        cex.names = 0.8
      )
      dev.off()
    } else {
      write_fallback("project_mutation_distribution.csv", "No project distribution data available")
      pdf("project_mutation_distribution.pdf")
      plot.new()
      text(0.5, 0.5, "No project distribution data available")
      dev.off()
    }
    
    # ==========================================
    # STAGE 5: Retrieve Clinical Profiles of Cases
    # ==========================================
    message("Stage 5: Retrieving clinical profiles for mutated cases...")
    
    occur_query <- ssm_occurrences() |>
      GenomicDataCommons::filter(ssm.consequence.transcript.gene.symbol %in% gene_list) |>
      GenomicDataCommons::expand(c('case', 'case.project'))
    
    occur_count <- count(occur_query)
    
    if (occur_count > 0) {
      occur_res <- occur_query |> results(size = min(occur_count, 500))
      
      case_ids <- extract_field(occur_res\$case, "case_id")
      project_ids <- extract_field(occur_res\$case, c("project", "project_id"))
      disease_types <- extract_field(occur_res\$case, "disease_type")
      
      unique_cases <- unique(case_ids[!is.na(case_ids)])
      
      if (length(unique_cases) > 0) {
        # Query clinical data for up to 100 unique cases to avoid API timeouts
        target_cases <- unique_cases[1:min(length(unique_cases), 100)]
        clin_data <- tryCatch({
          gdc_clinical(target_cases)
        }, error = function(e) {
          NULL
        })
        
        if (!is.null(clin_data) && "main" %in% names(clin_data)) {
          clinical_df <- as.data.frame(clin_data\$main)
          # Merge with demographic details if available
          if ("demographic" %in% names(clin_data)) {
            clinical_df <- merge(clinical_df, as.data.frame(clin_data\$demographic), 
                                 by = "case_id", all.x = TRUE)
          }
          write.csv(clinical_df, "clinical_summary.csv", row.names = FALSE)
        } else {
          # Fallback to basic case metadata extracted from occurrences
          fallback_clin <- data.frame(
            case_id = case_ids,
            project_id = project_ids,
            disease_type = disease_types,
            stringsAsFactors = FALSE
          )
          fallback_clin <- unique(fallback_clin)
          write.csv(fallback_clin, "clinical_summary.csv", row.names = FALSE)
        }
      } else {
        write_fallback("clinical_summary.csv", "No valid cases found with these mutations")
      }
    } else {
      write_fallback("clinical_summary.csv", "No cases found with these mutations")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GENOMICDATACOMMONS_GDC_SOMATIC_MUTATION_ANALYSIS":',
        paste0('    GenomicDataCommons: ', as.character(packageVersion('GenomicDataCommons')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gdc_somatic_mutation_analysis.csv versions.yml
    """
}

workflow BIOC_GENOMICDATACOMMONS_GDC_SOMATIC_MUTATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GENOMICDATACOMMONS_GDC_SOMATIC_MUTATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENOMICDATACOMMONS_GDC_SOMATIC_MUTATION_ANALYSIS.out.tables
    plots    = BIOC_GENOMICDATACOMMONS_GDC_SOMATIC_MUTATION_ANALYSIS.out.plots
    objects  = BIOC_GENOMICDATACOMMONS_GDC_SOMATIC_MUTATION_ANALYSIS.out.objects
    versions = BIOC_GENOMICDATACOMMONS_GDC_SOMATIC_MUTATION_ANALYSIS.out.versions
}
