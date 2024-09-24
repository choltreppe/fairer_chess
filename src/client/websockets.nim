import std/dom
import jsony

type
  WebSocket* = ref object
    readyState*: cint

  MessageEvent* = ref object of Event
    data*, origin*: cstring
    
  CloseEvent* = ref object of Event
    code*: cuint
    wasClean*: bool

func newWebSocket*(url: cstring): WebSocket {.importjs: "new WebSocket(@)".}
func newWebSocket*(url: cstring, protocol: cstring): WebSocket {.importjs: "new WebSocket(@)".}

proc send*(ws: WebSocket, msg: cstring) {.importjs: "#.send(#)".}

proc close*(ws: WebSocket, msg: cstring) {.importjs: "#.close(1000, #)".}

proc    onopen*(ws: WebSocket, cb: proc(e: Event)) {.importjs: "#.onopen = #".}
proc   onclose*(ws: WebSocket, cb: proc(e: CloseEvent)) {.importjs: "#.onclose = #".}
proc   onerror*(ws: WebSocket, cb: proc(e: Event)) {.importjs: "#.onerror = #".}
proc onmessage*(ws: WebSocket, cb: proc(e: MessageEvent)) {.importjs: "#.onmessage = #".}