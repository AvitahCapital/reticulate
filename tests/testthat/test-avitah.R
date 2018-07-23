context("avitah")

test_that("we can convert a 0 row dataframe from python to r", {
  skip_if_no_python()

  glue <- import('glue')
  zero_rows <- glue$select_interconnector(from_zone='random region')
  expect_equal(nrow(zero_rows), 0)
})


