# =====================================================================
#  tests/test_ch01.R
#  Enough for the Worst Year: Chapter 1 tests
#
#  Hand-worked checks of the balance sheet logic, plus checks that the
#  cleaning removes exactly the planted problems.
#
#  Run from the project folder:  testthat::test_file("tests/test_ch01.R")
# =====================================================================

library(testthat)

# testthat may run from inside tests/, so step up to the project folder
if (basename(getwd()) == "tests") setwd("..")
invisible(capture.output(source("r/ch01_balance_sheet.R")))

amt <- function(bs, item) bs$amount[bs$item == item]

# ---- A tiny Northgate, small enough to check by hand -----------------
#  Policy A: $1,460, expires 2027-04-01, in force  -> 91 days left
#            unearned = 1,460 x 91/365 = 364.00
#  Policy B: $1,095, expired 2026-11-30            -> unearned 0
#  Policy C: $2,190, cancelled 2026-08-29          -> unearned 0
#  Policy D: $730, expires 2027-12-31, in force    -> 365 days left
#            unearned = 730 x 365/365 = 730.00
#  Total unearned premium = 1,094.00
toy <- list(
  policies = data.frame(
    annual_premium = c(1460, 1095, 2190, 730),
    exp_date    = as.Date(c("2027-04-01", "2026-11-30", "2027-06-30", "2027-12-31")),
    cancel_date = as.Date(c(NA, NA, "2026-08-29", NA), format = "%Y-%m-%d")
  ),
  claims = data.frame(case_reserve = c(10000, 0)),
  assets = data.frame(
    asset_class  = c("Bond", "Equity", "Cash"),
    market_value = c(20000, 5000, 1000),
    stringsAsFactors = FALSE
  )
)
toy_bs <- build_balance_sheet(toy)

test_that("unearned premium counts only the days of cover still to come", {
  expect_equal(amt(toy_bs, "Unearned premium"), 1094)
})

test_that("IBNR is 15% of case reserves", {
  expect_equal(amt(toy_bs, "Unpaid claims: IBNR provision"), 1500)
})

test_that("the tiny balance sheet adds up", {
  # Assets 20,000 + 5,000 + 1,000 = 26,000
  # Liabilities 1,094 + 10,000 + 1,500 = 12,594
  expect_equal(amt(toy_bs, "Total assets"), 26000)
  expect_equal(amt(toy_bs, "Total liabilities"), 12594)
  expect_equal(amt(toy_bs, "Capital available"), 13406)
})

# ---- The real Northgate data -----------------------------------------
ng    <- clean_northgate()
ng_bs <- build_balance_sheet(ng)

test_that("cleaning removes exactly the three planted problems", {
  expect_equal(ng$n_pol_raw - nrow(ng$policies), 100)                    # duplicate policies
  expect_equal(nrow(ng$policies), 40000)
  expect_equal(ng$n_clm_raw - nrow(ng$claims) - nrow(ng$orphans), 298)   # duplicate claims
  expect_equal(nrow(ng$orphans), 10)                                     # no matching policy
  expect_equal(nrow(ng$claims), 3695)
})

test_that("case reserves reconcile from the raw file to the clean total", {
  raw  <- read_data("raw_claims.csv")
  dups <- raw[duplicated(raw$claim_id), ]
  expect_equal(sum(raw$case_reserve), 14863250)
  expect_equal(sum(dups$case_reserve), 816075)
  expect_equal(sum(ng$orphans$case_reserve), 50000)                      # 10 x 5,000
  expect_equal(sum(ng$claims$case_reserve), 14863250 - 816075 - 50000)
})

test_that("a bond whose coupon equals its yield is priced at par", {
  # Asset 3: Federal bond, face 1,200,000, coupon 3.5%, yield 3.5%
  expect_equal(ng$assets$market_value[ng$assets$asset_id == 3], 1200000)
})

test_that("Northgate's balance sheet matches the hand-built totals", {
  expect_equal(amt(ng_bs, "Total assets"), 42844424.82)
  expect_equal(amt(ng_bs, "Total liabilities"), 29924884.62)
  expect_equal(amt(ng_bs, "Capital available"), 12919540.20)
  expect_equal(amt(ng_bs, "Capital available"),
               amt(ng_bs, "Total assets") - amt(ng_bs, "Total liabilities"))
})