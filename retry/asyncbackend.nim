#
# retry
# Copyright (c) 2023 Shuhei Nogawa
# This software is released under the MIT License, see LICENSE.txt.
#

const
  # -d:asyncBackend=none|asyncdispatch|chronos`
  asyncBackend {.strdefine.} = "none"

  AsyncSupport* = asyncBackend != "none"

when asyncBackend == "none":
  discard
elif asyncBackend == "asyncdispatch":
  import std/asyncdispatch

  export asyncdispatch

  type Duration* = int

elif asyncBackend == "chronos":
  import pkg/chronos

  export chronos

else:
  {.fatal: "Unrecognized backend: " & asyncBackend .}
