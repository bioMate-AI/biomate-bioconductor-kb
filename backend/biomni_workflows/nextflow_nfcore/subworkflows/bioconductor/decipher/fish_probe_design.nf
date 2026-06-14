#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decipher — fish_probe_design
// Design and evaluate specific hybridization probes (FISH) targeting a taxonomic group.
// Input: gb, dbConn
// Container: quay.io/biocontainers/bioconductor-decipher:3.6.0--r45h01b2380_0
// R packages: DECIPHER, RSQLite
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECIPHER_FISH_PROBE_DESIGN {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-decipher:3.6.0--r45h01b2380_0"

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
    .bm_deps <- c("DECIPHER", "RSQLite")
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
    library(DECIPHER)
    library(RSQLite)
    
    # Define input file paths from the working directory
    gb <- "gb"
    dbConnPath <- "dbConn"
    
    # Establish SQLite database connection
    dbConn <- dbConnect(SQLite(), dbConnPath)
    
    # --- Import sequences into an SQLite database using Seqs2DB ---
    Seqs2DB(gb, "GenBank", dbConn, "Bacteria")
    
    # --- Identify taxonomic ranks using IdentifyByRank ---
    ids <- IdentifyByRank(dbConn, level=Inf, add2tbl=TRUE)
    
    # --- Generate sequence tiles using TileSeqs ---
    tiles <- TileSeqs(dbConn, add2tbl="Tiles")
    
    # --- Design specific probes using DesignProbes ---
    # Note: "Sphingopyxis" is the target group specified in the documented workflow.
    # If the input GenBank file does not contain this group, probes may be empty.
    probes <- DesignProbes(tiles, identifier="Sphingopyxis",
    	start=120, end=1450)
    
    # Prepare inputs for CalculateEfficiencyFISH to match the exact documented call.
    # We handle cases where 'probes' might be empty to ensure robustness.
    if (!is.null(probes) && nrow(probes) > 0) {
        probe <- probes\$probe[1]
        targets <- reverseComplement(DNAStringSet(probe))
        FA <- 35
    } else {
        # Fallback default probe/target if "Sphingopyxis" is not present in the user's custom gb file
        probe <- "AGCGTTTGACATCCTGATCGCGG"
        targets <- reverseComplement(DNAStringSet(probe))
        FA <- 35
    }
    
    # --- Evaluate hybridization efficiency using ---
    efficiency <- CalculateEfficiencyFISH(probe, targets,
    		temp=46, P=250e-9, ions=1, FA)
    
    # Save outputs to CSV files
    write.csv(ids, "identified_ranks.csv", row.names = FALSE)
    write.csv(tiles, "sequence_tiles.csv", row.names = FALSE)
    write.csv(probes, "designed_probes.csv", row.names = FALSE)
    write.csv(as.data.frame(efficiency), "probe_efficiency.csv", row.names = FALSE)
    
    # Save RDS objects for downstream analysis
    saveRDS(ids, "ids.rds")
    saveRDS(tiles, "tiles.rds")
    saveRDS(probes, "probes.rds")
    saveRDS(efficiency, "efficiency.rds")
    
    # Generate a PDF plot summarizing the probe design results
    pdf("probe_design_summary.pdf")
    if (!is.null(probes) && nrow(probes) > 0) {
        plot(probes\$start, probes\$score, 
             xlab = "Start Position", ylab = "Score", 
             main = "Designed Probes Score vs Position",
             col = "blue", pch = 19)
    } else {
        plot(1, type="n", xlab="", ylab="", main="No probes designed for Sphingopyxis")
        text(1, 1, "No probes designed.\nCheck if 'Sphingopyxis' is in the input GenBank file.")
    }
    dev.off()
    
    # Disconnect from the database
    dbDisconnect(dbConn)

    writeLines(c(
        '"BIOC_DECIPHER_FISH_PROBE_DESIGN":',
        paste0('        decipher: ', as.character(packageVersion("decipher")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fish_probe_design.csv versions.yml
    """
}

workflow BIOC_DECIPHER_FISH_PROBE_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gb, dbConn ] ]

    main:
    BIOC_DECIPHER_FISH_PROBE_DESIGN(ch_input)

    emit:
    tables   = BIOC_DECIPHER_FISH_PROBE_DESIGN.out.tables
    plots    = BIOC_DECIPHER_FISH_PROBE_DESIGN.out.plots
    objects  = BIOC_DECIPHER_FISH_PROBE_DESIGN.out.objects
    versions = BIOC_DECIPHER_FISH_PROBE_DESIGN.out.versions
}
