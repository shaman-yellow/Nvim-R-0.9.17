
nvim.edit <- function(name, file, title) {
    if (file != "")
        stop("Feature not implemented. Use nvim to edit files.")
    if (is.null(name))
        stop("Feature not implemented. Use nvim to create R objects from scratch.")

    waitf <- paste0(Sys.getenv("NVIMR_TMPDIR"), "/edit_", Sys.getenv("NVIMR_ID"), "_wait")
    editf <- paste0(Sys.getenv("NVIMR_TMPDIR"), "/edit_", Sys.getenv("NVIMR_ID"))
    unlink(editf)
    writeLines(text = "Waiting...", con = waitf)

    initial <- paste0(Sys.getenv("NVIMR_TMPDIR"), "/nvimcom_edit_",
                      round(runif(1, min = 100, max = 999)))
    sink(initial)
    dput(name)
    sink()

    .C("nvimcom_msg_to_nvim",
       paste0("EditRObject('", initial, "')"),
       PACKAGE = "nvimcom")

    while (file.exists(waitf))
        Sys.sleep(1)
    x <- eval(parse(editf))
    unlink(initial)
    unlink(editf)
    x
}

vi <- function(name = NULL, file = "") {
    nvim.edit(name, file)
}

nvim_capture_source_output <- function(s, o) {
    capture.output(base::source(s, echo = TRUE), file = o)
    .C("nvimcom_msg_to_nvim", paste0("GetROutput('", o, "')"), PACKAGE = "nvimcom")
}

nvim_dput <- function(oname, howto = "tabnew") {
    sink(paste0(Sys.getenv("NVIMR_TMPDIR"), "/Rinsert"))
    eval(parse(text = paste0("dput(", oname, ")")))
    sink()
    .C("nvimcom_msg_to_nvim",
       paste0('ShowRObj("', howto, '", "', oname, '", "r")'),
       PACKAGE = "nvimcom")
}

nvim_viewobj <- function(oname, fenc = "", nrows = NULL, howto = "tabnew", R_df_viewer = NULL) {
    if (is.data.frame(oname) || is.matrix(oname)) {
        # Only when the rkeyword includes "::"
        o <- oname
        oname <- sub("::", "_", deparse(substitute(oname)))
    } else {
        oname_split <- unlist(strsplit(oname, "$", fixed = TRUE))
        oname_split <- unlist(strsplit(oname_split, "[[", fixed = TRUE))
        oname_split <- unlist(strsplit(oname_split, "]]", fixed = TRUE))
        ok <- try(o <- get(oname_split[[1]], envir = .GlobalEnv), silent = TRUE)
        if (length(oname_split) > 1) {
            for (i in 2:length(oname_split)) {
                oname_integer <- suppressWarnings(o <- as.integer(oname_split[[i]]))
                if (is.na(oname_integer)) {
                    ok <- try(o <- ok[[oname_split[[i]]]], silent = TRUE)
                } else {
                    ok <- try(o <- ok[[oname_integer]], silent = TRUE)
                }
            }
        }
        if (inherits(ok, "try-error")) {
            .C("nvimcom_msg_to_nvim",
               paste0("RWarningMsg('", '"', oname, '"', " not found in .GlobalEnv')"),
               PACKAGE = "nvimcom")
            return(invisible(NULL))
        }
    }
    if (is.data.frame(o) || is.matrix(o)) {
        if (!is.null(nrows)) {
          o <- utils::head(o, n = nrows)
        }
        if (!is.null(R_df_viewer)) {
            .C("nvimcom_msg_to_nvim",
               paste0("g:SendCmdToR(printf(g:R_df_viewer, '", oname, "'))"),
               PACKAGE = "nvimcom")
            return(invisible(NULL))
        }
        if (getOption("nvimcom.delim") == "\t") {
            write.table(o, sep = "\t", row.names = FALSE, quote = FALSE,
                        fileEncoding = fenc,
                        file = paste0(Sys.getenv("NVIMR_TMPDIR"), "/Rinsert"))
        } else {
            write.table(o, sep = getOption("nvimcom.delim"), row.names = FALSE,
                        fileEncoding = fenc,
                        file = paste0(Sys.getenv("NVIMR_TMPDIR"), "/Rinsert"))
        }
        .C("nvimcom_msg_to_nvim",
           paste0("RViewDF('", oname, "', '", howto, "')"),
           PACKAGE = "nvimcom")
    } else {
        nvim_dput(oname, howto)
    }
    return(invisible(NULL))
}

