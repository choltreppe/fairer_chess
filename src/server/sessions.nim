import std/[strutils, oids, options, macros]
import fusion/matching
import ready, jsony
export ready.RedisConn
from mummy import WebSocket, Server

import ./users, ./game
from ./main import server


const
  sessionExpireTime = 24*60*60
  matchExpireTime = 10*60


type
  Session* = object
    user*: User
    ws*: WebSocket
    matchId*: Option[string]

  MatchState = enum matchWaiting, matchRunning
  Match* = object
    case state*: MatchState
    of matchWaiting:
      bySessionId*: string
      mode*: GameMode
    of matchRunning:
      sessionIds*: array[ObjPlayer, string]
      game*: Game
      wantRematch*: array[ObjPlayer, bool]
    isPublic*: bool


let redisPool = newRedisPool(5)

when not defined(release):
  discard redisPool.command("FLUSHALL")

template withRedisConn*(name, body: untyped) =
  redisPool.withConnection name:
    body


template genUniqueKey(conn: RedisConn, toKey: proc(id: string): string) =
  while (
    result = $genOid();
    let key = toKey(result);
    conn.command("EXISTS", key).to(int) > 0
  ): discard

macro genSetGetUpdate(T: typedesc, toKey: proc(id: string): string, expire: int) =
  let setter = ident("set" & $T)
  let getter = ident("get" & $T)
  let update = ident("update" & $T)
  quote do:

    proc `setter`*(conn: RedisConn, id: string, session: `T`) =
      let key = "fchess:" & `toKey`(id)
      discard conn.command("SET", key, session.toJson)
      discard conn.command("EXPIRE", key, $`expire`)

    proc `getter`*(conn: RedisConn, id: string): Option[`T`] =
      let key = "fchess:" & `toKey`(id)
      if conn.command("EXISTS", key).to(int) > 0:
        result = some(conn.command("GET", key).to(string).fromJson(`T`))

    template `update`*(conn: RedisConn, id: string, name, body: untyped) =
      if (let o = conn.`getter`(id); o.isSome):
        var name = o.get
        body
        conn.`setter`(id, name)


# missusing the hooks to just ignore server and keep constant to the only server there is
proc dumpHook(s: var string, v: Server) = discard
proc parseHook(s: string, i: var int, v: var Server) = v = server

func sessionKey(id: string): string = "session:"&id

Session.genSetGetUpdate(sessionKey, sessionExpireTime)

# returns session id
proc newSession*(conn: RedisConn, user: User, ws: WebSocket): string =
  conn.genUniqueKey(sessionKey)
  conn.setSession(result, Session(user: user, ws: ws))


func player*(match: Match, sessionId: string): Option[ObjPlayer] =
  if match.state == matchRunning:
    for player in ObjPlayer:
      if match.sessionIds[player] == sessionId:
        return some(player)

func matchKey(id: string): string = "match:"&id

const publicMatchWaitKey = "publicmatchwait"

Match.genSetGetUpdate(matchKey, matchExpireTime)

# returns match id
proc newMatch*(conn: RedisConn, sessionId: string, mode: GameMode, isPublic = false): string =
  conn.genUniqueKey(matchKey)
  conn.setMatch(result, Match(
    mode: mode,
    state: matchWaiting,
    bySessionId: sessionId,
    isPublic: isPublic
  ))
  conn.updateSession(sessionId, session):
    session.matchId = some(result)

proc removeIfPublicWaiting(conn: RedisConn, matchId: string) =
  if conn.command("EXISTS", publicMatchWaitKey).to(int) > 0 and
      conn.command("GET", publicMatchWaitKey).to(string) == matchId:
    discard conn.command("DEL", publicMatchWaitKey)

proc joinMatch*(conn: RedisConn, sessionId, matchId: string): bool =
  conn.updateMatch(matchId, match):
    if match.state == matchWaiting and
        (Some(@session1) ?= conn.getSession(match.bySessionId)) and
        sessionId != match.bySessionId:
      var sessionIds: array[ObjPlayer, string]
      var users: array[ObjPlayer, User]
      sessionIds[player1] = match.bySessionId
      users[player1] = session1.user
      conn.updateSession(sessionId, session2):
        sessionIds[player2] = sessionId
        users[player2] = session2.user
        session2.matchId = some(matchId)
        match = Match(
          state: matchRunning,
          sessionIds: sessionIds,
          game: newGame(users, match.mode),
          isPublic: match.isPublic
        )
        conn.removeIfPublicWaiting(matchId)
        result = true

proc searchPublicMatch*(conn: RedisConn, sessionId: string) =
  if conn.command("EXISTS", publicMatchWaitKey).to(int) == 0:
    let matchId = conn.newMatch(sessionId, defaultGameMode, isPublic = true)
    discard conn.command("SET", publicMatchWaitKey, matchId)
  else:
    if not conn.joinMatch(sessionId, conn.command("GET", publicMatchWaitKey).to(string)):
      discard conn.command("DEL", publicMatchWaitKey)
      conn.searchPublicMatch(sessionId)

# returns opponent sessionId if he needs to be informed
proc leaveMatch*(conn: RedisConn, sessionId: string): Option[string] =
  conn.updateSession(sessionId, session):
    if Some(@matchId) ?= session.matchId:
      session.matchId = none(string)
      if Some(@match) ?= conn.getMatch(matchId):
        discard conn.command("DEL", matchKey(matchId))
        conn.removeIfPublicWaiting(matchId)
        if Some(@player) ?= match.player(sessionId):
          let opponentId = match.sessionIds[not player]
          conn.updateSession(opponentId, session):
            session.matchId = none(string)
            result = some(opponentId)