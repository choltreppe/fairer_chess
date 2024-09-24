import std/[strutils, strformat, options]
import fusion/matching
import jsony
import mummy, mummy/routers

import ../msgs
import ./game, ./users, ./utils

var server*: Server
import ./sessions


var router*: Router

router.get("/favicon.ico") do (request: Request):
  request.respond(302, @{"Location": "/static/img/favicon.ico"})

router.get("/") do (request: Request):
  request.respond(200, @{"Content-Type": "text/html"}, static(staticRead("index.html")))

router.get("/join/*") do (request: Request):
  request.respond(200, @{"Content-Type": "text/html"}): &"""
    <script>
      window.localStorage.setItem('joinMatchId', '{request.uri.split("/")[^1]}');
      window.location.href = '/';
    </script>
  """

router.get("/ws") do (request: Request):
  if ("sec-fetch-site" notin request.headers or request.headers["sec-fetch-site"].startsWith("same")):
    discard request.upgradeToWebSocket()
  else:
    request.respond(403)

proc getView(conn: RedisConn, sessionId: string, informOpponent = false): View =
  if Some(@session) ?= conn.getSession(sessionId):
    if (Some(@id) ?= session.matchId) and (Some(@match) ?= conn.getMatch(id)):
      case match.state
      of matchWaiting:
        if match.isPublic:
          View(kind: viewWaitOpponent)
        else:
          View(kind: viewGameInvite, matchId: id)
      of matchRunning:
        if Some(@self) ?= match.player(sessionId):
          let opponent = not self
          if Some(@opponentSession) ?= conn.getSession(match.sessionIds[opponent]):
            if informOpponent:
              opponentSession.ws.send ServerMsg(
                kind: setView,
                view: View(kind: viewGame, game: match.game.subjective(opponent))
              )
            View(
              kind: viewGame,
              game: match.game.subjective(self),
              wantRematch: match.wantRematch[self]
            )
          else:
            View(kind: viewError, msg: "your opponent disconnected")
        else:
          session.matchId = none(string)
          View(kind: viewSelectGame, mode: defaultGameMode)
    else:
      View(kind: viewSelectGame, mode: defaultGameMode)
  else:
    View(kind: viewLogin)

proc websocketHandler(
  ws: WebSocket,
  event: WebSocketEvent,
  msg: Message
) =
  {.gcsafe.}:
    case event:
    of OpenEvent: discard

    of MessageEvent:
      #assert msg.kind == TextMessage
      var msg = msg.data.fromJson(ClientMsg)
      var informOpponent = msg.kind != getView

      template updateMatchOfSession(conn: RedisConn, name, body: untyped) =
        if (Some(@session) ?= conn.getSession(msg.sessionId)) and (Some(@matchId) ?= session.matchId):
          conn.updateMatch(matchId, name):
            body
      
      case msg.kind
      of loginGuest:
        #TODO: maybe optimize, so you dont need a 2nd redis access for returning view
        withRedisConn conn:
          msg.sessionId = conn.newSession(newGuestUser(msg.name), ws)
          ws.send ServerMsg(
            kind: setSessionId,
            sessionId: msg.sessionId
          )

      of searchOpponent:
        withRedisConn conn:
          conn.searchPublicMatch(msg.sessionId)

      of startPrivateMatch:
        withRedisConn conn:
          discard conn.newMatch(msg.sessionId, msg.mode)

      of joinMatch:
        withRedisConn conn:
          if not conn.joinMatch(msg.sessionId, msg.matchId):
            ws.send ServerMsg(
              kind: setView,
              view: View(kind: viewError, msg: "match not found :/")
            )
            return

      of leave:
        withRedisConn conn:
          if (Some(@opponentId) ?= conn.leaveMatch(msg.sessionId)) and
               (Some(@session) ?= conn.getSession(opponentId)):
            session.ws.send ServerMsg(kind: setView, view: conn.getView(opponentId))

      of move:
        withRedisConn conn:
          conn.updateMatchOfSession(match):
            if Some(@player) ?= match.player(msg.sessionId):
              if match.game.setMove(player, msg.move.subjective(player)):  # subjective() is its own inverse (= objective())
                match.game.move()
              else:
                informOpponent = false
                if Some(@opponentSession) ?= conn.getSession(match.sessionIds[not player]):
                  opponentSession.ws.send ServerMsg(kind: stopOpponentClock, time: match.game.realClock[player].time)

      of timeOver:
        withRedisConn conn:
          conn.updateMatchOfSession(match):
            match.game.timeOver

      of resign:
        withRedisConn conn:
          conn.updateMatchOfSession(match):
            if Some(@player) ?= match.player(msg.sessionId):
              match.game.resign(player)

      of rematch:
        withRedisConn conn:
          conn.updateMatchOfSession(match):
            if Some(@player) ?= match.player(msg.sessionId):
              if match.wantRematch[not player]:
                restart match.game
                match.wantRematch = [false, false]
              else:
                match.wantRematch[player] = true

      else: discard
      
      withRedisConn conn:
        ws.send ServerMsg(
          kind: setView,
          view: conn.getView(msg.sessionId, informOpponent)
        )
        conn.updateSession(msg.sessionId, session):
          session.ws = ws

    of ErrorEvent: discard

    of CloseEvent: discard

server = newServer(router, websocketHandler)
server.serve(
  Port(9001),
  when defined(release): "0.0.0.0"
  else: "127.0.0.1"
)