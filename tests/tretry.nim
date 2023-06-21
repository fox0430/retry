#
# retry
# Copyright (c) 2023 Shuhei Nogawa
# This software is released under the MIT License, see LICENSE.txt.
#

import std/[unittest, asyncdispatch, times, strformat, logging]
import retry {.all.}

suite "formatCustomFailLog":
  test "All values":
    let
      baseMessage = "currentRetry: $1, maxRetries: $2, duration: $3"
      currentRetry = 0
      maxRetries = 1
      delay = initDuration(milliseconds = 100)

    assert fmt"currentRetry: {$currentRetry}, maxRetries: {$maxRetries}, duration: {$delay}" ==
      baseMessage.formatCustomFailLog(currentRetry, maxRetries, delay)

  test "Empty":
    let
      baseMessage = ""
      currentRetry = 0
      maxRetries = 1
      delay = initDuration(milliseconds = 100)

    assert baseMessage ==
      baseMessage.formatCustomFailLog(currentRetry, maxRetries, delay)

  test "Only currentRetry":
    let
      baseMessage = "currentRetry: $1"
      currentRetry = 0
      maxRetries = 1
      delay = initDuration(milliseconds = 100)

    assert fmt"currentRetry: {$currentRetry}" ==
      baseMessage.formatCustomFailLog(currentRetry, maxRetries, delay)

  test "Only maxRetries":
    let
      baseMessage = "maxRetries: $2"
      currentRetry = 0
      maxRetries = 1
      delay = initDuration(milliseconds = 100)

    assert fmt"maxRetries: {$maxRetries}" ==
      baseMessage.formatCustomFailLog(currentRetry, maxRetries, delay)

  test "Only delay":
    let
      baseMessage = "delay: $3"
      currentRetry = 0
      maxRetries = 1
      delay = initDuration(milliseconds = 100)

    assert fmt"delay: {$delay}" ==
      baseMessage.formatCustomFailLog(currentRetry, maxRetries, delay)

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

suite "Logs: `retry`":
  ## Init a console logger for tests.
  var logger = newConsoleLogger(levelThreshold=lvlInfo, "This is test: ")
  addHandler(logger)

  test "Enable failLog":
    var p = DefaultRetryPolicy
    p.maxRetries = 1
    p.failLog = true

    try:
      retry p:
        assert false
    except AssertionDefect:
      assert true

  test "customFailLog":
    var p = DefaultRetryPolicy
    p.maxRetries = 1
    p.failLog = true
    p.customFailLog = "Custom log: $1, $2, $3"

    try:
      retry p:
        assert false
    except AssertionDefect:
      assert true

suite "Logs: `retryAsync`":
  test "Enable failLog":
    proc asyncFail(): Future[void] {.async.} =
      var p = DefaultRetryPolicy
      p.maxRetries = 1
      p.failLog = true

      retryAsync p:
        await sleepAsync(1)
        assert false

    try:
       waitFor asyncFail()
    except AssertionDefect:
      assert true

  test "customFailLog":
    proc asyncFail(): Future[void] {.async.} =
      var p = DefaultRetryPolicy
      p.maxRetries = 1
      p.failLog = true
      p.customFailLog = "Custom log: $1, $2, $3"

      retryAsync p:
        await sleepAsync(1)
        assert false

    try:
       waitFor asyncFail()
    except AssertionDefect:
      assert true
