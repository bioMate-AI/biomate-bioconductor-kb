library(ramwas)
library(filematrix)

# 1. Reproduce the vignette's data-preparation code
dr = paste0(tempdir(), "/simulated_project")
dir.create(dr, showWarnings = FALSE, recursive = TRUE)

ramwas0createArtificialData(
  dir = dr,
  nsamples = 20,
  nreads = 100e3,
  ncpgs = 25e3,
  threads = 2
)

param = ramwasParameters(
  dirproject = dr,
  dirbam = "bams",
  filebamlist = "bam_list.txt",
  filecpgset = "Simulated_chromosome.rds",
  cputhreads = 2,
  scoretag = "MAPQ",
  minscore = 4,
  minfragmentsize = 50,
  maxfragmentsize = 250,
  minavgcpgcoverage = 0.3,
  minnonzerosamples = 0.3,
  filecovariates = "covariates.txt",
  modelcovariates = NULL,
  modeloutcome = "age",
  modelPCs = 0,
  toppvthreshold = 1e-5
)

# Run the pipeline steps to generate the normalized coverage matrix and CpG locations
ramwas1scanBams(param)
ramwas2collectqc(param)
ramwas3normalizedCoverage(param)

pfull = parameterPreprocess(param)
cov_dir = pfull$dircoveragenorm

# 2. Serialize objects to EACH declared input file in the working directory

# Copy Coverage filematrix
for (f in list.files(cov_dir, pattern="^Coverage\\.", full.names=TRUE)) {
  file.copy(f, basename(f), overwrite = TRUE)
}

# Copy CpG_locations filematrix
for (f in list.files(cov_dir, pattern="^CpG_locations\\.", full.names=TRUE)) {
  file.copy(f, basename(f), overwrite = TRUE)
}

# Copy CpG_chromosome_names.txt (part of the CpG_locations filematrix structure)
if (file.exists(file.path(cov_dir, "CpG_chromosome_names.txt"))) {
  file.copy(file.path(cov_dir, "CpG_chromosome_names.txt"), "CpG_chromosome_names.txt", overwrite = TRUE)
}

# Copy covariates
file.copy(file.path(dr, "covariates.txt"), "covariates.txt", overwrite = TRUE)

# Create SNPs filematrix matching Coverage dimensions
cov_fm = fm.open("Coverage", readonly=TRUE)
n_samples = nrow(cov_fm)
n_cpgs = ncol(cov_fm)
close(cov_fm)

# Clean up any existing SNPs filematrix to avoid append issues
for (f in list.files(".", pattern="^SNPs\\.")) {
  file.remove(f)
}

# Generate synthetic genotype dosages (0, 1, 2) matching the coverage matrix dimensions
snp_fm = fm.create("SNPs", nrow=n_samples, ncol=n_cpgs, type="integer")
snp_fm[,] = matrix(sample(0:2, n_samples * n_cpgs, replace=TRUE), nrow=n_samples, ncol=n_cpgs)
close(snp_fm)