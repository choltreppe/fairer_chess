import std/options
import arrayutils
import ./users

type
  Pos* = tuple[row, col: int]

  ObjPlayer* = enum player1, player2
  SubjPlayer* = enum playerSelf="self", playerOpponent="opponent"
  Player = ObjPlayer|SubjPlayer

  PieceKind* = enum king, queen, rook, bishop, knight, pawn
  Piece[P: Player] = object
    kind*: PieceKind
    player*: P
  ObjPiece* = Piece[ObjPlayer]
  SubjPiece* = Piece[SubjPlayer]

  BoardLike[T] = array[8, array[8, T]]

  ObjBoard* = BoardLike[Option[ObjPiece]]
  SubjBoard* = BoardLike[Option[SubjPiece]]

  MoveKind* = enum basicMove, castleMove, pawnReplaceMove
  Move* = object
    pos*: Pos
    case kind*: MoveKind
    of castleMove: castleSide*: CastleSide
    else: discard

  PossibleMoves* = BoardLike[seq[Move]]

  MoveSelect* = tuple
    pos: Pos
    id: int
    replaceWith: PieceKind  # just used on pawn replace moves

  StagedMoveSelectStage* = enum nothingSelected, posSelected, allSelected
  StagedMoveSelect* = object
    case stage*: StagedMoveSelectStage
    of nothingSelected: discard
    of posSelected:
      pos*: Pos
    of allSelected:
      move*: MoveSelect
      needsPawnReplace*: bool

  GameStateKind* = enum gameContinues, gameWon, gameRemi
  GameState[P: Player] = object
    case kind*: GameStateKind
    of gameWon:
      by*: P
      resigned*: bool  # did he win by opponent resigning
    else: discard
  ObjGameState* = GameState[ObjPlayer]
  SubjGameState* = GameState[SubjPlayer]

  CastleSide = enum shortCastle, longCastle
  
  GameMode* = object
    time*: int  # in minutes

  Game* = object
    users: array[ObjPlayer, User]
    mode: GameMode
    board: ObjBoard
    turnStartTime: int64
    clock: array[ObjPlayer, int]
    possibleMoves: array[ObjPlayer, PossibleMoves]
    canCastle: array[ObjPlayer, array[CastleSide, bool]]# = [[true, true], [true, true]]
    captures: array[ObjPlayer, array[PieceKind, Natural]]
    nextMoves: array[ObjPlayer, Option[MoveSelect]]
    prevMoveMarks: tuple[origins, captures: seq[Pos]]
    state: ObjGameState

  SubjGame* = object
    users*: array[SubjPlayer, User]
    board*: SubjBoard
    turnStartTime*: int64
    clock*: array[SubjPlayer, tuple[time: int, running: bool]]
    possibleMoves*: PossibleMoves
    captures*: array[SubjPlayer, array[PieceKind, Natural]]
    nextMove*: StagedMoveSelect
    prevMoveMarks*: tuple[origins, captures: seq[Pos]]
    state*: GameState[SubjPlayer]

  UnknownMoveError* = ref object of CatchableError

func `[]`*[T](board: BoardLike[T], pos: Pos): T =
  board[pos.row][pos.col]

func `[]`*[T](board: var BoardLike[T], pos: Pos): var T =
  board[pos.row][pos.col]

func `[]=`*[T](board: var BoardLike[T], pos: Pos, v: T) =
  board[pos.row][pos.col] = v

func `not`*(player: SubjPlayer): SubjPlayer =
  case player
  of playerSelf: playerOpponent
  of playerOpponent: playerSelf


