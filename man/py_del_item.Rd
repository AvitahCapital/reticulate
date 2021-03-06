% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/python.R
\name{py_del_item}
\alias{py_del_item}
\title{Delete / remove an item from a Python object}
\usage{
py_del_item(x, name)
}
\arguments{
\item{x}{A Python object.}

\item{name}{The item name.}
}
\value{
The (mutated) object \code{x}, invisibly.
}
\description{
Delete an item associated with a Python object, as
through its \verb{__delitem__} method.
}
\seealso{
Other item-related APIs: \code{\link{py_get_item}()},
  \code{\link{py_set_item}()}
}
\concept{item-related APIs}
