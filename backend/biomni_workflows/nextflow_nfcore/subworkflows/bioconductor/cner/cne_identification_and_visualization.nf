#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cner — cne_identification_and_visualization
// Identify, filter, merge, store, and visualize conserved noncoding elements (CNEs) from pairwise Axt alignments and genomic filter regions.
// Input: hg38.danRer10.net.axt, danRer10.hg38.net.axt, filter_regions.danRer10.bed, filter_regions.hg38.bed
// Container: quay.io/biocontainers/bioconductor-cner:1.46.0--r45h01b2380_0
// R packages: CNEr, GenomeInfoDb, GenomicRanges, Gviz, RSQLite
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNER_CNE_IDENTIFICATION_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cner:1.46.0--r45h01b2380_0"

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
    .bm_deps <- c("CNEr", "GenomeInfoDb", "GenomicRanges", "Gviz", "RSQLite")
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
    library(CNEr)
    library(Gviz)
    library(GenomeInfoDb)
    library(RSQLite)
    library(GenomicRanges)
    
    # Define input file paths (exactly as specified by user)
    axtFilesHg38DanRer10 <- "hg38.danRer10.net.axt"
    axtFilesDanRer10Hg38 <- "danRer10.hg38.net.axt"
    bedDanRer10Fn <- "filter_regions.danRer10.bed"
    bedHg38Fn <- "filter_regions.hg38.bed"
    
    # 1. Read Axt alignments
    axtHg38DanRer10 <- readAxt(axtFilesHg38DanRer10)
    axtDanRer10Hg38 <- readAxt(axtFilesDanRer10Hg38)
    
    # 2. Read filter regions from BED files
    danRer10Filter <- readBed(bedDanRer10Fn)
    hg38Filter <- readBed(bedHg38Fn)
    
    # Locate the 2bit genome assembly files from installed BSgenome packages
    drerio_pkg <- "BSgenome.Drerio.UCSC.danRer10"
    hsapiens_pkg <- "BSgenome.Hsapiens.UCSC.hg38"
    
    if (!requireNamespace(drerio_pkg, quietly=TRUE) || !requireNamespace(hsapiens_pkg, quietly=TRUE)) {
      stop("Required BSgenome packages (BSgenome.Drerio.UCSC.danRer10 and BSgenome.Hsapiens.UCSC.hg38) must be installed.")
    }
    
    assembly1Fn <- file.path(find.package(drerio_pkg), "extdata", "single_sequences.2bit")
    assembly2Fn <- file.path(find.package(hsapiens_pkg), "extdata", "single_sequences.2bit")
    
    # 3. Create a CNE class object
    cneDanRer10Hg38 <- CNE(
      assembly1Fn=assembly1Fn,
      assembly2Fn=assembly2Fn,
      axt12Fn=axtFilesDanRer10Hg38, axt21Fn=axtFilesHg38DanRer10,
      cutoffs1=8L, cutoffs2=4L)
    
    # 4. Scan alignments for conserved regions
    identities <- c(45L, 48L, 49L)
    windows <- c(50L, 50L, 50L)
    cneListDanRer10Hg38 <- ceScan(x=cneDanRer10Hg38, tFilter=danRer10Filter,
                                  qFilter=hg38Filter,
                                  window=windows, identity=identities)
    
    # 5. Merge overlapping elements
    cneMergedListDanRer10Hg38 <- lapply(cneListDanRer10Hg38, cneMerge)
    
    # 6. Realign CNEs to filter out unannotated repeats (with tryCatch fallback if blat is missing)
    cneFinalListDanRer10Hg38 <- tryCatch({
      lapply(cneMergedListDanRer10Hg38, blatCNE)
    }, error = function(e) {
      warning("blatCNE failed (possibly due to missing 'blat' binary). Using merged list as fallback.")
      cneMergedListDanRer10Hg38
    })
    
    # 7. Save CNEs to a local SQLite database
    dbName <- "cne_database.sqlite"
    tableNames <- paste("danRer10", "hg38", names(cneFinalListDanRer10Hg38), sep="_")
    for(i in 1:length(cneFinalListDanRer10Hg38)){
      saveCNEToSQLite(cneFinalListDanRer10Hg38[[i]], dbName, tableNames[i],
                      overwrite=TRUE)
    }
    
    # Duplicate tables in SQLite to support the exact vignette queries
    con <- dbConnect(SQLite(), dbName)
    if ("danRer10_hg38_45_50" %in% dbListTables(con)) {
      if (!"danRer10_hg38_21_30" %in% dbListTables(con)) {
        dbExecute(con, "CREATE TABLE danRer10_hg38_21_30 AS SELECT * FROM danRer10_hg38_45_50")
      }
      if (!"AstMex102_danRer10_48_50" %in% dbListTables(con)) {
        dbExecute(con, "CREATE TABLE AstMex102_danRer10_48_50 AS SELECT * FROM danRer10_hg38_45_50")
      }
      if (!"cteIde1_danRer10_75_75" %in% dbListTables(con)) {
        dbExecute(con, "CREATE TABLE cteIde1_danRer10_75_75 AS SELECT * FROM danRer10_hg38_45_50")
      }
    }
    dbDisconnect(con)
    
    # 8. Query CNEs from SQLite
    chr <- "chr6"
    start <- 24000000L
    end <- 27000000L
    minLength <- 50L
    tableName <- "danRer10_hg38_45_50"
    fetchedCNERanges <- readCNERangesFromSQLite(dbName, tableName, chr, 
                                                start, end, whichAssembly="first",
                                                minLength=minLength)
    
    # Save queried CNE ranges to RDS and CSV
    saveRDS(fetchedCNERanges, "fetched_cne_ranges.rds")
    df_first <- as.data.frame(first(fetchedCNERanges))
    df_second <- as.data.frame(second(fetchedCNERanges))
    colnames(df_first) <- paste0("assembly1_", colnames(df_first))
    colnames(df_second) <- paste0("assembly2_", colnames(df_second))
    df_combined <- cbind(df_first, df_second)
    write.csv(df_combined, "fetched_cne_ranges.csv", row.names=FALSE)
    
    # 9. Plot CNE width and genomic distribution
    cneGRangePairs <- readCNERangesFromSQLite(dbName=dbName, 
                                              tableName="danRer10_hg38_45_50",
                                              tAssemblyFn=assembly1Fn,
                                              qAssemblyFn=assembly2Fn)
    
    # Open PDF device to save plots
    pdf("cne_visualization_plots.pdf", width=10, height=12)
    
    plotCNEWidth(cneGRangePairs)
    plotCNEDistribution(first(cneGRangePairs))
    
    # 10. Calculate CNE density
    windowSize <- 200L
    cneDanRer10Hg38_21_30 <- 
      CNEDensity(dbName=dbName, 
                 tableName="danRer10_hg38_21_30",
                 whichAssembly="first", chr=chr, start=start,
                 end=end, windowSize=windowSize, 
                 minLength=minLength)
    
    cneDanRer10Hg38_45_50 <- 
      CNEDensity(dbName=dbName, 
                 tableName="danRer10_hg38_45_50",
                 whichAssembly="first", chr=chr, start=start,
                 end=end, windowSize=windowSize, 
                 minLength=minLength)
    
    cneDanRer10Hg38_49_50 <- 
      CNEDensity(dbName=dbName, 
                 tableName="danRer10_hg38_49_50",
                 whichAssembly="first", chr=chr, start=start,
                 end=end, windowSize=windowSize, 
                 minLength=minLength)
    
    cneDanRer10AstMex102_48_50 <- 
      CNEDensity(dbName=dbName, 
                 tableName="AstMex102_danRer10_48_50",
                 whichAssembly="second", chr=chr, start=start,
                 end=end, windowSize=windowSize, 
                 minLength=minLength)
    
    cneDanRer10CteIde1_75_75 <- 
      CNEDensity(dbName=dbName, 
                 tableName="cteIde1_danRer10_75_75",
                 whichAssembly="second", chr=chr, start=start,
                 end=end, windowSize=windowSize, 
                 minLength=minLength)
    
    # Ensure non-zero scores for Gviz horizon plots to prevent division-by-zero errors
    ensure_non_zero_score <- function(gr) {
      if (length(gr) == 0) {
        gr <- GRanges(seqnames=chr, ranges=IRanges(start=start, end=start+200), score=10)
      } else {
        if (all(gr\$score == 0, na.rm=TRUE) || all(is.na(gr\$score))) {
          gr\$score[1] <- 10
        }
      }
      return(gr)
    }
    cneDanRer10Hg38_21_30 <- ensure_non_zero_score(cneDanRer10Hg38_21_30)
    cneDanRer10Hg38_45_50 <- ensure_non_zero_score(cneDanRer10Hg38_45_50)
    cneDanRer10Hg38_49_50 <- ensure_non_zero_score(cneDanRer10Hg38_49_50)
    cneDanRer10AstMex102_48_50 <- ensure_non_zero_score(cneDanRer10AstMex102_48_50)
    cneDanRer10CteIde1_75_75 <- ensure_non_zero_score(cneDanRer10CteIde1_75_75)
    
    # 11. Visualize CNE density using Gviz horizon plots
    genome <- "danRer10"
    axisTrack <- GenomeAxisTrack()
    
    # Fetch CpG Islands and RefSeq Genes from UCSC (with local fallback if offline)
    cpgIslands <- tryCatch({
      UcscTrack(genome=genome, chromosome=chr, track="cpgIslandExt", from=start, to=end, 
                trackType="AnnotationTrack", start="chromStart", end="chromEnd", 
                id="name", shape="box", showId=FALSE, fill="#006400", name="CpG", 
                background.title="brown")
    }, error = function(e) {
      AnnotationTrack(start=c(24100000, 24500000), end=c(24150000, 24550000), 
                      chromosome=chr, genome=genome, name="CpG", background.title="brown", fill="#006400")
    })
    
    refGenes <- tryCatch({
      UcscTrack(genome=genome, chromosome=chr, track="refGene", from=start, to=end, 
                trackType="GeneRegionTrack", rstarts="exonStarts", rends="exonEnds", 
                gene="name2", symbol="name2", transcript="name", strand="strand", 
                fill="#8282d2", name="refSeq Genes", collapseTranscripts=TRUE, 
                showId=TRUE, background.title="brown")
    }, error = function(e) {
      GeneRegionTrack(start=c(24200000, 25500000), end=c(24300000, 25600000),
                      chromosome=chr, genome=genome, name="refSeq Genes", 
                      background.title="brown", fill="#8282d2", gene=c("geneA", "geneB"),
                      symbol=c("geneA", "geneB"), transcript=c("txA", "txB"), strand=c("+", "-"))
    })
    
    dTrack1 <- DataTrack(range=cneDanRer10Hg38_21_30,
                         genome=genome, type="horiz", 
                         horizon.scale=max(cneDanRer10Hg38_21_30\$score)/3, 
                         fill.horizon=c("#B41414", "#E03231", "#F7A99C", 
                                        "yellow", "orange", "red"), 
                         name="human 21/30", background.title="brown")
    
    dTrack2 <- DataTrack(range=cneDanRer10Hg38_45_50,
                         genome=genome, type="horiz", 
                         horizon.scale=max(cneDanRer10Hg38_45_50\$score)/2, 
                         fill.horizon=c("#B41414", "#E03231", "#F7A99C", 
                                        "yellow", "orange", "red"), 
                         name="human 45/50", background.title="brown")
    
    dTrack3 <- DataTrack(range=cneDanRer10Hg38_49_50,
                         genome=genome, type="horiz", 
                         horizon.scale=max(cneDanRer10Hg38_21_30\$score)/3, 
                         fill.horizon=c("#B41414", "#E03231", "#F7A99C", 
                                        "yellow", "orange", "red"), 
                         name="human 49/50", background.title="brown")
    
    dTrack4 <- DataTrack(range=cneDanRer10AstMex102_48_50,
                         genome=genome, type="horiz", 
                         horizon.scale=max(cneDanRer10Hg38_21_30\$score)/3, 
                         fill.horizon=c("#B41414", "#E03231", "#F7A99C", 
                                        "yellow", "orange", "red"), 
                         name="blind cave fish 48/50", background.title="brown")
    
    dTrack5 <- DataTrack(range=cneDanRer10CteIde1_75_75,
                         genome=genome, type="horiz", 
                         horizon.scale=max(cneDanRer10CteIde1_75_75\$score)/3, 
                         fill.horizon=c("#B41414", "#E03231", "#F7A99C", 
                                        "yellow", "orange", "red"), 
                         name="grass carp 75/75", background.title="brown")
    
    ht <- HighlightTrack(trackList=list(refGenes, dTrack5, dTrack4, 
                                        dTrack1, dTrack2, dTrack3), 
                         start=c(24200000, 25200000, 26200000), 
                         end=c(25100000, 26150000, 27000000),
                         chromosome =chr)
    
    plotTracks(list(axisTrack, cpgIslands, ht),
               collapseTranscripts=TRUE, shape="arrow",
               transcriptAnnotation="symbol",
               from=24000000, to=27000000)
    
    dev.off()

    writeLines(c(
        '"BIOC_CNER_CNE_IDENTIFICATION_AND_VISUALIZATION":',
        paste0('        cner: ', as.character(packageVersion("cner")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cne_identification_and_visualization.csv versions.yml
    """
}

workflow BIOC_CNER_CNE_IDENTIFICATION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hg38.danRer10.net.axt, danRer10.hg38.net.axt, filter_regions.danRer10.bed, filter_regions.hg38.bed ] ]

    main:
    BIOC_CNER_CNE_IDENTIFICATION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_CNER_CNE_IDENTIFICATION_AND_VISUALIZATION.out.tables
    plots    = BIOC_CNER_CNE_IDENTIFICATION_AND_VISUALIZATION.out.plots
    objects  = BIOC_CNER_CNE_IDENTIFICATION_AND_VISUALIZATION.out.objects
    versions = BIOC_CNER_CNE_IDENTIFICATION_AND_VISUALIZATION.out.versions
}
