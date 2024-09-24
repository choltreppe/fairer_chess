from ./server/game import SubjGame, GameMode, MoveSelect

type
  ViewKind* = enum viewLoading, viewError, viewLogin, viewRules, viewSelectGame, viewWaitOpponent, viewGameInvite, viewGame
  View* = object
    case kind*: ViewKind
    of viewError:
      msg*: string
    of viewLogin:
      name*: string
    of viewSelectGame:
      mode*: GameMode
    of viewGameInvite:
      matchId*: string
    of viewGame:
      game*: SubjGame
      wantRematch*: bool
    else: discard

  ServerMsgKind* = enum setSessionId, setView, stopOpponentClock
  ServerMsg* = object
    case kind*: ServerMsgKind
    of setSessionId: sessionId*: string
    of setView: view*: View
    of stopOpponentClock: time*: int

  ClientMsgKind* = enum getView, loginGuest, searchOpponent, startPrivateMatch, joinMatch, leave, move, timeOver, resign, rematch
  ClientMsg* = object
    sessionId*: string
    
    case kind*: ClientMsgKind
    of loginGuest:
      name*: string

    of startPrivateMatch:
      mode*: GameMode

    of joinMatch:
      matchId*: string

    of move:
      move*: MoveSelect

    else: discard