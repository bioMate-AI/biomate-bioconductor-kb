#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PhyloProfile — domain_architecture_plotting
// Generate a protein domain architecture plot for a gene of interest and its orthologs.
// Input: domain_annotation.txt
// Container: quay.io/biocontainers/bioconductor-phyloprofile:2.2.2--r45hdfd78af_0
// R packages: PhyloProfile
// Bioconductor: 3.20 | R: 4.4
// Requires: PhyloProfile
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Parse domain input file using `parseDomainInput`
//  * 2. [Visualization & Output] Modify feature IDs for visualization
//  * 3. [Visualization & Output] Generate domain plot using `createArchiPlot` and draw it

nextflow.enable.dsl = 2

process BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOTTING {
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
    .bm_deps <- c("PhyloProfile")
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
    library(PhyloProfile)
    library(grid)
    
    # Define input file path
    domainFile <- "domain_annotation.txt"
    
    if (!file.exists(domainFile)) {
      stop(paste("Required input file '", domainFile, "' not found in the working directory.", sep = ""))
    }
    
    # Dynamically extract seedID and orthoID from the input file
    # Typically, the first column contains the sequence/gene IDs.
    raw_lines <- readLines(domainFile, n = 500)
    split_lines <- strsplit(raw_lines, "\t")
    first_elements <- sapply(split_lines, function(x) x[1])
    first_elements <- first_elements[!is.na(first_elements) & first_elements != "" & first_elements != "seqID" & first_elements != "geneID"]
    unique_ids <- unique(first_elements)
    
    if (length(unique_ids) == 0) {
      stop("Could not extract any valid gene/sequence IDs from the first column of domain_annotation.txt")
    }
    
    # Identify seedID (typically shorter, without pipe '|') and orthoID (with pipe '|')
    has_pipe <- grepl("\\\\|", unique_ids)
    seeds <- unique_ids[!has_pipe]
    orthos <- unique_ids[has_pipe]
    
    if (length(seeds) > 0) {
      seedID <- seeds[1]
    } else {
      seedID <- unique_ids[1]
    }
    
    if (length(orthos) > 0) {
      # Find an ortholog that belongs to this seed if possible
      matching_orthos <- orthos[startsWith(orthos, seedID)]
      if (length(matching_orthos) > 0) {
        orthoID <- matching_orthos[1]
      } else {
        orthoID <- orthos[1]
      }
    } else {
      orthoID <- unique_ids[min(2, length(unique_ids))]
    }
    
    message(paste("Selected Seed ID:", seedID))
    message(paste("Selected Ortholog ID:", orthoID))
    
    info <- c(seedID, orthoID)
    
    # 1. Parse domain input file using parseDomainInput
    domainDf <- parseDomainInput(seedID, domainFile, "file")
    
    # 2. Modify feature IDs for visualization
    domainDf\$feature_id_mod <- domainDf\$feature_id
    domainDf\$feature_id_mod <- gsub("SINGLE", "LCR", domainDf\$feature_id_mod)
    domainDf\$feature_id_mod[domainDf\$feature_type == "coils"] <- "Coils"
    domainDf\$feature_id_mod[domainDf\$feature_type == "seg"] <- "LCR"
    domainDf\$feature_id_mod[domainDf\$feature_type == "tmhmm"] <- "TM"
    
    # Save the modified domain dataframe to a CSV file
    write.csv(domainDf, "modified_domain_annotations.csv", row.names = FALSE)
    
    # 3. Generate domain plot using createArchiPlot and draw it
    plot <- createArchiPlot(info, domainDf, 9, 9)
    
    # Save the plot object as an RDS file
    saveRDS(plot, "domain_architecture_plot.rds")
    
    # Save the plot as a PDF file
    pdf("domain_architecture_plot.pdf", width = 10, height = 8)
    grid::grid.draw(plot)
    dev.off()
    
    # Draw to the default device/stdout if running interactively
    grid::grid.draw(plot)
    
    message("Pipeline completed successfully. Outputs written: 'modified_domain_annotations.csv', 'domain_architecture_plot.rds', and 'domain_architecture_plot.pdf'.")

    writeLines(c(
        '"BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOTTING":',
        paste0('    PhyloProfile: ', as.character(packageVersion('PhyloProfile')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_domain_architecture_plotting.csv versions.yml
    """
}

workflow BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ domain_annotation.txt ] ]

    main:
    BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOTTING(ch_input)

    emit:
    tables   = BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOTTING.out.tables
    plots    = BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOTTING.out.plots
    objects  = BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOTTING.out.objects
    versions = BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOTTING.out.versions
}
