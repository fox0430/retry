#
# retry
# Copyright (c) 2023 Shuhei Nogawa
# This software is released under the MIT License, see LICENSE.txt.
#

import std/[asyncdispatch, macros, math, os, times, random, logging, strutils,
            strformat]

type
  BackOff* = enum
    fixed
    exponential

  RetryPolicy* = object
    ## Time to wait after the attempt.
    delay*: Duration

    ## Maximum delay
    maxDelay*: Duration

    ## Randomly delay. if true.
    jitter*: bool

    ## Fix or increase the wait time after an attempt.
    backOff*: BackOff

    ## Increase delay exponentially with each attempt.
    ## Ignored if `backoff.fixed`.
    exponent*: int

    ## Maximum attempts
    maxRetries*: int

    ## Log level
    logLevel*: Level

    ## Show logs if fails. You need to create a logger before retry.
    failLog*: bool

    customFailLog*: string

  RetryError* = object of CatchableError

const
  DefaultRetryPolicy* = RetryPolicy(
    delay: initDuration(milliseconds = 100),
    maxDelay: initDuration(milliseconds = 1000),
    backoff: BackOff.fixed,
    exponent: 2,
    maxRetries: 3,
    jitter: false,
    failLog: true,
    logLevel: Level.lvlInfo)

proc sleep(t: int64) {.inline.} = sleep t.int

proc sleep(d: Duration) {.inline.} = sleep inMilliseconds(d)

proc sleepAsync(t: int64): Future[void] {.inline, async.} = await sleepAsync(t.int)

proc sleepAsync(d: Duration): Future[void] {.inline, async.} =
  await sleepAsync inMilliseconds(d)

proc jitter(d: Duration): Duration =
  ## Return a random duration.

  randomize()
  let jitter: float64 = rand(1.0)

  let
    secs = d.inSeconds.float64 * jitter
    nanos = d.inNanoseconds.float64 * jitter
    millis = (secs * 1000.0) + (nanos / 1_000_000.0)

  return initDuration(milliseconds = millis.int)

proc delay(policy: RetryPolicy, i: int): Duration =
  if policy.jitter:
    result = jitter(policy.delay)
  else:
    result = policy.delay

  if policy.backoff == BackOff.exponential:
    result *= (policy.exponent ^ i)

  if policy.maxDelay < result:
    result = policy.maxDelay

proc formatCustomFailLog(
  baseMessage: string,
  currentRetry, maxRetries: int,
  delay: Duration): string {.inline.} =
    ## Interpolates a format string with the values from
    ## currentRetry, maxRetries, and delay.

    baseMessage.format($currentRetry, maxRetries, $delay)

proc showFailLog(
  policy: RetryPolicy,
  currentRetry, maxRetries: int,
  delay: Duration) =
    ## Show logs if policy.failLog is true.

    let message =
      if policy.customFailLog.len > 0:
        policy.customFailLog.formatCustomFailLog(currentRetry, maxRetries, delay)
      else:
        fmt"Attempt: {currentRetry}/{maxRetries}, retrying in {delay} seconds"

    log(policy.logLevel, message)

template retry*(policy: RetryPolicy, body: untyped): untyped =
  ## Attempts received body according to RetryPolicy.
  ## Returns the result of the last body if it fails after trying up to the
  ## maximum number of times.

  for i in 0 .. policy.maxRetries:
    if i == policy.maxRetries:
      # Don't catch errors at the end.
      body
    else:
      try:
        body
      except CatchableError, Defect:
        let delay = delay(policy, i)

        if policy.failLog:
          showFailLog(policy, i, policy.maxRetries, delay)

        sleep delay

        continue

      break

template retry*(body: untyped): untyped =
  ## Use `DefaultRetryPolicy`.

  retry DefaultRetryPolicy: body