NvimR.source <- function(..., print.eval = TRUE, spaced = FALSE) {
    if (with(R.Version(), paste(major, minor, sep = ".")) >= "3.4.0") {
        base::source(getOption("nvimcom.source.path"), ...,
                     print.eval = print.eval, spaced = spaced)
    } else {
        base::source(getOption("nvimcom.source.path"), ..., print.eval = print.eval)
    }
}

NvimR.selection <- function(..., local = parent.frame()) NvimR.source(..., local = local)

NvimR.paragraph <- function(..., local = parent.frame()) NvimR.source(..., local = local)

NvimR.block <- function(..., local = parent.frame()) NvimR.source(..., local = local)

NvimR.function <- function(..., local = parent.frame()) NvimR.source(..., local = local)

NvimR.chunk <- function(..., local = parent.frame()) NvimR.source(..., local = local)

source.and.clean <- function(f, ...) {
    on.exit(unlink(f))
    source(f, ...)
}

nvim_format <- function(l1, l2, wco, sw) {
    if (is.null(getOption("nvimcom.formatfun"))) {
        if ("styler" %in% rownames(installed.packages())) {
           options(nvimcom.formatfun = "style_text")
        } else {
            if ("formatR" %in% rownames(installed.packages())) {
                options(nvimcom.formatfun = "tidy_source")
            } else {
                .C("nvimcom_msg_to_nvim",
                   "RWarningMsg('You have to install either formatR or styler in order to run :Rformat')",
                   PACKAGE = "nvimcom")
                return(invisible(NULL))
            }
        }
    }

    if (getOption("nvimcom.formatfun") == "tidy_source") {
        ok <- try(formatR::tidy_source(paste0(Sys.getenv("NVIMR_TMPDIR"), "/unformatted_code"),
                                       file = paste0(Sys.getenv("NVIMR_TMPDIR"), "/formatted_code"),
                                       width.cutoff = wco))
        if (inherits(ok, "try-error")) {
            .C("nvimcom_msg_to_nvim",
               "RWarningMsg('Error trying to execute the function formatR::tidy_source()')",
               PACKAGE = "nvimcom")
            return(invisible(NULL))
        }
    } else if (getOption("nvimcom.formatfun") == "style_text") {
        txt <- readLines(paste0(Sys.getenv("NVIMR_TMPDIR"), "/unformatted_code"))
        ok <- try(styler::style_text(txt, indent_by = sw))
        if (inherits(ok, "try-error")) {
            .C("nvimcom_msg_to_nvim",
               "RWarningMsg('Error trying to execute the function styler::style_text()')",
               PACKAGE = "nvimcom")
            return(invisible(NULL))
        }
        writeLines(ok, paste0(Sys.getenv("NVIMR_TMPDIR"), "/formatted_code"))
    }

    .C("nvimcom_msg_to_nvim",
       paste0("FinishRFormatCode(", l1, ", ", l2, ")"),
       PACKAGE = "nvimcom")
    return(invisible(NULL))
}

nvim_insert <- function(cmd, howto = "tabnew") {
    try(ok <- capture.output(cmd, file = paste0(Sys.getenv("NVIMR_TMPDIR"), "/Rinsert")))
    if (inherits(ok, "try-error")) {
        .C("nvimcom_msg_to_nvim",
           paste0("RWarningMsg('Error trying to execute the command \"", cmd, "\"')"),
           PACKAGE = "nvimcom")
    } else {
        .C("nvimcom_msg_to_nvim",
           paste0('FinishRInsert("', howto, '")'),
           PACKAGE = "nvimcom")
    }
    return(invisible(NULL))
}

###############################################################################
# The code of the next four functions were copied from the gbRd package
# version 0.4-11 (released on 2012-01-04) and adapted to nvimcom.
# The gbRd package was developed by Georgi N. Boshnakov.

gbRd.set_sectag <- function(s, sectag, eltag) {
    attr(s, "Rd_tag") <- eltag  # using `structure' would be more elegant...
    res <- list(s)
    attr(res, "Rd_tag") <- sectag
    res
}

