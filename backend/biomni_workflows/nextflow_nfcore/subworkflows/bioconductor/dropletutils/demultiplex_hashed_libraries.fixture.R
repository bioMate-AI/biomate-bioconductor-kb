library(DropletUtils)

set.seed(10000)
# Simulating empty droplets:
nbarcodes <- 1000
nhto <- 10
y <- matrix(rpois(nbarcodes*nhto, 20), nrow=nhto)

# Simulating cells:
ncells <- 100
true.sample <- sample(nhto, ncells, replace=TRUE)
y[cbind(true.sample, seq_len(ncells))] <- 1000

# Simulating doublets:
ndoub <- ncells/10
next.sample <- (true.sample[1:ndoub] + 1) %% nrow(y)
next.sample[next.sample==0] <- nrow(y)
y[cbind(next.sample, seq_len(ndoub))] <- 500

# Add row and column names for compatibility with CSV/TSV reading logic
rownames(y) <- paste0("HTO", seq_len(nrow(y)))
colnames(y) <- paste0("Barcode", seq_len(ncol(y)))

saveRDS(y, "y.rds")