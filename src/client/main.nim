import std/[dom, asyncjs, strutils, strformat, uri, sugar, options, cookies, strtabs, macros]
include karax/prelude
import fusion/matching
import jsony

import ../[msgs, host]
import ../server/[users, game]
import ./utils, ./websockets

var
  ws: WebSocket
  sessionId: string
  view: View

if (let id = window.localStorage.getItem("sessionId"); id != nil):
  sessionId = $id


proc openWebSocket: Future[void]

proc send(msg: ClientMsg) {.async, discardable.} =
  var msg = msg
  msg.sessionId = sessionId
  if ws == nil or ws.readyState != 1:
    await openWebSocket()
  ws.send msg.toJson.cstring

proc send(kind: ClientMsgKind) =
  send ClientMsg(kind: kind)


proc renderClock(time: int): string =
  align($(time div 60), 2, '0') & ":" & align($(time mod 60), 2, '0')

var clockwork: array[SubjPlayer, Option[Interval]]

proc updateClockwork =
  proc stopClockwork(player: SubjPlayer) =
    if Some(@interval) ?= clockwork[player]:
      clearInterval interval
      clockwork[player] = none(Interval)

  if view.kind == viewGame:
    for player in SubjPlayer:
      if view.game.clock[player].running:
        if clockwork[player].isNone:
          capture player:
            clockwork[player] = some(setInterval(
              (proc =
                dec view.game.clock[player].time
                redraw kxi
                if view.game.clock[player].time <= 0:
                  send timeOver
              ),
              1_000
            ))
      else:
        stopClockwork(player)
  else:
    for player in SubjPlayer:
      stopClockwork(player)


proc openWebSocket: Future[void] =
  const url = (
      when defined(release): "wss://"
      else: "ws://"
    ) & hostName & "/ws"

  newPromise do (resolve: proc ()):
    ws = newWebSocket(url)

    ws.onopen do (_: Event):

      ws.onmessage do (e: MessageEvent):
        let msg = e.data.`$`.fromJson(ServerMsg)

        case msg.kind
        of setSessionId:
          sessionId = msg.sessionId
          window.localStorage.setItem("sessionId", sessionId);

        of setView:
          view = msg.view
          if view.kind notin {viewLoading, viewLogin} and (let id = window.localStorage.getItem("joinMatchId"); id != nil):
            send ClientMsg(kind: joinMatch, matchId: $id)
            window.localStorage.removeItem("joinMatchId")
          else:
            updateClockwork()
            redraw kxi

        of stopOpponentClock:
          if view.kind == viewGame:
            view.game.clock[playerOpponent] = (time: msg.time, running: false)
            updateClockwork()
            redraw kxi

      resolve()

    ws.onclose do (e: CloseEvent):
      discard openWebSocket()


func renderTitledBox(title: string, content: VNode): VNode =
  content.class = "content"
  buildHtml(tdiv(class="titled-box")):
    tdiv(class="title"): text title
    content

proc renderDialogBox(buttonText: string, content: VNode): VNode =
  content.class = "content"
  buildHtml(form(class="dialog-box")):
    content
    tdiv(class="buttons"):
      button(action="submit"): text buttonText

template renderGameEndDialog(msg: string, withRematchOption = true): VNode =
  var buttonPressed {.global.} = false
  expandMacros:
    buildHtml(tdiv(class="dialog-box")):
      tdiv(class="content"): text msg
      tdiv(class="buttons"):
        if withRematchOption:
          tdiv(class = "button"&(view.wantRematch ?> " pressed")):
            text "rematch"
            proc onclick {.noredraw.} =
              send rematch
        tdiv(class="button"):
          text "new game"
          proc onclick {.noredraw.} =
            send leave

