#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: VaSP — splicing_quantification_and_gss_discovery
// Calculate Single Splicing Strength (3S) scores and identify genotype-specific splicing (GSS) events from a Ballgown object.
// Input: rice.bg, Sample_027.bam
// Container: quay.io/biocontainers/bioconductor-vasp:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, VaSP
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate 3S scores or junction counts for a specific gene using spliceGene, or genome-wide using spliceGenome
//  * 2. [Core Analysis] Identify bimodal distribution features (GSS events) using BMfinder
//  * 3. [Core Analysis] Extract genomic coordinates of the identified GSS introns using structure
//  * 4. [Input & Preparation] Extract read depth from BAM files using getDepth and gene information using getGeneinfo

nextflow.enable.dsl = 2

process BIOC_VASP_SPLICING_QUANTIFICATION_AND_GSS_DISCOVERY {
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
    .bm_deps <- c("VaSP", "GenomicRanges")
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
    library(VaSP)
    library(GenomicRanges)
    
    # 1. Load the Ballgown object from the user-provided 'rice.bg' file
    if (!file.exists("rice.bg")) {
      stop("Error: 'rice.bg' file not found in the working directory.")
    }
    
    rice.bg <- tryCatch({
      readRDS("rice.bg")
    }, error = function(e) {
      tmp_env <- new.env()
      load("rice.bg", envir = tmp_env)
      bg_objs <- sapply(ls(tmp_env), function(x) inherits(tmp_env[[x]], "ballgown"))
      if (any(bg_objs)) {
        tmp_env[[names(bg_objs)[which(bg_objs)[1]]]]
      } else {
        tmp_env[[ls(tmp_env)[1]]]
      }
    })
    
    # 2. Calculate 3S scores and junction counts for a specific gene
    score <- spliceGene(rice.bg, gene="MSTRG.183", junc.type = "score")
    count <- spliceGene(rice.bg, "MSTRG.183", junc.type = "count")
    
    # Save gene-specific splicing scores and counts
    write.csv(as.data.frame(score), "splicing_score_MSTRG.183.csv", row.names = TRUE)
    write.csv(as.data.frame(count), "splicing_count_MSTRG.183.csv", row.names = TRUE)
    
    # 3. Identify bimodal distribution features (GSS events)
    gss <- BMfinder(score, cores = 1)
    write.csv(as.data.frame(gss), "gss_events.csv", row.names = TRUE)
    
    # 4. Extract genomic coordinates of the identified GSS introns
    gss_intron <- structure(rice.bg)\$intron
    gss_intron <- gss_intron[gss_intron\$id %in% rownames(gss)]
    gss_intron_range <- range(gss_intron)
    
    # Save GSS intron information
    saveRDS(gss_intron, "gss_introns.rds")
    write.csv(as.data.frame(gss_intron), "gss_introns.csv", row.names = FALSE)
    
    # 5. Calculate genome-wide splicing scores
    splice <- spliceGenome(rice.bg, gene.select = NA, intron.select = NA)
    saveRDS(splice, "genome_wide_splice.rds")
    write.csv(as.data.frame(splice\$score), "genome_wide_splice_scores.csv", row.names = TRUE)
    
    # 6. Extract read depth from BAM file
    bam_file <- "Sample_027.bam"
    if (!file.exists(bam_file)) {
      stop("Error: 'Sample_027.bam' file not found in the working directory.")
    }
    depth <- getDepth(bam_file, "Chr1", start = 1171800, end = 1179400)
    write.csv(depth, "read_depth_Chr1.csv", row.names = FALSE)
    
    # 7. Extract gene information
    gene_id <- c("MSTRG.181", "MSTRG.182", "MSTRG.183")
    geneinfo <- getGeneinfo(genes = gene_id, rice.bg)
    write.csv(geneinfo, "gene_info.csv", row.names = FALSE)
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_VASP_SPLICING_QUANTIFICATION_AND_GSS_DISCOVERY":',
        paste0('    VaSP: ', as.character(packageVersion('VaSP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splicing_quantification_and_gss_discovery.csv versions.yml
    """
}

workflow BIOC_VASP_SPLICING_QUANTIFICATION_AND_GSS_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rice.bg, Sample_027.bam ] ]

    main:
    BIOC_VASP_SPLICING_QUANTIFICATION_AND_GSS_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_VASP_SPLICING_QUANTIFICATION_AND_GSS_DISCOVERY.out.tables
    plots    = BIOC_VASP_SPLICING_QUANTIFICATION_AND_GSS_DISCOVERY.out.plots
    objects  = BIOC_VASP_SPLICING_QUANTIFICATION_AND_GSS_DISCOVERY.out.objects
    versions = BIOC_VASP_SPLICING_QUANTIFICATION_AND_GSS_DISCOVERY.out.versions
}
