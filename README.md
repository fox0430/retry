# Retry

A simple retry interface in Nim.

## Examples

```nim
import std/httpclient
import pkg/retry

var client = newHttpClient()

retry:
  discard client.getContent("https://nim-lang.org")
```

```nim
# Please call the `asyncBackend` flag: -d:asyncBackend=asyncdispatch

import std/[asyncdispatch, httpclient]
import pkg/retry

proc getContentAsync(url: string): Future[string] {.async.} = 
  var client = newAsyncHttpClient()

  retryAsync:
    return await client.getContent(url)

discard waitFor getContentAsync("https://nim-lang.org")
```

```nim
import std/[times, httpclient, logging]
import pkg/retry

let myPolicy = RetryPolicy(
  delay: initDuration(milliseconds = 100),
  maxDelay: initDuration(milliseconds = 1000),
  backoff: BackOff.exponential,
  exponent: 2,
  maxRetries: 3,
  jitter: true,
  failLog: true,
  logLevel: Level.lvlError,
  customFailLog: "Custom log: currentRetry: $1, maxRetries: $2, duration: $3")

var client = newHttpClient()

retry myPolicy:
  discard client.getContent("https://nim-lang.org")
```

## Documents

https://fox0430.github.io/retry/retry.html

## License

MIT license
