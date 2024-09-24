import std/dom
include ../utils

func dirtyEcho*(v: auto) =
  {.noSideEffect.}:
    {.emit: ["console.log(", v, ");"].}
    
func `?>`*(cond: bool, s: string): string {.inline.} =
  if cond: s
  else: ""

type Share* = object
  title*, text*, url*: cstring

proc share*(navigator: Navigator, data: Share) {.importjs: "#.share(#)".}

proc writeToClipboard*(navigator: Navigator, text: cstring) {.importjs: "#.clipboard.writeText(#)".}