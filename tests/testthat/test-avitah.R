context("avitah")

test_that("we can convert a 0 row dataframe from python to r", {
  skip_if_no_python()

  glue <- import('glue')

  some_rows <- glue$select_interconnector(from_zone='TTF', to_zone='NBP')
  expect_gt(nrow(some_rows), 0)
  expect_equal(some_rows$from_zone[1], 'TTF')
  expect_equal(some_rows$to_zone[1], 'NBP')
  expect_true(class(some_rows$DateTime)[1] =='POSIXct')

  zero_rows <- glue$select_interconnector(from_zone='random region')
  expect_equal(nrow(zero_rows), 0)
})

test_that("date column is converted", {
  skip_if_no_python()

  pd <- import('pandas', convert=FALSE)
  pydf <- pd$DataFrame(list(date=pd$DatetimeIndex(pd$date_range('2016-01-01', '2016-01-03'))$date))
  df <- py_to_r(pydf)
  expect_true(class(df$date)[1] == 'Date')
})
