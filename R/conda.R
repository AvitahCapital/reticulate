#' Interface to conda
#'
#' R functions for managing Python [conda
#' environments](https://conda.io/docs/user-guide/tasks/manage-environments.html).
#'
#' @param envname Name of conda environment
#'
#' @param conda Path to conda executable (or "auto" to find conda using the
#'   PATH and other conventional install locations).
#'
#' @param packages Character vector with package names to install or remove.
#'
#' @param pip `TRUE` to use pip (defaults to `FALSE`)
#'
#' @param ... Optional arguments, reserved for future expansion.
#'
#' @return `conda_list()` returns a data frame with the names and paths to the
#'   respective python binaries of available environments. `conda_create()`
#'   returns the Path to the python binary of the created environment.
#'   `conda_binary()` returns the location of the main conda binary or `NULL`
#'   if none can be found.
#'
#' @name conda-tools
#'
#' @importFrom jsonlite fromJSON
#'
#' @export
conda_list <- function(conda = "auto") {

  # resolve conda binary
  conda <- conda_binary(conda)

  # list envs -- discard stderr as Anaconda may emit warnings that can
  # otherwise be ignored; see e.g. https://github.com/rstudio/reticulate/issues/474
  conda_envs <- suppressWarnings(
    system2(conda, args = c("info", "--json"), stdout = TRUE, stderr = FALSE)
  )

  # check for error
  status <- attr(conda_envs, "status")
  if (!is.null(status)) {
    # show warning if conda_diagnostics are enabled
    if (getOption("reticulate.conda_diagnostics", default = FALSE)) {
      errmsg <- attr(status, "errmsg")
      warning("Error ", status, " occurred running ", conda, " ", errmsg)
    }
    # return empty data frame
    return(data.frame(
      name = character(),
      python = character(),
      stringsAsFactors = FALSE)
    )
  }

  # strip out anaconda cloud prefix (not valid json)
  if (length(conda_envs) > 0 && grepl("Anaconda Cloud", conda_envs[[1]], fixed = TRUE))
    conda_envs <- conda_envs[-1]

  # convert to json
  conda_envs <- fromJSON(conda_envs)$envs
  conda_envs <- Filter(file.exists, conda_envs)

  # return an empty data.frame when no envs are found
  if (length(conda_envs) == 0L) {
    return(data.frame(
      name = character(),
      python = character(),
      stringsAsFactors = FALSE)
    )
  }

  # normalize and remove duplicates (seems necessary on Windows as Anaconda
  # may report both short-path and long-path versions of the same environment)
  conda_envs <- unique(normalizePath(conda_envs))

  # build data frame
  name <- character()
  python <- character()
  for (conda_env in conda_envs) {
    name <- c(name, basename(conda_env))
    conda_env_dir <- conda_env
    if (!is_windows())
      conda_env_dir <- file.path(conda_env_dir, "bin")
    conda_env_python <- file.path(conda_env_dir, "python")
    if (is_windows()) {
      conda_env_python <- paste0(conda_env_python, ".exe")
      conda_env_python <- normalizePath(conda_env_python)
    }
    python <- c(python, conda_env_python)

  }
  data.frame(name = name, python = python, stringsAsFactors = FALSE)
}



#' @rdname conda-tools
#' @export
conda_create <- function(envname = NULL, packages = "python", conda = "auto") {

  # resolve conda binary
  conda <- conda_binary(conda)

  # resolve environment name
  envname <- condaenv_resolve(envname)

  # create the environment
  args <- conda_args("create", envname, packages)
  result <- system2(conda, shQuote(args))
  if (result != 0L) {
    stop("Error ", result, " occurred creating conda environment ", envname,
         call. = FALSE)
  }

  # return the path to the python binary
  conda_python(envname = envname, conda = conda)

}

#' @rdname conda-tools
#' @export
conda_remove <- function(envname, packages = NULL, conda = "auto") {

  # resolve conda binary
  conda <- conda_binary(conda)

  # resolve environment name
  envname <- condaenv_resolve(envname)

  # no packages means everything
  if (is.null(packages))
    packages <- "--all"

  # remove packges (or the entire environment)
  args <- conda_args("remove", envname, packages)
  result <- system2(conda, shQuote(args))
  if (result != 0L) {
    stop("Error ", result, " occurred removing conda environment ", envname,
         call. = FALSE)
  }
}

