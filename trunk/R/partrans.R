par.trans <- function (object, params) {
  if (!is(object,"pomp"))
    stop(sQuote("object")," must be a ",sQuote("pomp")," object")
  if (missing(params)) params <- coef(object)
  tfun <- object@userdata$transform.fn
  if (!is.null(tfun))
    do.call(tfun,c(list(params=params),object@userdata))
  else
    params
}

par.untrans <- function (object, params) {
  if (!is(object,"pomp"))
    stop(sQuote("object")," must be a ",sQuote("pomp")," object")
  if (missing(params)) params <- coef(object)
  tfun <- object@userdata$untransform.fn
  if (!is.null(tfun))
    do.call(tfun,c(list(params=params),object@userdata))
  else
    params
}
