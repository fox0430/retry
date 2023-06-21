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
import std/[asyncdispatch, httpclient]
import pkg/retry

proc getContentAsync(url: string): Future[string] {.async.} = 
  var client = newAsyncHttpClient()

  retryAsync:
    return await client.getContent(url)

discard waitFor getContentAsync("https://nim-lang.org")
```

```nim
import std/[times, httpclient]
import pkg/retry

let myPolicy = RetryPolicy(
  delay: initDuration(milliseconds = 100),
  maxDelay: initDuration(milliseconds = 1000),
  backoff: BackOff.exponent,
  exponent: 2,
  maxRetries: 3,
  jitter: true,
  failLog: true,
  logLevel: Level.lvlError,
  customFailLog: "Custom log")

retry myPolicy:
  discard client.getContent("https://nim-lang.org")
```

## License

MIT license
