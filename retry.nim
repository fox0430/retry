#
# retry
# Copyright (c) 2023 Shuhei Nogawa
# This software is released under the MIT License, see LICENSE.txt.
#

import std/[asyncdispatch, macros, math, os, times, random]

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

const
  DefaultRetryPolicy* = RetryPolicy(
    delay: initDuration(milliseconds = 100),
    maxDelay: initDuration(milliseconds = 1000),
    backoff: BackOff.fixed,
    exponent: 2,
    maxRetries: 3,
    jitter: false)

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
        sleep delay(policy, i)

        continue

      break

template retry*(body: untyped): untyped =
  ## Use `DefaultRetryPolicy`.

  retry DefaultRetryPolicy: body

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
        await sleepAsync delay(policy, i)

        continue

      break

template retryAsync*(body: untyped): untyped =
  ## Use `DefaultRetryPolicy`.

  retryAsync DefaultRetryPolicy: body
