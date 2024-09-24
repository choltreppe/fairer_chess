import std/[strformat, os]
import nake


var release = false

proc buildStyles =
  let sassCmd = "sassc --style=" & (if release: "compressed" else: "expanded")
  direShell sassCmd, "sass/main.sass", "build/static/style.css"

proc buildClient =
  const
    path = "src/client/main.nim"
    outDir ="build/static"
    outPath = outDir/"client.js"
    outPathMin = outPath.changeFileExt("client.min.js")

  let extraOpts =
    if release: "-d:release"
    else: ""

  direShell &"nim js {extraOpts} -o:{outPath} {path}"
  if release:
    #[direShell "uglifyjs",
      outPath,
      "-o", outPathMin,
      "--compress --mangle --toplevel"]#
    direShell "terser",
      outPath,
      "-o", outPathMin,
      "-c -m"
    direShell "mv", outPathMin, outPath

proc buildServer =
  let cmd =
    if release: "nim musl -d:pcre -d:release"
    else: "nim c"
  direShell cmd,
    "-o:build/server",
    "src/server/main.nim"

task "build", "build website":
  buildStyles()
  buildClient()
  buildServer()

task "buildRelease", "build website for release":
  release = true
  runTask "build"

task "run", "build and run website":
  runTask "build"
  echo "run .."
  direShell "./build/server"