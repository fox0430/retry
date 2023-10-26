#
# retry
# Copyright (c) 2023 Shuhei Nogawa
# This software is released under the MIT License, see LICENSE.txt.
#

import std/[unittest, times, strformat, logging]
import ../retry/asyncbackend

import ../retry/retry {.all.}

suite "formatCustomFailLog":
  test "All values":
    let
      baseMessage = "currentRetry: $1, maxRetries: $2, duration: $3"
      currentRetry = 0
      maxRetries = 1
      delay = 100

    assert fmt"currentRetry: {$currentRetry}, maxRetries: {$maxRetries}, duration: {$delay}" ==
      baseMessage.formatCustomFailLog(currentRetry, maxRetries, delay)

  test "Empty":
    let
      baseMessage = ""
      currentRetry = 0
      maxRetries = 1
      delay = 100

    assert baseMessage ==
      baseMessage.formatCustomFailLog(currentRetry, maxRetries, delay)

  test "Only currentRetry":
    let
      baseMessage = "currentRetry: $1"
      currentRetry = 0
      maxRetries = 1
      delay = 100

    assert fmt"currentRetry: {$currentRetry}" ==
      baseMessage.formatCustomFailLog(currentRetry, maxRetries, delay)

  test "Only maxRetries":
    let
      baseMessage = "maxRetries: $2"
      currentRetry = 0
      maxRetries = 1
      delay = 100

    assert fmt"maxRetries: {$maxRetries}" ==
      baseMessage.formatCustomFailLog(currentRetry, maxRetries, delay)

  test "Only delay":
    let
      baseMessage = "delay: $3"
      currentRetry = 0
      maxRetries = 1
      delay = 100

    assert fmt"delay: {$delay}" ==
      baseMessage.formatCustomFailLog(currentRetry, maxRetries, delay)

suite "retry":
  test "The default policy and sccuesful":
    var c = 0

    try:
      retry:
        c.inc
    except AssertionDefect:
      discard

    assert c == 1

  test "The default policy and all fails":
    var c = 0

    try:
      retry:
        c.inc
        assert false
    except AssertionDefect:
      discard

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
      discard

    assert c == 6

  test "Change delay":
    var p = DefaultRetryPolicy
    p.delay = 1

    let n = now()
    try:
      retry p:
        assert false
    except AssertionDefect:
      discard

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
      discard

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
      discard

    assert now() - n > initDuration(milliseconds = 1000)

suite "retryIf":
  test "The default policy and sccuesful":
    proc sum(a, b: int): int = a + b

    assert 3 == retryIf(sum(1, 2), r != 3)

  test "The default policy and all fails":
    var c = 0

    proc sum(a, b: int): int =
      c.inc
      return a + b

    try:
      discard retryIf(sum(1, 2), r == 3)
    except RetryError:
      discard

    assert c == 4

  test "Change maxRetries":
    var c = 0

    proc sum(a, b: int): int =
      c.inc
      return a + b

    var p = DefaultRetryPolicy
    p.maxRetries = 5

    try:
      discard retryIf(p, sum(1, 2), true)
    except RetryError:
      discard

    assert c == 6

  test "Change delay":
    proc sum(a, b: int): int = a + b

    var p = DefaultRetryPolicy
    p.delay = 1

    let n = now()
    try:
      discard retryIf(p, sum(1, 2), true)
    except RetryError:
      discard

    assert now() - n < initDuration(milliseconds = 100)

  test "Change backoff":
    proc sum(a, b: int): int = a + b

    var p = DefaultRetryPolicy
    p.backOff = BackOff.exponential

    let n = now()
    try:
      discard retryIf(p, sum(1, 2), true)
    except RetryError:
      discard

    assert now() - n > initDuration(milliseconds = 700)

  test "Change exponent":
    proc sum(a, b: int): int = a + b

    var p = DefaultRetryPolicy
    p.backOff = BackOff.exponential
    p.exponent = 3

    let n = now()
    try:
      discard retryIf(p, sum(1, 2), true)
    except RetryError:
      discard

    assert now() - n > initDuration(milliseconds = 1000)

