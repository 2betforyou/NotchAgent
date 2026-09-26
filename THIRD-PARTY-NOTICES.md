# Third-party notices

## SwiftTerm

- Upstream: https://github.com/migueldeicaza/SwiftTerm
- Version: v1.13.0
- Commit: `8e7a1e154f470e19c709a00a8768df348ba5fc43`
- License: MIT; full license in `Vendor/SwiftTerm/LICENSE` and bundled `SwiftTerm-LICENSE.txt`.
- The vendored package manifest is reduced to the macOS library target, excluding upstream tools and benchmark dependencies.
- Metal shader source is copied as a resource, using upstream's runtime-compilation fallback when needed. This avoids requiring the optional Metal build toolchain. The macOS terminal defaults to the native CPU renderer.
- Local source patch: `MacLocalTerminalView.clipboardCopy` is `open` rather than `public`, allowing NotchAgent to reject unsolicited OSC 52 clipboard writes. Manual copy/paste remains supported.

NotchAgent's notch UI and window behavior are independently implemented. SwiftTerm is the only third-party code included.

## External programs and marks

- Agent names (Codex, Claude Code, Gemini CLI) identify external programs and do not imply endorsement or affiliation.
- The small agent marks in the app are simplified drawings made in code for identification, not the official logos, and are not bundled image assets.
- CLI tools and `git` are not bundled. NotchAgent runs the copies installed on the user's Mac and talks to Claude Code and Codex only through their documented extension points (Claude Code `--settings` hooks and status line, Codex `-c notify`), for sessions opened in NotchAgent.