gbRd.fun <- function(x, pkg) {
    rdo <- NULL # prepare the "Rd" object rdo
    x <- do.call(utils::help, list(x, pkg, help_type = "text",
                               verbose = FALSE,
                               try.all.packages = FALSE))
    if (length(x) == 0)
        return(NULL)

    # If more matches are found will `paths' have length > 1?
    f <- as.character(x[1]) # removes attributes of x.

    path <- dirname(f)
    dirpath <- dirname(path)
    pkgname <- basename(dirpath)
    RdDB <- file.path(path, pkgname)

    if (file.exists(paste(RdDB, "rdx", sep = "."))) {
        rdo <- tools:::fetchRdDB(RdDB, basename(f))
    }
    if (is.null(rdo))
        return(NULL)

    tags <- tools:::RdTags(rdo)
    keep_tags <- c("\\title", "\\name", "\\arguments")
    rdo[which(!(tags %in% keep_tags))] <-  NULL

    rdo
}

gbRd.get_args <- function(rdo, arg) {
    tags <- tools:::RdTags(rdo)
    wtags <- which(tags == "\\arguments")

    if (length(wtags) != 1)
        return(NULL)

    rdargs <- rdo[[wtags]] # use of [[]] assumes only one element here
    f <- function(x) {
        wrk0 <- as.character(x[[1]])
        for (w in wrk0)
            if (w %in% arg)
                return(TRUE)

        wrk <- strsplit(wrk0, ",[ ]*")
        if (!is.character(wrk[[1]])) {
            warning("wrk[[1]] is not a character vector! ", wrk)
            return(FALSE)
        }
        wrk <- any(wrk[[1]] %in% arg)
        wrk
    }
    sel <- !sapply(rdargs, f)

    ## deal with "..." arg
    if ("..." %in% arg || "\\dots" %in% arg) {  # since formals() represents ... by "..."
        f2 <- function(x) {
            if (is.list(x[[1]]) && length(x[[1]]) > 0 &&
               attr(x[[1]][[1]], "Rd_tag") == "\\dots")
                TRUE
            else
                FALSE
        }
        i2 <- sapply(rdargs, f2)
        sel[i2] <- FALSE
    }

    rdargs[sel] <- NULL   # keeps attributes (even if 0 or 1 elem remain).
    rdargs
}

gbRd.args2txt <- function(pkg = NULL, rdo, arglist) {
    rdo <- gbRd.fun(rdo, pkg)

    if (is.null(rdo))
        return(list())

    get_items <- function(a, rdo) {
        if (is.null(a) || is.na(a))
            return(NA)
        # Build a dummy documentation with only one item in the "arguments" section
        x <- list()
        class(x) <- "Rd"
        x[[1]] <- gbRd.set_sectag("Dummy name", sectag = "\\name", eltag = "VERB")
        x[[2]] <- gbRd.set_sectag("Dummy title", sectag = "\\title", eltag = "TEXT")
        x[[3]] <- gbRd.get_args(rdo, a)
        tags <- tools:::RdTags(x)

        # We only need the section "arguments", but print(x) will result in
        # nothing useful if either "title" or "name" section is missing
        keep_tags <- c("\\title", "\\name", "\\arguments")
        x[which(!(tags %in% keep_tags))] <-  NULL

        res <- paste0(x, collapse = "", sep = "")

        # The result is (example from utils::available.packages()):
        # \name{Dummy name}\title{Dummy title}\arguments{\item{max_repo_cache_age}{any
        # cached values older than this in seconds     will be ignored. See \sQuote{Details}.   }}

        .Call("get_section", res, "arguments", PACKAGE = "nvimcom")
    }
    argl <- lapply(arglist, get_items, rdo)
    names(argl) <- arglist
    argl
}

###############################################################################

nvim.GlobalEnv.fun.args <- function(funcname) {
    sink(paste0(Sys.getenv("NVIMR_TMPDIR"), "/args_for_completion"))
    cat(nvim.args(funcname))
    sink()
    if (Sys.getenv("NVIMR_COMPLCB") == "SetComplMenu") {
        .C("nvimcom_msg_to_nvim",
           paste0('FinishGlbEnvFunArgs("', funcname, '")'), PACKAGE = "nvimcom")
    } else {
        .C("nvimcom_msg_to_nvim",
           paste0("v:lua.require'cmp_nvim_r'.finish_glbenv_fun()"),
           PACKAGE = "nvimcom")
    }
    return(invisible(NULL))
}