proc renderRules: VNode =
  renderTitledBox("Rules", buildHtml(tdiv(id="rules")) do:
    h1: text "Chess, but both players are on the move at the same time"
    
    for (desc, imgs) in {
      "When a piece moved away it isn't captured.": @["miss", "swap"],
      "When a piece gets in front of another piece, it blocks its attack but gets captured": @["sacrifice"],
      "You can overshoot a attack. It will still just move as far as possible": @["overshoot1", "overshoot2"],
      "When both pieces move to the same square, both are captured.": @["collide"],
      "The only exception is when you castle your rook can be captured.": @["collide_castle"],
      "You can capture your own pieces.<br/>When your opponent wants to capture that piece, you capture his piece aswell.": @["self_capture", "self_capture_def"]
    }:
      tdiv(class="desc"): verbatim desc
      for img in imgs:
        tdiv(class="rule"):
          proc addImg(side: char): VNode =
            buildHtml(img(src = &"/static/img/rules/{img}_{side}.svg"))
          addImg('b')
          tdiv(class="arrow")
          addImg('a')
  )

proc render(game: var SubjGame): VNode =

  func renderCapture(pieces: array[PieceKind, Natural], player: SubjPlayer): VNode =
    buildHtml(tdiv(class="captures")):
      for kind, count in pieces:
        if count > 0:
          tdiv:
            for _ in 0 ..< count:
              tdiv(class = &"piece {kind}" & (player == playerOpponent ?> " opponent-capture"))

  func value(pieces: array[PieceKind, Natural]): int =
    for kind, count in pieces:
      result += [king: 0, queen: 9, rook: 5, bishop: 3, knight: 3, pawn: 1][kind] * count

  proc renderPlayerInfoRow(player: SubjPlayer): VNode =
    buildHtml(tdiv(class = "player-info-row " & $player)):
      tdiv(class="player-name"): text $game.users[player]
      renderCapture(game.captures[player], player)
      tdiv(class="material-advantage"):
        if (let materialDiff = game.captures[player].value - game.captures[not player].value; materialDiff > 0):
          text &"+{materialDiff}"
      tdiv(class="clock"):
        text renderClock(game.clock[player].time)

  buildHtml(tdiv(id="game")):

    renderPlayerInfoRow(playerOpponent)

    tdiv(id="board"):
      for rowi, row in game.board:
        tdiv(class="row"):
          for coli, piece in row:
            capture(rowi, coli, block:
              let pos: Pos = (rowi, coli)

              var class: string
              if Some(@piece) ?= piece:
                class = &"piece {piece.kind} {piece.player}"
              if pos in game.prevMoveMarks.captures:
                class.add " prev-capture"
              elif pos in game.prevMoveMarks.origins:
                class.add " prev-pos"

              var moveId = -1
              if game.nextMove.stage == posSelected:
                if (let id = game.possibleMoves[game.nextMove.pos].findIt(it.pos == pos); id >= 0):
                  moveId = id
                  class.add " move-select"
              elif game.nextMove.stage == allSelected and
                   game.possibleMoves[game.nextMove.move.pos][game.nextMove.move.id].pos == pos:
                class.add " move-selected"

              buildHtml(tdiv(class=class)):
                proc onclick =
                  if game.nextMove.stage != allSelected:
                    if game.nextMove.stage == posSelected and moveId >= 0:
                      game.nextMove = StagedMoveSelect(
                        stage: allSelected,
                        move: (game.nextMove.pos, moveId, queen),
                        needsPawnReplace: game.possibleMoves[game.nextMove.pos][moveId].kind == pawnReplaceMove
                      )
                      if not game.nextMove.needsPawnReplace:
                        send ClientMsg(kind: move, move: game.nextMove.move)

                    elif len(game.possibleMoves[pos]) > 0:
                      game.nextMove = StagedMoveSelect(
                        stage: posSelected,
                        pos: pos
                      )

                    else:
                      game.nextMove = StagedMoveSelect(stage: nothingSelected)

                if game.nextMove.stage == allSelected and
                    game.nextMove.needsPawnReplace and
                    game.possibleMoves[game.nextMove.move.pos][game.nextMove.move.id].pos == pos:
                  tdiv(class="pawn-replace-select"):
                    for kind in queen..knight:
                      capture(kind,
                        buildHtml(tdiv(class = &"piece {kind}")) do:
                          proc onclick =
                            game.nextMove.move.replaceWith = kind
                            game.nextMove.needsPawnReplace = false
                            send ClientMsg(kind: move, move: game.nextMove.move)
                      )
            )

    renderPlayerInfoRow(playerSelf)

    if game.state.kind in {gameRemi, gameWon}:
      tdiv(class = "popup-container"):
        renderGameEndDialog(
          case game.state.kind
          of gameRemi: "Remis"
          of gameWon:
            if game.state.resigned:
              case game.state.by
              of playerSelf: "Your opponent resigned"
              of playerOpponent: "You resigned"
            else:
              case game.state.by
              of playerSelf: "You won !"
              of playerOpponent: "You lost :("
          else: ""  # never happens
        )
    else:
      button(id="resign"):
        text "resign"
        proc onclick {.noredraw.} =
          send resign