suite "retryIfException":
  test "The default policy and sccuesful":
    var c = 0

    proc count() =
      c.inc

    retryIfException(count(), ValueError)

    assert c == 1

  test "The default policy and all fails":
    var c = 0

    proc countAndAssertionDefect() =
      c.inc
      raise newException(AssertionDefect, "")

    try:
      retryIfException(countAndAssertionDefect(), AssertionDefect)
    except AssertionDefect:
      discard

    assert c == 4

  test "Change maxRetries":
    var c = 0

    proc countAndAssertionDefect() =
      c.inc
      raise newException(AssertionDefect, "")

    var p = DefaultRetryPolicy
    p.maxRetries = 5

    try:
      retryIfException(p, countAndAssertionDefect(), AssertionDefect)
    except AssertionDefect:
      discard

    assert c == 6

  test "Change delay":
    var c = 0

    proc countAndAssertionDefect() =
      c.inc
      raise newException(AssertionDefect, "")

    const Policy = RetryPolicy(
      delay: 1,
      maxDelay: 1000,
      backoff: BackOff.fixed,
      exponent: 2,
      maxRetries: 3,
      jitter: false,
      failLog: true,
      logLevel: Level.lvlInfo)

    let n = now()
    try:
      retryIfException(Policy, countAndAssertionDefect(), AssertionDefect)
    except AssertionDefect:
      discard

    assert now() - n < initDuration(milliseconds = 100)

  test "Change backoff":
    var c = 0

    proc countAndAssertionDefect() =
      c.inc
      raise newException(AssertionDefect, "")

    const Policy = RetryPolicy(
      delay: 100,
      maxDelay: 1000,
      backoff: BackOff.exponential,
      exponent: 2,
      maxRetries: 3,
      jitter: false,
      failLog: true,
      logLevel: Level.lvlInfo)

    let n = now()
    try:
      retryIfException(Policy, countAndAssertionDefect(), AssertionDefect)
    except AssertionDefect:
      discard

    assert now() - n > initDuration(milliseconds = 700)

  test "Change exponent":
    var c = 0

    proc countAndAssertionDefect() =
      c.inc
      raise newException(AssertionDefect, "")

    const Policy= RetryPolicy(
      delay: 100,
      maxDelay: 1000,
      backoff: BackOff.exponential,
      exponent: 3,
      maxRetries: 3,
      jitter: false,
      failLog: true,
      logLevel: Level.lvlInfo)

    let n = now()
    try:
      retryIfException(Policy, countAndAssertionDefect(), AssertionDefect)
    except AssertionDefect:
      discard

    assert now() - n > initDuration(milliseconds = 1000)

