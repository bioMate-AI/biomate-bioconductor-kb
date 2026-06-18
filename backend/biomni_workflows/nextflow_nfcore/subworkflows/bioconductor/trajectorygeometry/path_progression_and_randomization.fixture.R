# Fixture for path_progression_and_randomization.nf — needs:
#   straight_path: a matrix of points along a directed path through PCA space
#   crooked_path:  a matrix of points along a non-directed (random-walk) path
#   oscillation:   a numeric vector (oscillation test input — TrajectoryGeometry
#                  uses these for randomization-vs-progression comparison)
#
# These mirror the inputs the package's path-randomization tutorial uses;
# we synthesize them directly (no TrajectoryGeometry call needed).

set.seed(11)
n_steps <- 100
n_dims  <- 5

# straight_path: steady drift along dim 1, small noise on others
straight_path <- matrix(rnorm(n_steps * n_dims, sd = 0.2),
                        nrow = n_steps, ncol = n_dims,
                        dimnames = list(NULL, sprintf("PC%d", seq_len(n_dims))))
straight_path[, 1] <- straight_path[, 1] + seq(0, 5, length.out = n_steps)

# crooked_path: a random walk in PCA space (no net drift)
crooked_path <- matrix(0, nrow = n_steps, ncol = n_dims,
                       dimnames = list(NULL, sprintf("PC%d", seq_len(n_dims))))
for (i in 2:n_steps) {
  crooked_path[i, ] <- crooked_path[i - 1, ] + rnorm(n_dims, sd = 0.5)
}

# oscillation: noisy sine wave — a 1-D progression that the randomization
# test should detect as non-monotonic.
oscillation <- sin(seq(0, 4 * pi, length.out = n_steps)) +
                 rnorm(n_steps, sd = 0.2)

saveRDS(straight_path, "straight_path.rds")
saveRDS(crooked_path,  "crooked_path.rds")
saveRDS(oscillation,   "oscillation.rds")

cat("Fixture wrote:",
    paste(list.files(pattern = "\\.rds$"), collapse = ", "),
    "\n")
