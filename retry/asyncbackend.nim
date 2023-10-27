#
# retry
# Copyright (c) 2023 Shuhei Nogawa
# This software is released under the MIT License, see LICENSE.txt.
#

const
  # -d:asyncBackend=none|asyncdispatch|chronos`
  AsyncBackend* {.strdefine.} = "none"

  AsyncSupport* = AsyncBackend != "none"

when AsyncBackend == "none":
  discard
elif AsyncBackend == "asyncdispatch":
  import std/asyncdispatch

  export asyncdispatch

  type Duration* = int

elif AsyncBackend == "chronos":
  import pkg/chronos

  export chronos

else:
  {.fatal: "Unrecognized backend: " & AsyncBackend .}
