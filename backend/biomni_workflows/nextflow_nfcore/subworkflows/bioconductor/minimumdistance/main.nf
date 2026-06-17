#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MinimumDistance — trio_denovo_cnv_calling
// Identify, filter, and visualize de novo copy number variants in case-parent trios from raw genotyping report files.
// Input: SNP_info.csv, FinalReport*.txt, sample_data.csv
// Container: quay.io/biocontainers/bioconductor-minimumdistance:1.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg18, MinimumDistance, SummarizedExperiment, VanillaICE, data.table, foreach, oligoClasses
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create marker annotation and set sequence info
//  * 2. [Visualization & Output] Define ArrayViews to manage raw source files and parsed output directory
//  * 3. [Input & Preparation] Define parsing parameters and parse source files
//  * 4. [Input & Preparation] Define pedigree structure and map sample IDs
//  * 5. [Input & Preparation] Construct a MinDistExperiment object
//  * 6. [Core Analysis] Segment the minimum distance and offspring log R ratios
//  * 7. [Core Analysis] Calculate posterior probabilities and call trio states
//  * 8. [Core Analysis] Filter called CNVs
//  * 9. [Visualization & Output] Merge adjacent segments and plot results

nextflow.enable.dsl = 2

process BIOC_MINIMUMDISTANCE_TRIO_DENOVO_CNV_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("oligoClasses", "VanillaICE", "MinimumDistance", "data.table", "BSgenome.Hsapiens.UCSC.hg18")
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
    library(oligoClasses)
    library(VanillaICE)
    library(MinimumDistance)
    library(data.table)
    library(BSgenome.Hsapiens.UCSC.hg18)
    library(grid)
    
    # Register sequential backend for foreach
    foreach::registerDoSEQ()
    
    # ==========================================
    # 1. Create marker annotation and set sequence info
    # ==========================================
    # Read SNP_info.csv from the current working directory
    features <- suppressWarnings(fread("SNP_info.csv"))
    fgr <- GRanges(paste0("chr", features\$Chr), IRanges(features\$Position, width=1),
                   isSnp=features[["Intensity Only"]]==0)
    fgr <- SnpGRanges(fgr)
    names(fgr) <- features[["Name"]]
    
    # Set sequence levels and info using hg18
    sl <- seqlevels(BSgenome.Hsapiens.UCSC.hg18)
    seqlevels(fgr) <- sl[sl %in% seqlevels(fgr)]
    seqinfo(fgr) <- seqinfo(BSgenome.Hsapiens.UCSC.hg18)[seqlevels(fgr),]
    fgr <- sort(fgr)
    
    # ==========================================
    # 2. Define ArrayViews to manage raw source files
    # ==========================================
    # Find all FinalReport files in the current working directory
    files <- list.files(".", full.names=TRUE, recursive=FALSE, pattern="FinalReport")
    
    parsedDir <- "ParsedFiles"
    if(!file.exists(parsedDir)) dir.create(parsedDir)
    views <- ArrayViews(rowRanges=fgr, sourcePaths=files, parsedPath=parsedDir)
    
    # ==========================================
    # 3. Define parsing parameters and parse source files
    # ==========================================
    dat <- fread(files[1], skip="[Data]")
    
    select_columns <- match(c("SNP Name", "Allele1 - AB", "Allele2 - AB",
                              "Log R Ratio", "B Allele Freq"), names(dat))
    
    index_genome <- match(names(fgr), dat[["SNP Name"]])
    
    scan_params <- CopyNumScanParams(index_genome=index_genome,
                                     select=select_columns,
                                     cnvar="Log R Ratio",
                                     bafvar="B Allele Freq",
                                     gtvar=c("Allele1 - AB", "Allele2 - AB"))
    
    # Parse the source files
    parseSourceFile(views[, 1], scan_params)
    invisible(sapply(views, parseSourceFile, param=scan_params))
    
    # ==========================================
    # 4. Define pedigree structure and map sample IDs
    # ==========================================
    # Read sample metadata mapping file names to individual IDs
    sample_info <- read.csv("sample_data.csv", stringsAsFactors=FALSE)
    
    # Clean up whitespace and map column names
    colnames(sample_info) <- trimws(colnames(sample_info))
    sample_info\$IndividualID <- gsub(" ", "", sample_info\$IndividualID)
    sample_info\$FatherID <- gsub(" ", "", sample_info\$FatherID)
    sample_info\$MotherID <- gsub(" ", "", sample_info\$MotherID)
    sample_info\$FamilyID <- gsub(" ", "", sample_info\$FamilyID)
    
    # Map colnames of views to Individual IDs
    sample_files_clean <- gsub(".txt", "", sample_info\$File)
    ind_id <- setNames(sample_info\$IndividualID, sample_files_clean)
    views_cols_clean <- gsub(".txt", "", colnames(views))
    colnames(views) <- ind_id[views_cols_clean]
    
    # Dynamically build ParentOffspringList from sample metadata
    families <- unique(sample_info\$FamilyID)
    ped_list_elements <- list()
    for (fam in families) {
      fam_data <- sample_info[sample_info\$FamilyID == fam, ]
      offspring_rows <- fam_data[fam_data\$FatherID != "" & fam_data\$MotherID != "" & 
                                 !is.na(fam_data\$FatherID) & !is.na(fam_data\$MotherID), ]
      if (nrow(offspring_rows) > 0) {
        for (i in 1:nrow(offspring_rows)) {
          off_id <- offspring_rows\$IndividualID[i]
          fat_id <- offspring_rows\$FatherID[i]
          mot_id <- offspring_rows\$MotherID[i]
          
          ped_list_elements[[paste0(fam, "_", off_id)]] <- ParentOffspring(
            id = fam,
            father = fat_id,
            mother = mot_id,
            offspring = off_id,
            parsedPath = parsedPath(views)
          )
        }
      }
    }
    ped_list <- ParentOffspringList(pedigrees=ped_list_elements)
    
    # ==========================================
    # 5. Construct a MinDistExperiment object
    # ==========================================
    # Use the first pedigree in the list for analysis
    ped_to_use <- ped_list[[1]]
    me <- MinDistExperiment(views, pedigree=ped_to_use)
    
    # ==========================================
    # 6. Segment the minimum distance and offspring log R ratios
    # ==========================================
    segment_params <- DNAcopyParam(alpha=0.01)
    params <- MinDistParam(dnacopy=segment_params)
    
    mdgr <- segment2(me, params)
    
    # ==========================================
    # 7. Calculate posterior probabilities and call trio states
    # ==========================================
    md_g <- MAP2(me, mdgr, params)
    
    # Save the raw called object
    saveRDS(md_g, "md_g_raw.rds")
    
    # ==========================================
    # 8. Filter called CNVs
    # ==========================================
    filter_param <- FilterParamMD()
    default_cnvs <- cnvFilter(md_g, filter_param)
    write.csv(as.data.frame(default_cnvs), "default_filtered_cnvs.csv", row.names=FALSE)
    
    # Extract de novo hemizygous and homozygous calls
    denovo_hemi <- denovoHemizygous(md_g)
    write.csv(as.data.frame(denovo_hemi), "denovo_hemizygous_cnvs.csv", row.names=FALSE)
    
    denovo_homo <- denovoHomozygous(md_g)
    write.csv(as.data.frame(denovo_homo), "denovo_homozygous_cnvs.csv", row.names=FALSE)
    
    # Custom filter for specific states on the first available chromosome
    seqs_present <- as.character(unique(seqnames(md_g)))
    seq_to_filter <- if ("chr22" %in% seqs_present) "chr22" else seqs_present[1]
    
    select_cnv <- FilterParamMD(state=c("220", "221", "223"), seqnames=seq_to_filter)
    cnvs <- cnvFilter(md_g, select_cnv)
    write.csv(as.data.frame(cnvs), "selected_states_cnvs.csv", row.names=FALSE)
    
    # ==========================================
    # 9. Merge adjacent segments and plot results
    # ==========================================
    pdf("denovo_cnv_visualization.pdf", width=11, height=8.5)
    
    if (length(denovoHemizygous(md_g)) > 0) {
      g2 <- reduce(denovoHemizygous(md_g), min.gapwidth=500e3)
      post <- MAP2(me, g2, params)
      g2 <- denovoHemizygous(post)
      
      if (length(g2) > 0) {
        vps <- pedigreeViewports()
        grid.params <- HmmTrellisParam()
        p <- plotDenovo(me, g2, grid.params)
        pedigreeGrid(g=g2, vps=vps, figs=p)
      } else {
        grid.newpage()
        grid.text("No de novo hemizygous CNVs remaining after merging and recalculation.")
      }
    } else {
      grid.newpage()
      grid.text("No de novo hemizygous CNVs detected to plot.")
    }
    
    dev.off()
    
    # Save final experiment and results objects
    saveRDS(me, "MinDistExperiment_object.rds")
    saveRDS(md_g, "MAP2_called_object.rds")
    
    message("Trio de novo CNV calling pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MINIMUMDISTANCE_TRIO_DENOVO_CNV_CALLING":',
        paste0('    MinimumDistance: ', as.character(packageVersion('MinimumDistance')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trio_denovo_cnv_calling.csv versions.yml
    """
}

workflow BIOC_MINIMUMDISTANCE_TRIO_DENOVO_CNV_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SNP_info.csv, FinalReport*.txt, sample_data.csv ] ]

    main:
    BIOC_MINIMUMDISTANCE_TRIO_DENOVO_CNV_CALLING(ch_input)

    emit:
    tables   = BIOC_MINIMUMDISTANCE_TRIO_DENOVO_CNV_CALLING.out.tables
    plots    = BIOC_MINIMUMDISTANCE_TRIO_DENOVO_CNV_CALLING.out.plots
    objects  = BIOC_MINIMUMDISTANCE_TRIO_DENOVO_CNV_CALLING.out.objects
    versions = BIOC_MINIMUMDISTANCE_TRIO_DENOVO_CNV_CALLING.out.versions
}
