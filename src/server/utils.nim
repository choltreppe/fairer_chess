import jsony, mummy

include ../utils

proc send*(ws: WebSocket, data: auto) =
  ws.send data.toJson