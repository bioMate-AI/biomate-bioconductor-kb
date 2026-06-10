#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phyloprofile — domain_architecture_plot
// Generate a domain architecture plot for a gene of interest and its orthologs.
// Input: gene.domains
// Container: quay.io/biocontainers/bioconductor-phyloprofile:2.2.2--r45hdfd78af_0
// R packages: PhyloProfile
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-phyloprofile:2.2.2--r45hdfd78af_0"

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
    
    # Define input file
    domainFile <- "gene.domains"
    
    # Check if input file exists
    if (!file.exists(domainFile)) {
        stop(paste("Input file not found:", domainFile))
    }
    
    # Dynamically extract seedID and orthoID from the input file to ensure robustness
    raw_lines <- readLines(domainFile, n = 200)
    split_lines <- strsplit(raw_lines, "\t")
    ids <- sapply(split_lines, function(x) x[1])
    ids <- unique(ids[!is.na(ids) & ids != ""])
    # Exclude potential header names
    ids <- ids[!tolower(ids) %in% c("seqid", "geneid", "orthoid", "seedid", "id")]
    
    if (length(ids) == 0) {
        stop("No valid gene/sequence IDs found in the input domain file.")
    }
    
    seedID <- ids[1]
    if (length(ids) > 1) {
        orthoID <- ids[2]
    } else {
        orthoID <- seedID
    }
    
    info <- c(seedID, orthoID)
    
    # 1. Parse domain input file using parseDomainInput
    domainDf <- parseDomainInput(seedID, domainFile, "file")
    
    # 2. Modify feature IDs
    domainDf\$feature_id_mod <- domainDf\$feature_id
    domainDf\$feature_id_mod <- gsub("SINGLE", "LCR", domainDf\$feature_id_mod)
    domainDf\$feature_id_mod[domainDf\$feature_type == "coils"] <- "Coils"
    domainDf\$feature_id_mod[domainDf\$feature_type == "seg"] <- "LCR"
    domainDf\$feature_id_mod[domainDf\$feature_type == "tmhmm"] <- "TM"
    
    # Save the processed domain dataframe
    write.csv(domainDf, "domain_architecture_data.csv", row.names = FALSE)
    
    # 3. Generate the domain plot using createArchiPlot and draw it
    plot <- createArchiPlot(info, domainDf, 9, 9)
    
    # Save the plot to a PDF file
    pdf("domain_architecture_plot.pdf", width = 10, height = 8)
    grid::grid.draw(plot)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOT":
        phyloprofile: \$(Rscript -e 'cat(as.character(packageVersion("phyloprofile")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_domain_architecture_plot.csv versions.yml
    """
}

workflow BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene.domains ] ]

    main:
    BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOT(ch_input)

    emit:
    tables   = BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOT.out.tables
    plots    = BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOT.out.plots
    objects  = BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOT.out.objects
    versions = BIOC_PHYLOPROFILE_DOMAIN_ARCHITECTURE_PLOT.out.versions
}
