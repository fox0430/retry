# Package

version       = "0.1.0"
author        = "fox0430"
description   = "A simple retry interface"
license       = "MIT"
skipDirs      = @["tests"]
installFiles  = @["retry.nim"]


# Dependencies

requires "nim >= 1.6.0"

task testAsyncdispatch, "Run tests with -d:asyncBackend=asyncdispatch":
  exec "nim c -r -d:asyncBackend=asyncdispatch tests/tretry"

task testChronos, "Run tests with -d:asyncBackend=chronos":
  exec "nim c -r -d:asyncBackend=chronos tests/tretry"
