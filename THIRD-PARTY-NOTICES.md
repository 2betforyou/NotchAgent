# Third-party notices

## SwiftTerm

- Upstream: https://github.com/migueldeicaza/SwiftTerm
- Version: v1.13.0
- Commit: `8e7a1e154f470e19c709a00a8768df348ba5fc43`
- License: MIT; full license in `Vendor/SwiftTerm/LICENSE` and bundled `SwiftTerm-LICENSE.txt`.
- The vendored package manifest is reduced to the macOS library target, excluding upstream tools and benchmark dependencies.
- Metal shader source is copied as a resource, using upstream's runtime-compilation fallback when needed. This avoids requiring the optional Metal build toolchain. The macOS terminal defaults to the native CPU renderer.
- Local source patch: `MacLocalTerminalView.clipboardCopy` is `open` rather than `public`, allowing NotchAgent to reject unsolicited OSC 52 clipboard writes. Manual copy/paste remains supported.
- Backported [SwiftTerm PR #578](https://github.com/migueldeicaza/SwiftTerm/pull/578) to center full-width CJK glyphs in their cells and size the cursor to cover the full character.

NotchAgent's notch UI and window behavior are independently implemented. SwiftTerm is the only third-party code included.

## External programs and marks

- Agent names (Codex, Claude Code, Gemini CLI) identify external programs and do not imply endorsement or affiliation.
- Agent marks are bundled first-party assets for identification: [Claude](https://claude.com) ([asset](https://assets.claude.com/95a868946ac8a31e5ff832e2899f294aa368b836.png)), [Gemini](https://gemini.google.com) ([asset](https://www.gstatic.com/lamda/images/gemini_sparkle_4g_512_lt_f94943af3be039176192d.png)), and the [OpenAI Blossom](https://openai.com/brand/) for Codex ([SVG source](https://images.ctfassets.net/kftzwdyauwt9/3M8rPrJsENQL5tjaDzo6SL/f0f85c8e27090123c767ac3c8237b401/Blossom_Dark.svg)). The Blossom path is isolated from the source's construction diagram, with its original shape and white fill preserved. These marks remain the property of their respective owners; the project's software license does not grant trademark rights. No affiliation or endorsement is implied.
- CLI tools and `git` are not bundled. NotchAgent runs the copies installed on the user's Mac and talks to Claude Code and Codex only through their documented extension points (Claude Code `--settings` hooks and status line, Codex `-c notify`), for sessions opened in NotchAgent.