nvim.get.summary <- function(obj, wdth) {
    isnull <- try(is.null(obj), silent = TRUE)
    if (class(isnull)[1] != "logical")
        return(invisible(NULL))
    if (isnull == TRUE)
        return(invisible(NULL))

    owd <- getOption("width")
    options(width = wdth)
    sink(paste0(Sys.getenv("NVIMR_TMPDIR"), "/args_for_completion"))
    if (Sys.getenv("NVIMR_COMPLCB") == "SetComplMenu") {
        sobj <- try(summary(obj), silent = TRUE)
        print(sobj)
    } else {
        if (!is.null(attr(obj, "label")))
            cat("\n\n", attr(obj, "label"))
        cat("\n\n```rout\n")
        if (is.factor(obj) || is.numeric(obj)) {
            sobj <- try(summary(obj), silent = TRUE)
            print(sobj)
        } else {
            sobj <- try(utils::str(obj), silent = TRUE)
            print(sobj)
        }
        cat("```\n")
    }
    sink()
    options(width = owd)

    if (Sys.getenv("NVIMR_COMPLCB") == "SetComplMenu") {
        .C("nvimcom_msg_to_nvim", "FinishGetSummary()", PACKAGE = "nvimcom")
    } else {
        .C("nvimcom_msg_to_nvim", "v:lua.require'cmp_nvim_r'.finish_get_summary()",
           PACKAGE = "nvimcom")
    }
    return(invisible(NULL))
}

nvim.list.args <- function(ff) {
    saved.warn <- getOption("warn")
    options(warn = -1)
    on.exit(options(warn = saved.warn))
    mm <- try(methods(ff), silent = TRUE)
    if (class(mm)[1] == "MethodsFunction" && length(mm) > 0) {
        for (i in seq_along(mm)) {
            if (exists(mm[i])) {
                cat(ff, "[method ", mm[i], "]:\n", sep = "")
                print(args(mm[i]))
                cat("\n")
            }
        }
        return(invisible(NULL))
    }
    print(args(ff))
}

nvim.plot <- function(x) {
    xname <- deparse(substitute(x))
    if (length(grep("numeric", class(x))) > 0 || length(grep("integer", class(x))) > 0) {
        oldpar <- par(no.readonly = TRUE)
        par(mfrow = c(2, 1))
        hist(x, col = "lightgray", main = paste("Histogram of", xname), xlab = xname)
        boxplot(x, main = paste("Boxplot of", xname),
                col = "lightgray", horizontal = TRUE)
        par(oldpar)
    } else {
        plot(x)
    }
}

nvim.names <- function(x) {
    if (isS4(x))
        slotNames(x)
    else
        names(x)
}

nvim.getclass <- function(x) {
    if (missing(x) || length(charToRaw(x)) == 0)
        return("#E#")

    if (x == "#c#")
        return("character")
    else if (x == "#n#")
        return("numeric")

    if (!exists(x, where = .GlobalEnv)) {
        return("#E#")
    }

    saved.warn <- getOption("warn")
    options(warn = -1)
    on.exit(options(warn = saved.warn))
    tr <- try(cls <- class(get(x, envir = .GlobalEnv)), silent = TRUE)
    if (class(tr)[1] == "try-error")
        return("#E#")

    return(cls)
}

nvim_complete_args <- function(id, rkeyword0, argkey, firstobj = "", pkg = NULL, ldf = FALSE) {
    if (firstobj == "") {
        res <- nvim.args(rkeyword0, argkey, pkg, extrainfo = TRUE, sdq = FALSE)
    } else {
        objclass <- nvim.getclass(firstobj)
        if (objclass[1] == "#E#" || objclass[1] == "")
            res <- nvim.args(rkeyword0, argkey, pkg, extrainfo = TRUE, sdq = FALSE)
        else
            res <- nvim.args(rkeyword0, argkey, pkg, objclass, extrainfo = TRUE, sdq = FALSE)
    }
    if (ldf && exists(firstobj)) {
        dtfrm <- get(firstobj)
        if (is.data.frame(dtfrm)) {
            for (n in names(dtfrm)) {
                nlab <- attr(dtfrm[[n]], "label")
                res <- append(res, paste0("{'word': '", n, "', 'menu': '[", firstobj,
                                          "]', 'user_data': {'word': '", firstobj, "$", n,
                                          "', 'env': '", ifelse(is.null(pkg), ".GlobalEnv", pkg),
                                          "', 'cls': 'v', 'descr': '",
                                          ifelse(is.null(nlab), "", nvim.fix.string(nlab)),
                                          "'}},\n"))
            }
        }
    }
    writeLines(text = res,
               con = paste0(Sys.getenv("NVIMR_TMPDIR"), "/args_for_completion"))
    .C("nvimcom_msg_to_nvim",
       paste("+FinishArgsCompletion", id, argkey, rkeyword0, sep = ";"),
       PACKAGE = "nvimcom")
    return(invisible(NULL))
}
