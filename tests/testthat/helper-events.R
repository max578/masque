# Simulated illness-death table: recurrence then death, with censoring. A row
# without a recurrence carries time_rec == time_death.
.events_fixture <- function(n = 900L, seed = 11L) {
  withr::with_seed(seed, {
    arm <- rep(c("A", "B"), length.out = n)
    t_rec <- stats::rexp(n, ifelse(arm == "A", 1 / 900, 1 / 1400))
    t_death <- stats::rexp(n, 1 / 2500)
    cens <- stats::runif(n, 30, 3000)
    status_death <- as.integer(t_death <= cens)
    time_death <- round(pmin(t_death, cens))
    status_rec <- as.integer(t_rec < pmin(t_death, cens))
    time_rec <- ifelse(status_rec == 1L, pmin(round(t_rec), time_death),
      time_death
    )
    data.frame(
      id = sprintf("P%04d", seq_len(n)),
      arm = arm,
      age = round(stats::rnorm(n, 62, 9)),
      time_rec = as.numeric(time_rec),
      status_rec = status_rec,
      time_death = as.numeric(time_death),
      status_death = status_death,
      stringsAsFactors = FALSE
    )
  })
}

.events_roles <- function(df) {
  r <- propose_roles(df)
  r <- set_role(r, "arm", role = "treatment")
  for (cn in c("time_rec", "status_rec", "time_death", "status_death")) {
    r <- set_role(r, cn, role = "outcome", action = "scramble")
  }
  r
}

.events_spec <- list(list(
  time = c("time_rec", "time_death"),
  status = c("status_rec", "status_death")
))

.pattern_of <- function(d) paste(d$status_rec, d$status_death, sep = "/")
