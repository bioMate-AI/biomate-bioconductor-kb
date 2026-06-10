library(DropletUtils)
library(Matrix)

set.seed(0)
my.counts <- DropletUtils:::simCounts()

saveRDS(my.counts, "my.counts")