const
  maxPlayerNameLen = 12
  defaultPlayerName = "?"

type
  User* = ref object
    name: string

func `$`*(user: User): string = user.name


when not defined(js):

  import ./utils

  func newGuestUser*(name: string): User =
    var name = name.filterIt(it in {'a'..'z', 'A'..'Z', '0'..'9', '.', '-', '_', ' '})
    if len(name) == 0:
      name = defaultPlayerName
    elif len(name) > maxPlayerNameLen:
      name = name[0 ..< maxPlayerNameLen]
    User(name: name)