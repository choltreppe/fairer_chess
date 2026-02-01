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
    direShell "closure-compiler",
      "--js", outPath,
      "--js_output_file", outPathMin,
      "--assume_function_wrapper"
    direShell "mv", outPathMin, outPath

proc buildServer =
  direShell "nim c",
    if release: "-d:release" else: "",
    "-o:build/server",
    "src/server/main.nim"

task "build", "build website (debug)":
  buildStyles()
  buildClient()
  buildServer()

task "buildRelease", "build website for release":
  release = true
  runTask "build"

task "run", "build and run website (debug)":
  runTask "build"
  echo "run .."
  direShell "./build/server"