macro retryIf*(
  policy: RetryPolicy,
  body: typed,
  conditions: untyped): untyped =
    ## Retry only if the result of `body` matches the `conditions`.
    ##
    ## A `r` variable can be used implicitly in `retryIf`.
    ## It's  assigned the result of `body` and is available in the `conditions`.

    # Get a return type of `body`.
    var procType = getType(body)
    while procType.kind == nnkBracketExpr: procType = procType[1]
    let returnType = procType

    quote do:
      (proc (): `returnType` =
        for i in 0 .. `policy`.maxRetries:
          let r {.inject.} = `body`
          if `conditions`:
            # Retry if conditions match.
            let delay = delay(`policy`, i)

            if `policy`.failLog:
              showFailLog(`policy`, i, `policy`.maxRetries, delay)

            sleep delay
          else:
            return r

        raise newException(RetryError, "Maximum attempts reached")
      )()

template retryIf*(body: typed, conditions: untyped): untyped =
  ## Use DefaultRetryPolicy.

  retryIf(DefaultRetryPolicy, body, conditions)

macro retryIfException*(
  policy: RetryPolicy,
  body: typed,
  exceptions: varargs[untyped]): untyped =
    ## Retry only if the result of `body` matches `exceptions`.

    # NimNode for Exceptions.
    var e = newSeq[NimNode]()
    for ident in exceptions:
      e.add ident

    quote do:
      for i in 0 .. `policy`.maxRetries:
        if i == `policy`.maxRetries:
          # Don't catch errors at the end.
          `body`
        else:
          try:
            `body`
          except `e`:
            let delay = delay(`policy`, i)

            if `policy`.failLog:
              showFailLog(`policy`, i, `policy`.maxRetries, delay)

            sleep delay

            continue

          break

template retryIfException*(
  body: untyped,
  exceptions: varargs[untyped]): untyped =
    ## Use `DefaultRetryPolicy`.

    retryIfException(DefaultRetryPolicy, body, exceptions)

template retryAsync*(policy: RetryPolicy, body: untyped): untyped =
  ## Use sleepAsync.

  for i in 0 .. policy.maxRetries:
    if i == policy.maxRetries:
      # Don't catch errors at the end.
      body
    else:
      try:
        body
      except CatchableError, Defect:
        let delay = delay(policy, i)

        if policy.failLog:
          showFailLog(policy, i, policy.maxRetries, delay)

        await sleepAsync delay

        continue

      break

template retryAsync*(body: untyped): untyped =
  ## Use `DefaultRetryPolicy`.

  retryAsync DefaultRetryPolicy: body

macro retryIfAsync*(
  policy: RetryPolicy,
  body: typed,
  conditions: untyped): untyped =
    ## Return an async proc.

    # Get a return type in the Future of `body`.
    let returnType = getTypeInst(body)[1]

    quote do:
      (proc (): Future[`returnType`] {.async.} =
        for i in 0 .. `policy`.maxRetries:
          let r {.inject.} = await `body`
          if `conditions`:
            # Retry if conditions match.
            let delay = delay(`policy`, i)

            if `policy`.failLog:
              showFailLog(`policy`, i, `policy`.maxRetries, delay)

            await sleepAsync delay
          else:
            return r

        raise newException(RetryError, "Maximum attempts reached")
      )()

template retryIfAsync*(body: typed, conditions: untyped): untyped =
  ## Use DefaultRetryPolicy.

  retryIfAsync(DefaultRetryPolicy, body, conditions)

macro retryIfExceptionAsync*(
  policy: RetryPolicy,
  body: typed,
  exceptions: varargs[untyped]): untyped =
    ## Return an async proc.

    # Get a return type in the Future of `body`.
    let returnType = getTypeInst(body)[1]

    # NimNode for Exceptions.
    var e = newSeq[NimNode]()
    for ident in exceptions:
      e.add ident

    quote do:
      (proc (): Future[`returnType`] {.async.} =
        for i in 0 .. `policy`.maxRetries:
          if i == `policy`.maxRetries:
            # Don't catch errors at the end.
            await `body`
          else:
            try:
              await `body`
            except `e`:
              let delay = delay(`policy`, i)

              if `policy`.failLog:
                showFailLog(`policy`, i, `policy`.maxRetries, delay)

              await sleepAsync delay

              continue

            break
      )()

template retryIfExceptionAsync*(
  body: untyped,
  exceptions: varargs[untyped]): untyped =
    ## Use `DefaultRetryPolicy`.

    retryIfExceptionAsync(DefaultRetryPolicy, body, exceptions)
