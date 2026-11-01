# =====================================================================
#  r/ch01_balance_sheet.R
#  Enough for the Worst Year: Chapter 1 cross-check in R
#
#  Rebuilds Northgate's balance sheet from the raw CSV files, entirely
#  independently of SAS, then compares it with SAS's balance_sheet.csv.
#  Every line must match to the cent.
#
#  Uses base R only (no packages needed).
#  Run from the project folder:  source("r/ch01_balance_sheet.R")
# =====================================================================

valdate   <- as.Date("2026-12-31")
ibnr_load <- 0.15   # illustrative: IBNR held at 15% of case reserves

# ---- Read a file from the data/ folder ----
read_data <- function(file) {
  read.csv(file.path("data", file), stringsAsFactors = FALSE)
}

# ---- Clean the raw files: the same three fixes as SAS, written independently ----
clean_northgate <- function() {
  pol <- read_data("raw_policies.csv")
  clm <- read_data("raw_claims.csv")
  ast <- read_data("raw_assets.csv")

  pol$exp_date    <- as.Date(as.character(pol$exp_date),    format = "%Y-%m-%d")
  pol$cancel_date <- as.Date(as.character(pol$cancel_date), format = "%Y-%m-%d")

  # Problem 1: duplicate policy records
  policies <- pol[!duplicated(pol$policy_id), ]

  # Problem 2: duplicate claim records
  dedup <- clm[!duplicated(clm$claim_id), ]

  # Problem 3: claims with no matching policy
  has_policy <- dedup$policy_id %in% policies$policy_id

  list(policies  = policies,
       claims    = dedup[has_policy, ],
       orphans   = dedup[!has_policy, ],
       assets    = ast,
       n_pol_raw = nrow(pol),
       n_clm_raw = nrow(clm))
}

# ---- Build the balance sheet at the valuation date ----
build_balance_sheet <- function(d) {
  p        <- d$policies
  in_force <- is.na(p$cancel_date) & p$exp_date > valdate

  # Unearned premium: premium for the days of cover still to come
  upr <- sum(p$annual_premium[in_force] *
             as.numeric(p$exp_date[in_force] - valdate) / 365)

  case_res <- sum(d$claims$case_reserve)

  a        <- d$assets
  bonds    <- round(sum(a$market_value[a$asset_class == "Bond"]),   2)
  equities <- round(sum(a$market_value[a$asset_class == "Equity"]), 2)
  cash     <- round(sum(a$market_value[a$asset_class == "Cash"]),   2)
  total_a  <- round(bonds + equities + cash, 2)

  upr_r    <- round(upr, 2)
  case_r   <- round(case_res, 2)
  ibnr_r   <- round(ibnr_load * case_res, 2)
  total_l  <- round(upr_r + case_r + ibnr_r, 2)

  capital  <- round(total_a - total_l, 2)

  data.frame(
    item   = c("Bonds", "Equities", "Cash", "Total assets",
               "Unearned premium", "Unpaid claims: case reserves",
               "Unpaid claims: IBNR provision", "Total liabilities",
               "Capital available"),
    amount = c(bonds, equities, cash, total_a,
               upr_r, case_r, ibnr_r, total_l,
               capital),
    stringsAsFactors = FALSE
  )
}

# ---- Compare R's balance sheet with SAS's ----
compare_with_sas <- function(bs_r) {
  sas        <- read_data("balance_sheet.csv")
  sas$item   <- trimws(sas$item)
  sas$amount <- as.numeric(gsub(",", "", as.character(sas$amount)))

  out <- data.frame(
    item       = bs_r$item,
    R          = bs_r$amount,
    SAS        = sas$amount[match(bs_r$item, sas$item)],
    stringsAsFactors = FALSE
  )
  out$difference <- round(out$R - out$SAS, 2)
  out
}

# =====================================================================
#  Run the cross-check
# =====================================================================
northgate <- clean_northgate()

cat("\nCleaning (R)\n")
cat("  Policy records received:        ", northgate$n_pol_raw, "\n")
cat("  Clean policies:                 ", nrow(northgate$policies), "\n")
cat("  Claim records received:         ", northgate$n_clm_raw, "\n")
cat("  Claims with no matching policy: ", nrow(northgate$orphans), "\n")
cat("  Clean claims:                   ", nrow(northgate$claims), "\n\n")

bs_r  <- build_balance_sheet(northgate)
check <- compare_with_sas(bs_r)

print(format(check, big.mark = ",", nsmall = 2), row.names = FALSE)

if (all(!is.na(check$SAS)) && all(abs(check$difference) < 0.005)) {
  cat("\nAll", nrow(check), "balance sheet lines match SAS to the cent.\n")
} else {
  stop("R and SAS disagree: see the difference column above.")
}