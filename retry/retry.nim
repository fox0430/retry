#
# retry
# Copyright (c) 2023 Shuhei Nogawa
# This software is released under the MIT License, see LICENSE.txt.
#

import std/[macros, math, os, random, logging, strutils, strformat]
import asyncbackend

type
  BackOff* = enum
    fixed
    exponential

  MilliSeconds* = int64

  RetryPolicy* = object
    delay*: MilliSeconds
      ## Time to wait after the attempt.

    maxDelay*: MilliSeconds
      ## Maximum delay.

    jitter*: bool
      ## Randomly delay. if true.

    backOff*: BackOff
      ## Fix or increase the wait time after an attempt.

    exponent*: int
      ## Increase delay exponentially with each attempt.
      ## Ignored if `backoff.fixed`.

    maxRetries*: int
      ## Maximum attempts,

    logLevel*: Level
      ## Log level.

    failLog*: bool
      ## Show logs if fails. You need to create a logger before retry.

    customFailLog*: string
      ## If you used custom logs use this.

  RetryError* = object of CatchableError

const
  DefaultRetryPolicy* = RetryPolicy(
    delay: 100,
    maxDelay: 1000,
    backoff: BackOff.fixed,
    exponent: 2,
    maxRetries: 3,
    jitter: false,
    failLog: true,
    logLevel: Level.lvlInfo)

proc sleep(t: int64) {.inline.} = sleep t.int

when AsyncSupport:
  when AsyncBackend == "asyncdispatch":
    proc sleepAsync(t: int64) {.inline, async.} =
      await sleepAsync(t.int)
  else:
    proc sleepAsync(t: int64) {.inline, async.} =
      await sleepAsync(t.milliSeconds)

proc jitter(d: MilliSeconds): MilliSeconds =
  ## Return a random duration.

  randomize()
  let jitter: float64 = rand(1.0)

  let
    secs = d.float64 * jitter
    nanos = d.float64 * jitter
    millis = (secs * 1000.0) + (nanos / 1_000_000.0)

  return millis.int64

proc delay(policy: RetryPolicy, i: int): MilliSeconds =
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
  delay: MilliSeconds): string {.inline.} =
    ## Interpolates a format string with the values from
    ## currentRetry, maxRetries, and delay.

    baseMessage.format($currentRetry, maxRetries, $delay)

proc showFailLog(
  policy: RetryPolicy,
  currentRetry, maxRetries: int,
  delay: MilliSeconds) =
    ## Show logs if policy.failLog is true.

    let message =
      if policy.customFailLog.len > 0:
        policy.customFailLog.formatCustomFailLog(currentRetry, maxRetries, delay)
      else:
        fmt"Attempt: {currentRetry}/{maxRetries}, retrying in {delay} seconds"

    log(policy.logLevel, message)

template retry*(policy: RetryPolicy, body: untyped): untyped =
  ## Attempts received body according to RetryPolicy.
  ## Returns the result of the last body if it fails
  ## (`CatchableError`, Defect) after trying up to the maximum number of times.

  runnableExamples:
    let p = DefaultRetryPolicy
    retry p:
      assert true

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

  runnableExamples:
    retry:
      assert true

  retry DefaultRetryPolicy: body

macro retryIf*(
  policy: RetryPolicy,
  body: typed,
  conditions: untyped): untyped =
    ## Retry only if the result of `body` matches the `conditions`.
    ##
    ## A `r` variable can be used implicitly in `retryIf`.
    ## It's  assigned the result of `body` and is available in the `conditions`.

    runnableExamples:
      assert 2 == retryIf(1 + 1, r != 2)

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
  ## Use `DefaultRetryPolicy`.

  runnableExamples:
    let p = DefaultRetryPolicy
    assert 2 == retryIf(p, 1 + 1, r != 2)

  retryIf(DefaultRetryPolicy, body, conditions)

macro retryIfException*(
  policy: RetryPolicy,
  body: typed,
  exceptions: varargs[untyped]): untyped =
    ## Retry only if the result of `body` matches `exceptions`.

    runnableExamples:
      let p = DefaultRetryPolicy
      retryIfException(p, assert true, AssertionDefect)

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

    runnableExamples:
      retryIfException(assert true, AssertionDefect)

    retryIfException(DefaultRetryPolicy, body, exceptions)

when AsyncSupport:
  template retryAsync*(policy: RetryPolicy, body: untyped): untyped =
    ## Use sleepAsync.

    runnableExamples:
      import std/asyncdispatch

      let p = DefaultRetryPolicy

      proc sleepAsyncRetry(t: int): Future[void] {.async.} =
        retryAsync p:
          await sleepAsync t

      waitFor sleepAsyncRetry(1000)

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

    runnableExamples:
      import std/asyncdispatch

      proc sleepAsyncRetry(t: int): Future[void] {.async.} =
        retryAsync:
          await sleepAsync t

      waitFor sleepAsyncRetry(1000)

    retryAsync DefaultRetryPolicy: body

  macro retryIfAsync*(
    policy: RetryPolicy,
    body: typed,
    conditions: untyped): untyped =
      ## Return an async proc.

      runnableExamples:
        import std/asyncdispatch

        let p = DefaultRetryPolicy

        proc sleepAndReturnInt(t: int): Future[int] {.async.} =
          await sleepAsync t
          return t

        assert 1 == waitFor retryIfAsync(p, sleepAndReturnInt(1), r != 1)

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

  template retryIfAsync*(asyncProc: typed, conditions: untyped): untyped =
    ## Use `DefaultRetryPolicy`.

    runnableExamples:
      import std/asyncdispatch

      proc sleepAndReturnInt(t: int): Future[int] {.async.} =
        await sleepAsync t
        return t

      assert 1 == waitFor retryIfAsync(sleepAndReturnInt(1), r != 1)

    retryIfAsync(DefaultRetryPolicy, asyncProc, conditions)

  macro retryIfExceptionAsync*(
    policy: RetryPolicy,
    asyncProc: typed,
    exceptions: varargs[untyped]): untyped =
      ## Return an async proc.

      runnableExamples:
        import std/asyncdispatch

        let p = DefaultRetryPolicy

        waitFor retryIfExceptionAsync(p, sleepAsync(1), ValueError)

      # Get a return type in the Future of `asyncProc`.
      let returnType = getTypeInst(asyncProc)[1]

      # NimNode for Exceptions.
      var e = newSeq[NimNode]()
      for ident in exceptions:
        e.add ident

      quote do:
        (proc (): Future[`returnType`] {.async.} =
          for i in 0 .. `policy`.maxRetries:
            if i == `policy`.maxRetries:
              # Don't catch errors at the end.
              await `asyncProc`
            else:
              try:
                await `asyncProc`
              except `e`:
                let delay = delay(`policy`, i)

                if `policy`.failLog:
                  showFailLog(`policy`, i, `policy`.maxRetries, delay)

                await sleepAsync delay

                continue

              break
        )()

  template retryIfExceptionAsync*(
    asyncProc: untyped,
    exceptions: varargs[untyped]): untyped =
      ## Use `DefaultRetryPolicy`.

      runnableExamples:
        import std/asyncdispatch

        waitFor retryIfExceptionAsync(sleepAsync(1), ValueError)

      retryIfExceptionAsync(DefaultRetryPolicy, asyncProc, exceptions)
