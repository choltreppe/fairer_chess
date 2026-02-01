when defined(release):
  const target = "x86_64-linux-gnu.2.17"

  --cc:clang
  --clang.exe:zigcc
  --clang.linkerexe:zigcc
  switch("passc", "-target "&target)
  switch("passl", "-target "&target)
  --forceBuild:on