when not defined(js):

  import std/[sequtils, strutils, strformat, sugar, tables, times, math]
  import fusion/matching
  import ./utils

  const defaultGameMode* = GameMode(time: 10)

  func `$`(piece: ObjPiece): string =
    const preCode = char(0xE2) & char(0x99)
    preCode & char([player1: 0x94, player2: 0x9A][piece.player] + int(piece.kind))

  func `$`(piece: Option[ObjPiece]): string =
    if Some(@piece) ?= piece: $piece
    else: " "

  func `$`(board: BoardLike): string =
    const sepLine = " ---".repeat(8) & "\n"
    for row in board:
      result.add sepLine
      for elem in row:
        result.add &"| {elem} "
      result.add "|\n"
    result.add sepLine

  func `not`*(player: ObjPlayer): ObjPlayer =
    case player
    of player1: player2
    of player2: player1

  func newPiece(kind: PieceKind, player: ObjPlayer): ObjPiece =
    ObjPiece(kind: kind, player: player)

  func continues*(game: Game): bool = game.state.kind == gameContinues

  const
    homeRow = [player1: 0, player2: 7]
    pawnRow = [player1: 1, player2: 6]
    pawnDir = [player1: 1, player2: -1]

    castleColInfo = [
      shortCastle: (
        rookOrigin: 7,
        rookTarget: 5,
        kingTarget: 6
      ),
      longCastle: (
        rookOrigin: 0,
        rookTarget: 3,
        kingTarget: 2
      )
    ]

    initBoard = block:
      var board: ObjBoard
      for player, row in pawnRow:
        let piece = newPiece(pawn, player)
        for col in 0 ..< 8:
          board[row][col] = some(piece)
      for player, row in homeRow:
        for i, pieceKind in [rook, knight, bishop]:
          let piece = newPiece(pieceKind, player)
          board[row][i]   = some(piece)
          board[row][7-i] = some(piece)
        board[row][4] = some(newPiece(king,  player))
        board[row][3] = some(newPiece(queen, player))
      board

  proc realClock*(game: Game): array[ObjPlayer, tuple[time: int, running: bool]] =
    if game.continues:
      for player, result in result.mpairs:
        result.time = game.clock[player]
        if game.nextMoves[player].isNone:
          result.time -= int(getTime().toUnix - game.turnStartTime)
          result.running = true
    else:
      for player, result in result.mpairs:
        result.time = game.clock[player]


  func subjective(a,b: ObjPlayer): SubjPlayer =
    if a == b: playerSelf
    else: playerOpponent

  iterator subjectivePair(player: ObjPlayer): (ObjPlayer, SubjPlayer) =
    yield (player, SubjPlayer.playerSelf)
    yield (not player, playerOpponent)

  func mapSubj[T](x: array[ObjPlayer, T], player: ObjPlayer): array[SubjPlayer, T] =
    for p, sp in player.subjectivePair:
      result[sp] = x[p]

  func subjective(pos: Pos, player: ObjPlayer): Pos {.inline.} =
    result = pos
    if player == player1:
      result.row = 7 - result.row

  func subjective*(move: MoveSelect, player: ObjPlayer): MoveSelect {.inline.} =
    result = move
    result.pos = result.pos.subjective(player)

  proc subjective*(game: Game, player: ObjPlayer): SubjGame =
    result = SubjGame(
      users: game.users.mapSubj(player),
      turnStartTime: game.turnStartTime,
      clock: game.realClock.mapSubj(player),
      captures: game.captures.mapSubj(player),
      nextMove:
        if Some(@move) ?= game.nextMoves[player]:
          StagedMoveSelect(stage: allSelected, move: move.subjective(player))
        else: StagedMoveSelect(stage: nothingSelected)
      ,
      prevMoveMarks: (
        game.prevMoveMarks.origins.mapIt(it.subjective(player)),
        game.prevMoveMarks.captures.mapIt(it.subjective(player))
      ),
      state:
        if game.state.kind != gameWon:
          cast[GameState[SubjPlayer]](game.state)
        else:
          GameState[SubjPlayer](
            kind: gameWon,
            by: subjective(player, game.state.by),
            resigned: game.state.resigned
          )
    )
    template mapBoard(fromId) =
      for i {.inject.} in 0 ..< 8:
        result.board[i] = game.board[fromId].mapIt(it.map do (piece: ObjPiece) -> auto:
          SubjPiece(
            kind: piece.kind,
            player: subjective(player, piece.player)
          )
        )
        result.possibleMoves[i] = game.possibleMoves[player][fromId]
        for moves in result.possibleMoves[i].mitems:
          for move in moves.mitems:
            move.pos = move.pos.subjective(player)
    case player
    of player1: mapBoard(7-i)
    of player2: mapBoard(i) 

  func `+`(a, b: Pos): Pos {.inline.} = (a.row + b.row, a.col + b.col)
  func `-`(a, b: Pos): Pos {.inline.} = (a.row - b.row, a.col - b.col)
  func `+`(a: Pos, b: int): Pos = a + (b, b)
  func `+=`(a: var Pos, b: Pos|int) = a = a + b

  func isOnBoard(pos: Pos): bool {.inline.} =
    pos.row >= 0 and pos.row < 8 and
    pos.col >= 0 and pos.col < 8

  type Occupation = enum notOccupied, selfOccupied, enemyOccupied, offBoard

  func occupation(board: ObjBoard, player: ObjPlayer, pos: Pos): Occupation {.inline.} =
    if isOnBoard(pos):
      if Some(@piece) ?= board[pos]:
        if piece.player == player: selfOccupied
        else: enemyOccupied
      else: notOccupied
    else:
      offBoard
   

  func updatePossibleMoves(game: var Game) =
    let board = game.board  # cant capture var Game in inner procs

    var kingPos = [player1: (-1, -1), player2: (-1, -1)]
    var attacked: array[ObjPlayer, BoardLike[bool]]

    for player, possibleMoves in game.possibleMoves.mpairs:

      proc newMove(pos: Pos, isAttack = true): Move =
        if isAttack:
          attacked[player][pos] = true
        Move(kind: basicMove, pos: pos)

      const
        straightDirs = @[(-1, 0), (1, 0), (0, -1), (0, 1)]
        diagonalDirs = @[(-1, -1), (-1, 1), (1, -1), (1, 1)]
        allDirs = straightDirs & diagonalDirs
        knightOffsets = collect:
          for a in [-1, 1]:
            for b in [-1, 1]:
              for (row, col) in [(1, 2), (2, 1)]:
                (row*a, col*b)

      proc possibleOneStep(pos: Pos, dirs: seq[Pos]): seq[Move] =
        for dir in dirs:
          let pos = pos + dir
          if pos.isOnBoard:
            result.add newMove(pos)

      proc possibleAnySteps(pos: Pos, dirs: seq[Pos]): seq[Move] =
        for dir in dirs:
          var blocked = false
          var pos = pos
          while true:
            pos += dir
            let occupation = board.occupation(player, pos)
            if blocked:
              if occupation != offBoard:
                result.add newMove(pos, isAttack = false)
              if occupation != notOccupied:
                break
            else:
              if occupation != offBoard:
                result.add newMove(pos)
              case occupation
              of notOccupied: discard
              of enemyOccupied: blocked = true
              else: break

      for rowi, row in board:
        for coli, piece in row:
          possibleMoves[rowi][coli] = @[]

          if (Some(@piece) ?= piece) and piece.player == player:
            let pos: Pos = (rowi, coli)

            case piece.kind
            of king:
              kingPos[player] = pos
              possibleMoves[pos] = pos.possibleOneStep(allDirs)
              for castleSide, can in game.canCastle[player]:
                let castleColInfo = castleColInfo[castleSide]
                if can and betweenAllIt(pos.col, castleColInfo.rookOrigin, board[(pos.row, it)].isNone):
                  possibleMoves[pos].add Move(
                    kind: castleMove,
                    castleSide: castleSide,
                    pos: (homeRow[player], castleColInfo.kingTarget)
                  )

            of queen:  possibleMoves[pos] = pos.possibleAnySteps(allDirs)
            of rook:   possibleMoves[pos] = pos.possibleAnySteps(straightDirs)
            of bishop: possibleMoves[pos] = pos.possibleAnySteps(diagonalDirs)

            of knight: possibleMoves[pos] = pos.possibleOneStep(knightOffsets)

            of pawn:
              proc addPawnMove(possibleMoves: var PossibleMoves, offset: Pos, occupation: set[Occupation], isAttack = false): bool =
                let newPos = pos + offset
                if board.occupation(player, newPos) in occupation:
                  possibleMoves[pos].add newMove(newPos, isAttack)
                  if newPos.row == homeRow[not player]:
                    possibleMoves[pos][^1].kind = pawnReplaceMove
                    if isAttack:
                      attacked[player][pos] = true
                  true
                else: false

              if possibleMoves.addPawnMove((pawnDir[player], 0), {notOccupied}) and pos.row == pawnRow[player]:
                discard possibleMoves.addPawnMove((pawnDir[player]*2, 0), {notOccupied})
              for x in [-1, 1]:
                discard possibleMoves.addPawnMove((pawnDir[player], x), {enemyOccupied, selfOccupied}, isAttack = true)

    for player, possibleMoves in game.possibleMoves.mpairs:
      assert kingPos[player] != (-1, -1)
      possibleMoves[kingPos[player]].keepItIf:
        not attacked[not player][it.pos] or
        ((Some(@piece) ?= game.board[it.pos]) and piece.player == player)


  proc newGame*(users: array[ObjPlayer, User], mode: GameMode): Game =
    result.users = users
    result.mode = mode
    let timeSec = mode.time * 60
    result.clock = [timeSec, timeSec]
    result.board = initBoard
    result.canCastle = [[true, true], [true, true]]
    result.updatePossibleMoves
    result.turnStartTime = getTime().toUnix

  proc restart*(game: var Game) =
    game = newGame(game.users, game.mode)

  func mode*(game: Game): GameMode = game.mode

  proc timeOver*(game: var Game) =
    let clock = game.realClock.mapIt(max(it.time, 0))
    let timeOver = clock.mapIt(it <= 0)
    game.state =
      if not timeOver[player1] and not timeOver[player2]:
        ObjGameState(kind: gameContinues)
      else:
        game.clock = clock
        game.nextMoves = [none(MoveSelect), none(MoveSelect)]
        if timeOver[player1] and timeOver[player2]:
          ObjGameState(kind: gameRemi)
        else:
          ObjGameState(kind: gameWon, by:
            if timeOver[player2]: player1
            else: player2
          )

  proc resign*(game: var Game, player: ObjPlayer) =
    if game.continues:
      game.state = ObjGameState(kind: gameWon, by: not player, resigned: true)


  # returns true if ready to do moves
  proc setMove*(game: var Game, player: ObjPlayer, move: MoveSelect): bool =
    if game.nextMoves[player].isNone:
      game.clock[player] -= int(getTime().toUnix - game.turnStartTime)
      game.nextMoves[player] = some(move)
      if game.nextMoves[not player].isSome:
        result = true

  iterator `..<`(a, b: Pos): Pos =
    let diff = b - a
    assert diff.row != 0 or diff.col != 0
    if diff.row != 0 and diff.col != 0:
      assert abs(diff.row) == abs(diff.col)
    let dir = (sgn(diff.row), sgn(diff.col))
    var pos = a
    for _ in 1 ..< max(abs(diff.row), abs(diff.col)):
      pos += dir
      yield pos

  proc move*(game: var Game) =

    game.prevMoveMarks = (@[], @[])

    proc captured(game: var Game, piece: ObjPiece) =
      inc game.captures[not piece.player][piece.kind]

    # collect moves
    var moves: array[ObjPlayer, tuple[origin: Pos, move: Move]]
    var replaceWith: array[ObjPlayer, PieceKind]
    for player, move in game.nextMoves:
      let move = move.get
      if not move.pos.isOnBoard or move.id >= len(game.possibleMoves[player][move.pos]):
        raise UnknownMoveError(msg: "unknown move")
      moves[player] = (move.pos, game.possibleMoves[player][move.pos][move.id])
      replaceWith[player] =
        if move.replaceWith in queen..knight: move.replaceWith
        else: queen

    # find piece that moves
    var pieces: array[ObjPlayer, ObjPiece]
    for player, (origin, move) in moves:
      pieces[player] =
        if move.kind == pawnReplaceMove:
          newPiece(replaceWith[player], player)
        else:
          game.board[origin].get

      game.prevMoveMarks.origins.add origin

      # do castle
      if move.kind == castleMove:
        let castleColInfo = castleColInfo[move.castleSide]
        game.board[homeRow[player]][castleColInfo.rookOrigin] = none(ObjPiece)
        game.board[homeRow[player]][castleColInfo.rookTarget] = some(newPiece(rook, player))
        game.canCastle[player][move.castleSide] = false
        game.prevMoveMarks.origins.add (homeRow[player], castleColInfo.rookOrigin)

      # update can-castle state
      if pieces[player].kind == rook and origin.row == homeRow[player]:
        for castleSide, colInfo in castleColInfo:
          if origin.col == colInfo.rookOrigin:
            game.canCastle[player][castleSide] = false
      elif pieces[player].kind == king:
        for castle in game.canCastle[player].mitems: castle = false

    # remove pieces from old positions
    for (origin, _) in moves:
      game.board[origin] = none(ObjPiece)

    # handle obstacles
    var attacking = none(ObjPlayer)
    for player, (origin, move) in moves.mpairs:
      if pieces[player].kind notin {knight, king}:  # including king is just easy fix to handle castle. and king just moves 1 otherwise anyways
        for pos in origin ..< move.pos:
          if moves[not player].move.pos == pos:
            assert attacking.isNone
            attacking = some(player)
          elif game.board[pos].isNone: continue
          move.pos = pos
          break

    # place at new position and update captures
    if moves[player1].move.pos != moves[player2].move.pos:
      assert attacking.isNone
      for player, (_, move) in moves:
        let target = move.pos
        if Some(@piece) ?= game.board[target]:
          game.captured piece
          game.prevMoveMarks.captures.add target
        game.board[target] = some(pieces[player])

    # special case: both moved to same place
    else:
      let pos = moves[player1].move.pos
      game.prevMoveMarks.captures.add pos
      # self-capture case
      if Some(@piece) ?= game.board[pos]:
        game.captured piece
        game.captured pieces[not piece.player]
        game.board[pos] = some(pieces[piece.player])
      # normal case
      else:
        if Some(@player) ?= attacking:
          game.board[moves[player].move.pos] = some(pieces[player])
          game.captured pieces[not player]
        else:
          for player in ObjPlayer:
            game.captured pieces[not player]

    let won = [
      player1: game.captures[player1][king] > 0,
      player2: game.captures[player2][king] > 0
    ]
    game.state =
      if won[player1] and won[player2]: ObjGameState(kind: gameRemi)
      elif won[player1]: ObjGameState(kind: gameWon, by: player1)
      elif won[player2]: ObjGameState(kind: gameWon, by: player2)
      else:
        # prepare next round
        game.updatePossibleMoves
        game.nextMoves = [none(MoveSelect), none(MoveSelect)]
        ObjGameState(kind: gameContinues)

    game.turnStartTime = getTime().toUnix