#' @param forge Include the [Conda Forge](https://conda-forge.org/) repository.
#' @param pip_ignore_installed Ignore installed versions when using pip. This is `TRUE` by default
#'   so that specific package versions can be installed even if they are downgrades. The `FALSE`
#'   option is useful for situations where you don't want a pip install to attempt an overwrite
#'   of a conda binary package (e.g. SciPy on Windows which is very difficult to install via
#'   pip due to compilation requirements).
#'
#' @rdname conda-tools
#'
#' @keywords internal
#'
#' @export
conda_install <- function(envname = NULL,
                          packages,
                          forge = TRUE,
                          pip = FALSE,
                          pip_ignore_installed = TRUE,
                          conda = "auto",
                          python_version = NULL,
                          ...)
{
  # resolve conda binary
  conda <- conda_binary(conda)

  # resolve environment name
  envname <- condaenv_resolve(envname)

  # honor request for specific Python
  python_package <- NULL
  if (!is.null(python_version))
    python_package <- paste("python", python_version, sep = "=")

  # check if the environment exists, and create it on demand if needed.
  # if the environment does already exist, but a version of Python was
  # requested, attempt to install that in the existing environment
  # (effectively re-creating it if the Python version differs)
  python <- tryCatch(conda_python(envname = envname, conda = conda), error = identity)
  if (inherits(python, "error") || !file.exists(python)) {
    conda_create(envname, packages = python_package, conda = conda)
  } else if (!is.null(python_package)) {
    args <- conda_args("install", envname, python_package)
    status <- system2(conda, shQuote(args))
    if (status != 0L) {
      fmt <- "installation of '%s' into environment '%s' failed [error code %i]"
      msg <- sprintf(fmt, python_package, envname, status)
      stop(msg, call. = FALSE)
    }
  }

  if (pip) {
    # use pip package manager
    condaenv_bin <- function(bin) path.expand(file.path(dirname(conda), bin))
    cmd <- sprintf("%s%s %s && pip install --upgrade %s %s%s",
                   ifelse(is_windows(), "", ifelse(is_osx(), "source ", "/bin/bash -c \"source ")),
                   shQuote(path.expand(condaenv_bin("activate"))),
                   envname,
                   ifelse(pip_ignore_installed, "--ignore-installed", ""),
                   paste(shQuote(packages), collapse = " "),
                   ifelse(is_windows(), "", ifelse(is_osx(), "", "\"")))
    result <- system(cmd)

  } else {
    # use conda
    args <- conda_args("install", envname)
    if (forge)
      args <- c(args, "-c", "conda-forge")
    args <- c(args, python_package, packages)
    result <- system2(conda, shQuote(args))
  }

  # check for errors
  if (result != 0L) {
    stop("Error ", result, " occurred installing packages into conda environment ",
         envname, call. = FALSE)
  }

  invisible(NULL)
}


#' @rdname conda-tools
#' @export
conda_binary <- function(conda = "auto") {

  # automatic lookup if requested
  if (identical(conda, "auto")) {
    conda <- find_conda()
    if (is.null(conda))
      stop("Unable to find conda binary. Is Anaconda installed?", call. = FALSE)
    conda <- conda[[1]]
  }

  # if the user has requested a conda binary in the 'condabin' folder,
  # try to find and use its sibling in the 'bin' folder instead as
  # we rely on other tools typically bundled in the 'bin' folder
  # https://github.com/rstudio/keras/issues/691
  if (!is_windows()) {
    altpath <- file.path(dirname(conda), "../bin/conda")
    if (file.exists(altpath))
      return(normalizePath(altpath, winslash = "/", mustWork = TRUE))
  } else {
    # on Windows it's preferable to conda.bat located in the 'condabin'
    # folder. if the user passed the path to a 'Scripts/conda.exe' we will
    # try to find the 'conda.bat'.
    altpath <- file.path(dirname(conda), "../condabin/conda.bat")
    if (file.exists(altpath))
      return(normalizePath(altpath, winslash = "/", mustWork = TRUE))
  }

  # validate existence
  if (!file.exists(conda))
    stop("Specified conda binary '", conda, "' does not exist.", call. = FALSE)

  # return conda
  conda
}


#' @rdname conda-tools
#' @export
conda_version <- function(conda = "auto") {
  conda_bin <- conda_binary(conda)
  system2(conda_bin, "--version", stdout = TRUE)
}