func inviteUrl(matchId: string): string =
  (
    when defined(release): "https://"
    else: "http://"
  ) & hostName & "/join/" & matchId

proc createDom: VNode =
  buildHtml(tdiv):
    tdiv(id="header"):
      tdiv(id="logo"):
        proc onclick {.noredraw.} =
          send leave
      tdiv(id="nav"):
        if view.kind == viewSelectGame:
          tdiv:
            text "rules"
            proc onclick =
              view = View(kind: viewRules)
        elif view.kind != viewLogin:
          tdiv:
            text "home"
            proc onclick {.noredraw.} =
              send leave
        a(href="https://chol.foo/imprint.html"):
          text "imprint"
        a(href="https://github.com/choltreppe/fairer_chess"):
          text "source code"
    
    tdiv(id="content"):
      case view.kind
      of viewLoading: tdiv(id="loading")

      of viewLogin:
        renderDialogBox("start",
          buildHtml(tdiv(id="name-input")) do:
            text "name:"
            #input(`type`="text", id="guest-name", maxlength=MaxPlayerNameLen):
            input(`type`="text", id="guest-name", value=view.name):
              proc oninput(_: Event, n: VNode) =
                view.name = $n.value  
        ):
          proc onsubmit(e: Event, _: VNode) {.noredraw.} =
            e.preventDefault
            send ClientMsg(kind: loginGuest, name: view.name)

        renderRules()

      of viewRules: renderRules()

      of viewSelectGame:
       tdiv(id="start-game-nav"):
        button:
          text "search opponent"
          proc onclick {.noredraw.} =
            send searchOpponent
        
        renderDialogBox("start private game",
          buildHtml(tdiv(id = "private-game-config")) do:
            tdiv:
              input(
                id = "mode-time",
                `type` = "number",
                value = $view.mode.time,
                min = "1", max = "30",
                size = "1"
              ):
                proc oninput(_: Event, n: VNode) =
                  view.mode.time = parseInt($n.value)
              text "minutes"
            #TODO: other mode options when added
        ):
          proc onsubmit(e: Event, _: VNode) {.noredraw.} =
            e.preventDefault
            send ClientMsg(kind: startPrivateMatch, mode: view.mode)

      of viewWaitOpponent:
        tdiv(class="info-box"):
          text "waiting for opponent .."

      of viewGameInvite:
        renderTitledBox("match created",
          buildHtml(tdiv) do:
            a(href = inviteUrl(view.matchId)):
              text "send this link to invite"
        )

      of viewGame:
        render(view.game)

      of viewError:
        tdiv(class="info-box"):
          text view.msg

      else: discard #TODO

proc postRender =
  if view.kind == viewGameInvite:
    try:
      navigator.share Share(
        title: "Fairer Chess",
        text: "join the match",
        url: inviteUrl(view.matchId)
      )
    except: discard


proc main {.async.} =
  setRenderer createDom, clientPostRenderCallback = postRender
  await openWebSocket()
  send getView

discard main()