when AsyncSupport:
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
        discard

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
        discard

      assert c == 6

    test "Change delay":
      var c = 0

      proc asyncFail(): Future[void] {.async.} =
        var p = DefaultRetryPolicy
        p.delay = 1

        retryAsync p:
          c.inc
          await sleepAsync(1)
          assert false

      let n = now()
      try:
        waitFor asyncFail()
      except AssertionDefect:
        discard

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
        discard

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
        discard

      assert now() - n > initDuration(milliseconds = 1000)

  suite "retryIfAsync":
    test "The default policy and sccuesful":
      proc returnInt(): Future[int] {.async.} =
        return 1

      assert 1 == waitFor retryIfAsync(returnInt(), r != 1)

    test "The default policy and all fails":
      var c = 0

      proc countAndReturnInt(): Future[int] {.async.} =
        c.inc
        return 1

      try:
        discard waitFor retryIfAsync(countAndReturnInt(), r == 1)
      except RetryError:
        discard

      assert c == 4

    test "Change maxRetries":
      var c = 0

      proc countAndReturnFlase(): Future[bool] {.async.} =
        c.inc
        return false

      const Policy = RetryPolicy(
        delay: 100,
        maxDelay: 1000,
        backoff: BackOff.fixed,
        exponent: 2,
        maxRetries: 5,
        jitter: false,
        failLog: true,
        logLevel: Level.lvlInfo)

      try:
        discard waitFor retryIfAsync(Policy, countAndReturnFlase(), true)
      except RetryError:
        discard

      assert c == 6

    test "Change delay":
      proc returnFlase(): Future[bool] {.async.} =
        return false

      const Policy = RetryPolicy(
        delay: 1,
        maxDelay: 1000,
        backoff: BackOff.fixed,
        exponent: 2,
        maxRetries: 3,
        jitter: false,
        failLog: true,
        logLevel: Level.lvlInfo)

      let n = now()
      try:
        discard waitFor retryIfAsync(Policy, returnFlase(), true)
      except RetryError:
        discard

      assert now() - n < initDuration(milliseconds = 100)

    test "Change backoff":
      proc returnFlase(): Future[bool] {.async.} =
        return false

      const Policy = RetryPolicy(
        delay: 100,
        maxDelay: 1000,
        backoff: BackOff.exponential,
        exponent: 2,
        maxRetries: 3,
        jitter: false,
        failLog: true,
        logLevel: Level.lvlInfo)

      let n = now()
      try:
        discard waitFor retryIfAsync(Policy, returnFlase(), true)
      except RetryError:
        discard

      assert now() - n > initDuration(milliseconds = 700)

    test "Change exponent":
      proc returnFlase(): Future[bool] {.async.} =
        return false

      const Policy = RetryPolicy(
        delay: 100,
        maxDelay: 1000,
        backoff: BackOff.exponential,
        exponent: 3,
        maxRetries: 3,
        jitter: false,
        failLog: true,
        logLevel: Level.lvlInfo)

      let n = now()
      try:
        discard waitFor retryIfAsync(Policy, returnFlase(), true)
      except RetryError:
        discard

      assert now() - n > initDuration(milliseconds = 1000)

  suite "retryIfExceptionAsync":
    test "The default policy and sccuesful":
      var c = 0

      proc count(): Future[void] {.async.} =
        c.inc

      waitFor retryIfExceptionAsync(count(), ValueError)

      assert c == 1

    test "The default policy and all fails":
      var c = 0

      proc countAndAssertionDefect(): Future[void] {.async.} =
        c.inc
        raise newException(AssertionDefect, "")

      try:
        waitFor retryIfExceptionAsync(countAndAssertionDefect(), AssertionDefect)
      except AssertionDefect:
        discard

      assert c == 4

    test "Change maxRetries":
      var c = 0

      proc countAndAssertionDefect(): Future[void] {.async.} =
        c.inc
        raise newException(AssertionDefect, "")

      const Policy = RetryPolicy(
        delay: 100,
        maxDelay: 1000,
        backoff: BackOff.fixed,
        exponent: 2,
        maxRetries: 5,
        jitter: false,
        failLog: true,
        logLevel: Level.lvlInfo)

      try:
        waitFor retryIfExceptionAsync(
          Policy,
          countAndAssertionDefect(),
          AssertionDefect)
      except AssertionDefect:
        discard

      assert c == 6

    test "Change delay":
      var c = 0

      proc countAndAssertionDefect(): Future[void] {.async.} =
        c.inc
        raise newException(AssertionDefect, "")

      const Policy = RetryPolicy(
         delay: 1,
         maxDelay: 1000,
         backoff: BackOff.fixed,
         exponent: 2,
         maxRetries: 3,
         jitter: false,
         failLog: true,
         logLevel: Level.lvlInfo)

      let n = now()
      try:
        waitFor retryIfExceptionAsync(
          Policy,
          countAndAssertionDefect(),
          AssertionDefect)
      except AssertionDefect:
        discard

      assert now() - n < initDuration(milliseconds = 100)

    test "Change backoff":
      var c = 0

      proc countAndAssertionDefect(): Future[void] {.async.} =
        c.inc
        raise newException(AssertionDefect, "")

      const Policy = RetryPolicy(
        delay: 100,
        maxDelay: 1000,
        backoff: BackOff.exponential,
        exponent: 2,
        maxRetries: 3,
        jitter: false,
        failLog: true,
        logLevel: Level.lvlInfo)

      let n = now()
      try:
        waitFor retryIfExceptionAsync(
          Policy,
          countAndAssertionDefect(),
          AssertionDefect)
      except AssertionDefect:
        discard

      assert now() - n > initDuration(milliseconds = 700)

    test "Change exponent":
      var c = 0

      proc countAndAssertionDefect(): Future[void] {.async.} =
        c.inc
        raise newException(AssertionDefect, "")

      const Policy = RetryPolicy(
         delay: 100,
         maxDelay: 1000,
         backoff: BackOff.exponential,
         exponent: 3,
         maxRetries: 3,
         jitter: false,
         failLog: true,
         logLevel: Level.lvlInfo)

      let n = now()
      try:
        waitFor retryIfExceptionAsync(
          Policy,
          countAndAssertionDefect(),
          AssertionDefect)
      except AssertionDefect:
        discard

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

when AsyncSupport:
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
