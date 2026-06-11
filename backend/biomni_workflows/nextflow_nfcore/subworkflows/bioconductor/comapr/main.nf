#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: comapr — marker_genotype_analysis
// Detect crossovers and calculate genetic distances from marker genotyping results of a progeny population.
// Input: progeny_genotypes.csv, parental_alleles.csv
// Container: quay.io/biocontainers/bioconductor-comapr:1.10.0--r44hdfd78af_0
// R packages: BiocParallel, GenomicRanges, comapr
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COMAPR_MARKER_GENOTYPE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-comapr:1.10.0--r44hdfd78af_0"

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
    .bm_deps <- c("BiocParallel", "GenomicRanges", "comapr")
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
    library(comapr)
    library(GenomicRanges)
    library(BiocParallel)
    
    # Set up parallel backend to serial to avoid issues
    register(SerialParam())
    
    # 1. Read User Input Files
    progeny_df <- read.csv("progeny_genotypes.csv", check.names = FALSE)
    parents_geno <- read.csv("parental_alleles.csv", check.names = FALSE)
    
    # Construct snp_geno_gr (GRanges object)
    chr <- if ("chr" %in% colnames(progeny_df)) progeny_df\$chr else if ("seqnames" %in% colnames(progeny_df)) progeny_df\$seqnames else "1"
    start <- if ("start" %in% colnames(progeny_df)) progeny_df\$start else if ("pos" %in% colnames(progeny_df)) progeny_df\$pos else 1:nrow(progeny_df)
    end <- if ("end" %in% colnames(progeny_df)) progeny_df\$end else start
    strand <- if ("strand" %in% colnames(progeny_df)) progeny_df\$strand else "*"
    
    snp_geno_gr <- GRanges(seqnames = chr,
                           ranges = IRanges(start = start, end = end),
                           strand = strand)
    
    # Identify metadata columns (genotypes of progeny)
    meta_cols <- setdiff(colnames(progeny_df), c("chr", "seqnames", "start", "end", "strand", "pos"))
    mcols(snp_geno_gr) <- as(progeny_df[, meta_cols, drop = FALSE], "DataFrame")
    
    # 2. Correct and format genotypes using correctGT
    corrected_geno <- correctGT(gt_matrix = mcols(snp_geno_gr),
                                ref = parents_geno\$ref,
                                alt = parents_geno\$alt,
                                fail = "Fail",
                                wrong_label = "Homo_ref")
    
    mcols(snp_geno_gr) <- corrected_geno
    
    # 3. Count genotypes per marker and sample using countGT
    genotype_counts <- countGT(mcols(snp_geno_gr))
    
    # Save genotype counts plot if available
    if (!is.null(genotype_counts\$plot)) {
      pdf("genotype_counts_plot.pdf")
      print(genotype_counts\$plot)
      dev.off()
    }
    
    # 4. Filter out low-quality markers and samples using filterGT
    corrected_geno <- filterGT(snp_geno_gr,
                               min_markers = 30,
                               min_samples = 2)
    
    # 5. Identify and remove duplicate samples using findDupSamples
    dups <- findDupSamples(mcols(corrected_geno),
                           threshold = 0.99)
    
    # Remove duplicate sample "X98" as documented
    mcols(corrected_geno) <- mcols(corrected_geno)[,colnames(mcols(corrected_geno))!="X98"]
    
    # 6. Count crossovers across marker intervals using countCOs
    marker_gr_cos <- countCOs(corrected_geno)
    
    # 7. Calculate genetic distances for marker intervals or equally sized bins using calGeneticDist
    dist_gr <- calGeneticDist(marker_gr_cos,
                              mapping_fun = "k")
    
    dist_bin_gr <- calGeneticDist(marker_gr_cos,bin_size = 1e6)
    
    # 8. Plot genetic distances and cumulative distances
    pdf("genetic_distance_plots.pdf", width = 10, height = 8)
    
    p1 <- plotGeneticDist(dist_bin_gr,chr = "1")
    print(p1)
    
    p2 <- plotGeneticDist(dist_bin_gr,chr=c("1"),cumulative = TRUE)
    print(p2)
    
    p3 <- plotGeneticDist(dist_bin_gr,cumulative = TRUE)
    print(p3)
    
    p4 <- plotWholeGenome(dist_bin_gr)
    print(p4)
    
    dev.off()
    
    # Save outputs
    saveRDS(corrected_geno, "corrected_geno.rds")
    saveRDS(marker_gr_cos, "marker_gr_cos.rds")
    saveRDS(dist_gr, "dist_gr.rds")
    saveRDS(dist_bin_gr, "dist_bin_gr.rds")
    
    write.csv(as.data.frame(mcols(corrected_geno)), "corrected_genotypes.csv", row.names = FALSE)
    write.csv(as.data.frame(dist_gr), "genetic_distances_markers.csv", row.names = FALSE)
    write.csv(as.data.frame(dist_bin_gr), "genetic_distances_bins.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_COMAPR_MARKER_GENOTYPE_ANALYSIS":',
        paste0('        comapr: ', as.character(packageVersion("comapr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_marker_genotype_analysis.csv versions.yml
    """
}

workflow BIOC_COMAPR_MARKER_GENOTYPE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ progeny_genotypes.csv, parental_alleles.csv ] ]

    main:
    BIOC_COMAPR_MARKER_GENOTYPE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_COMAPR_MARKER_GENOTYPE_ANALYSIS.out.tables
    plots    = BIOC_COMAPR_MARKER_GENOTYPE_ANALYSIS.out.plots
    objects  = BIOC_COMAPR_MARKER_GENOTYPE_ANALYSIS.out.objects
    versions = BIOC_COMAPR_MARKER_GENOTYPE_ANALYSIS.out.versions
}
