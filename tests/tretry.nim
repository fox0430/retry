#
# retry
# Copyright (c) 2023 Shuhei Nogawa
# This software is released under the MIT License, see LICENSE.txt.
#

import std/[unittest, asyncdispatch, times]
import retry

suite "retry":
  test "The default policy and sccuesful":
    var c = 0

    try:
      retry:
        c.inc
    except AssertionDefect:
      assert c == 1

  test "The default policy and all fails":
    var c = 0

    try:
      retry:
        c.inc
        assert false
    except AssertionDefect:
      assert c == 4

  test "Change maxRetries":
    var c = 0

    var p = DefaultRetryPolicy
    p.maxRetries = 5

    try:
      retry p:
        c.inc
        assert false
    except AssertionDefect:
      assert c == 6

  test "Change delay":
    var p = DefaultRetryPolicy
    p.delay = initDuration(milliseconds = 1)

    let n = now()
    try:
      retry p:
        assert false
    except AssertionDefect:
      assert now() - n < initDuration(milliseconds = 100)

  test "Change backoff":
    var c = 0

    var p = DefaultRetryPolicy
    p.backOff = BackOff.exponential

    let n = now()
    try:
      retry p:
        c.inc
        assert false
    except AssertionDefect:
      assert now() - n > initDuration(milliseconds = 700)

  test "Change exponent":
    var c = 0

    var p = DefaultRetryPolicy
    p.backOff = BackOff.exponential
    p.exponent = 3

    let n = now()
    try:
      retry p:
        c.inc
        assert false
    except AssertionDefect:
      assert now() - n > initDuration(milliseconds = 1000)

suite "retryAsync":
  test "The default policy and sccuesful":
    proc sleepAsync(): Future[void] {.async.} =
      retryAsync:
        await sleepAsync(1)

    waitFor sleepAsync()

  test "The default policy and all fails":
    var c = 0

    proc asyncFail(): Future[void] {.async.} =
      retryAsync:
        c.inc
        await sleepAsync(1)
        assert false

    try:
      waitFor asyncFail()
    except AssertionDefect:
      assert c == 4

  test "Change maxRetries":
    var c = 0

    proc asyncFail(): Future[void] {.async.} =
      var p = DefaultRetryPolicy
      p.maxRetries = 5

      retryAsync p:
        c.inc
        await sleepAsync(1)
        assert false

    try:
      waitFor asyncFail()
    except AssertionDefect:
      assert c == 6

  test "Change delay":
    var c = 0

    proc asyncFail(): Future[void] {.async.} =
      var p = DefaultRetryPolicy
      p.delay = initDuration(milliseconds = 1)

      retryAsync p:
        c.inc
        await sleepAsync(1)
        assert false

    let n = now()
    try:
      waitFor asyncFail()
    except AssertionDefect:
      assert now() - n < initDuration(milliseconds = 100)

  test "Change backoff":
    var c = 0

    proc asyncFail(): Future[void] {.async.} =
      var p = DefaultRetryPolicy
      p.backOff = BackOff.exponential

      retryAsync p:
        c.inc
        await sleepAsync(1)
        assert false

    let n = now()
    try:
      waitFor asyncFail()
    except AssertionDefect:
      assert now() - n > initDuration(milliseconds = 700)

  test "Change exponent":
    var c = 0

    proc asyncFail(): Future[void] {.async.} =
      var p = DefaultRetryPolicy
      p.backOff = BackOff.exponential
      p.exponent = 3

      retryAsync p:
        c.inc
        await sleepAsync(1)
        assert false

    let n = now()
    try:
      waitFor asyncFail()
    except AssertionDefect:
      assert now() - n > initDuration(milliseconds = 1000)
