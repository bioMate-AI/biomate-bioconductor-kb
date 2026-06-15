# Real user-style input for wpm::convertESet -> wrapperWPM:
#   my_MSnSet_object - an ExpressionSet a user feeds WPM to randomise samples
#       across a well plate (this is the "expressionset_to_plate_map" workflow;
#       wpm::convertESet accepts ExpressionSet or MSnSet identically — it only
#       reads Biobase::pData). The phenoData carries an `Environment` grouping
#       factor (the experimental block/condition the workflow groups on), exactly
#       as the wpm vignette's command-line ExpressionSet/MSnSet example. The
#       intensities are synthetic (the user's own measurements); the structure
#       (sample names in colnames, `Environment` grouping factor in pData) is the
#       real contract wpm::convertESet(object, "Environment") expects.
# Built with Biobase only (ships in the wpm biocontainer) — no MSnbase needed.
suppressPackageStartupMessages({
  library(Biobase)
})

set.seed(42)

# A realistic small design: 12 samples in 3 experimental environments.
sample_names <- sprintf("S%02d", seq_len(12))
n_feat <- 80
M <- matrix(rnorm(n_feat * length(sample_names), mean = 20, sd = 3),
            nrow = n_feat, ncol = length(sample_names))
colnames(M) <- sample_names
rownames(M) <- sprintf("protein_%03d", seq_len(n_feat))

pd <- data.frame(
  Environment = factor(rep_len(c("ctrl", "treatA", "treatB"), length(sample_names))),
  Category    = factor(rep_len(c("batch1", "batch2"), length(sample_names))),
  row.names   = sample_names
)

my_MSnSet_object <- ExpressionSet(
  assayData = M,
  phenoData = AnnotatedDataFrame(pd))

saveRDS(my_MSnSet_object, "my_MSnSet_object")
saveRDS(my_MSnSet_object, "my_MSnSet_object.rds")