#' @rdname conda-tools
#' @export
conda_python <- function(envname = NULL, conda = "auto") {

  # resolve envname
  envname <- condaenv_resolve(envname)

  # for fully-qualified paths, construct path explicitly
  if (grepl("[/\\\\]", envname)) {
    suffix <- if (is_windows()) "python.exe" else "bin/python"
    path <- file.path(envname, suffix)
    if (file.exists(path))
      return(path)

    fmt <- "no conda environment exists at path '%s'"
    stop(sprintf(fmt, envname))
  }

  # otherwise, list conda environments and try to find it
  conda_envs <- conda_list(conda = conda)
  env <- subset(conda_envs, conda_envs$name == envname)
  if (nrow(env) > 0)
    path.expand(env$python[[1]])
  else
    stop("conda environment ", envname, " not found")
}



find_conda <- function() {
  conda <- Sys.which("conda")
  if (!nzchar(conda)) {
    conda_locations <- c(
      miniconda_conda(),
      path.expand("~/anaconda/bin/conda"),
      path.expand("~/anaconda2/bin/conda"),
      path.expand("~/anaconda3/bin/conda"),
      path.expand("~/anaconda4/bin/conda"),
      path.expand("~/miniconda/bin/conda"),
      path.expand("~/miniconda2/bin/conda"),
      path.expand("~/miniconda3/bin/conda"),
      path.expand("~/miniconda4/bin/conda"),
      path.expand("/anaconda/bin/conda"),
      path.expand("/anaconda2/bin/conda"),
      path.expand("/anaconda3/bin/conda"),
      path.expand("/anaconda4/bin/conda"),
      path.expand("/miniconda/bin/conda"),
      path.expand("/miniconda2/bin/conda"),
      path.expand("/miniconda3/bin/conda"),
      path.expand("/miniconda4/bin/conda")
    )
    if (is_windows()) {
      anaconda_versions <- windows_registry_anaconda_versions()
      anaconda_versions <- subset(anaconda_versions, anaconda_versions$arch == .Platform$r_arch)
      if (nrow(anaconda_versions) > 0) {
        conda_scripts <- utils::shortPathName(
          file.path(anaconda_versions$install_path, "Scripts", "conda.exe")
        )
        conda_bats <- utils::shortPathName(
          file.path(anaconda_versions$install_path, "condabin", "conda.bat")
        )
        conda_locations <- c(conda_locations, conda_bats, conda_scripts)
      }
    }
    conda_locations <- conda_locations[file.exists(conda_locations)]
    if (length(conda_locations) > 0)
      conda_locations
    else
      NULL
  } else {
    conda
  }
}

condaenv_resolve <- function(envname = NULL) {

  python_environment_resolve(
    envname = envname,
    resolve = identity
  )

}

condaenv_exists <- function(envname = NULL, conda = "auto") {

  # check that conda is installed
  condabin <- tryCatch(conda_binary(conda = conda), error = identity)
  if (inherits(condabin, "error"))
    return(FALSE)

  # check that the environment exists
  python <- tryCatch(conda_python(envname, conda = conda), error = identity)
  if (inherits(python, "error"))
    return(FALSE)

  # validate the Python binary exists
  file.exists(python)

}

conda_args <- function(action, envname = NULL, ...) {

  envname <- condaenv_resolve(envname)

  # use '--prefix' as opposed to '--name' if envname looks like a path
  args <- c(action, "--yes")
  if (grepl("[/\\]", envname))
    args <- c(args, "--prefix", envname, ...)
  else
    args <- c(args, "--name", envname, ...)

  args

}

is_condaenv <- function(dir) {
  file.exists(file.path(dir, "conda-meta"))
}

conda_list_packages <- function(envname = NULL, conda = "auto", no_pip = TRUE) {
  
  conda <- conda_binary(conda)
  envname <- condaenv_resolve(envname)

  # create the environment
  args <- c("list")
  if (grepl("[/\\]", envname)) {
    args <- c(args, "--prefix", envname)
  } else {
    args <- c(args, "--name", envname)
  }
  
  if (no_pip)
    args <- c(args, "--no-pip")
  
  args <- c(args, "--json")
  
  output <- system2(conda, shQuote(args), stdout = TRUE)
  status <- attr(output, "status") %||% 0L
  if (status != 0L) {
    fmt <- "error listing conda environment [status code %i]"
    stopf(fmt, status)
  }
  
  parsed <- jsonlite::fromJSON(output)
  data.frame(
    package = parsed$name,
    version = parsed$version,
    stringsAsFactors = FALSE
  )
  
}
