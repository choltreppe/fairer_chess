
template filterIt*(s: string, cond): string =
  var result: string
  for it {.inject.} in s:
    if cond: result.add it
  result

template findIt*(a: openarray[auto], cond: untyped): int =
  var result = -1
  for i, it {.inject.} in a:
    if cond:
      result = i
      break
  result

template betweenAllIt*(a, b: int, body: untyped): bool =
  var res = true
  if a < b:
    for it {.inject.} in a+1 ..< b:
      if not body:
        res = false
        break
  elif b < a:
    for it {.inject.} in b+1 ..< a:
      if not body:
        res = false
        break
  res

iterator revPairs*[T](elems: openarray[T]): (int, T) =
  for i in countdown(high(elems), low(elems)):
    yield (i, elems[i])