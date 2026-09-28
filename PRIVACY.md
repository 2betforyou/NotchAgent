# NotchAgent 개인정보 처리방침

- 시행일: 2026년 9월 26일
- 적용 대상: NotchAgent 0.1.0 이상 (macOS 앱)
- 문의: june295921@gmail.com

[English version below](#english)

## 요약

NotchAgent는 개인정보를 수집하지 않으며, 어떤 정보도 개발자나 제3자의 서버로 보내지 않습니다. 계정, 분석, 광고, 텔레메트리, 자동 업데이트 서버가 없습니다. 아래에 적은 정보는 모두 사용자의 Mac 안에만 저장되고, 앱 안에서만 쓰입니다.

## 기기에 저장하는 정보

macOS 환경설정(`~/Library/Preferences/app.notchagent.desktop.plist`)에 다음을 저장합니다.

- 사용자가 추가한 작업 폴더 경로와 그 순서, 현재 선택한 작업 폴더
- 화면·호버·알림·로그인 시 실행 등 앱 설정
- 단축키, 언어, 강조색·터미널 테마·글꼴·글자 크기
- 사용자가 직접 입력한 CLI 실행 파일 경로
- 사용량 표시 사용 여부, 첫 실행 안내 완료 여부
- 세션 복원을 켠 경우: 열려 있던 탭의 종류(Terminal·Codex·Claude Code·Gemini CLI), 폴더, 순서, 터미널이 보고한 작업 제목과 사용자가 정한 탭 이름, 그리고 대화를 정확히 이어 열기 위한 각 CLI의 대화 ID(Claude Code 세션 ID, Codex 스레드 ID). 대화 본문은 저장하지 않으며, 이어 열기는 각 CLI가 스스로 보관한 기록을 사용합니다.

Claude 사용량 표시를 켠 경우에만 `~/Library/Application Support/NotchAgent/claude-rate-limits.json`에 5시간·주간 한도 사용률과 초기화 시각을 저장합니다. 이 기능을 끄면 파일을 삭제합니다.

NotchAgent는 터미널 입력·출력 본문, 명령 기록, 대화 본문, API 키, 로그인 토큰을 저장하지 않습니다. 탭 제목은 위 세션 복원 정보에 포함됩니다.

최근 활동은 에이전트 종류, 작업 제목, 폴더 이름, 이벤트, 시각, 읽음 상태를 앱 실행 중 메모리에 최대 50개 보관합니다. 앱을 종료하면 비워집니다. 알림 센터를 켜면 이 중 종류·제목·폴더·이벤트를 macOS 로컬 알림으로 전달하며, 알림 기록은 macOS에서 관리합니다.

파일 경로가 없는 이미지나 스크린샷을 끌어놓으면 macOS 임시 폴더 아래 `NotchAgent-Drops`에 파일을 받아 경로를 터미널에 입력합니다. Finder 파일은 복사하지 않고 원래 경로를 사용합니다. 임시 파일은 세션이 읽을 수 있도록 유지되며 macOS의 임시 파일 정리 대상입니다. 클립보드는 변경하지 않습니다.

앱 데이터는 위 환경설정·지원 폴더와 임시 파일을 지워 제거할 수 있습니다. 이미 표시된 시스템 알림은 알림 센터에서 지울 수 있습니다.

## 사용자가 실행하는 프로그램

터미널에서 실행한 셸과 CLI(Codex, Claude Code, Gemini CLI 등)는 사용자 계정 권한으로 동작합니다. 이들 프로그램의 네트워크 통신, 파일 접근, 기록 저장은 각 프로그램의 약관과 개인정보 처리방침을 따릅니다. NotchAgent는 이들의 승인·샌드박스 설정을 바꾸지 않습니다.

## 에이전트 상태 신호

노치에 "작업 중", "완료", "확인 필요"를 정확히 표시하고 대화를 이어 열기 위해, NotchAgent에서 연 세션에 한해 각 CLI의 공식 확장 기능을 씁니다. 전역 설정 파일은 바꾸지 않습니다.

- **Claude Code**: 세션 시작, 요청 제출, 응답 종료, 알림 때 실행되는 훅을 추가합니다. 훅이 넘겨주는 정보 중 이벤트 종류, 알림 종류, 세션 ID만 사용합니다. 함께 전달되는 작업 폴더·대화 기록 경로·마지막 응답 같은 나머지 정보는 읽어 들인 즉시 버리며 저장하지 않습니다. 사용자가 설정한 기존 훅은 그대로 함께 실행됩니다.
- **Codex**: 응답이 끝날 때 실행되는 `notify` 프로그램으로 NotchAgent를 지정합니다. 전달되는 정보 중 이벤트 종류와 스레드 ID만 사용하고, 요청·응답 내용은 저장하지 않습니다. 사용자가 이미 `notify` 프로그램을 설정해 두었다면 같은 정보를 그대로 그 프로그램에 전달합니다.

이 신호는 macOS의 로컬 알림으로 앱에 전달되며 Mac 밖으로 나가지 않습니다.

## 사용량 표시 (선택)

- **Codex**: 켠 경우에만 5분마다 기기에 설치된 `codex app-server`를 읽기 전용 모드로 실행해 계정 플랜과 남은 한도를 읽습니다. 통신은 Codex CLI가 기존 로그인으로 OpenAI와 직접 수행합니다. NotchAgent는 결과를 화면에만 표시하고 저장하거나 다른 곳으로 보내지 않습니다.
- **Claude Code**: 켠 경우에만 NotchAgent에서 여는 Claude Code 세션의 상태 표시줄 명령을 NotchAgent로 지정합니다. 전달되는 정보 중 한도 사용률과 초기화 시각만 위 파일에 저장하고, 나머지는 저장하지 않은 채 사용자가 원래 설정한 상태 표시줄 명령에 그대로 넘깁니다.

NotchAgent는 키체인이나 로그인 정보를 읽지 않습니다. 두 기능 모두 설정에서 언제든 끌 수 있습니다.

## git worktree

사용자가 작업 폴더 메뉴에서 요청한 경우에만 로컬 `git` 명령(`git worktree add`, `git worktree remove`)을 실행합니다. 커밋하지 않은 변경이 있는 worktree는 지우지 않습니다.

## 진단 로그

문제 해결을 위해 macOS 시스템 로그에 오류 종류와 이벤트만 기록합니다(예: "단축키 등록 실패"). 터미널 내용, 파일 경로, 계정 정보는 기록하지 않으며, 로그는 Mac 밖으로 전송되지 않습니다. 버그를 신고할 때 사용자가 직접 확인하고 첨부할 수 있습니다.

## 권한

손쉬운 사용, 화면 기록, 연락처, 위치, 카메라, 마이크 권한을 요청하지 않습니다. 원격 프로그램이 클립보드를 덮어쓰는 기능(OSC 52)은 차단합니다. 로그인 시 실행은 사용자가 설정에서 켠 경우에만 등록합니다.

macOS 알림 권한은 사용자가 알림 센터 옵션을 켰을 때만 요청합니다. 알림 센터와 소리는 기본적으로 꺼져 있습니다.

## 아동의 개인정보

NotchAgent는 개인정보를 수집하지 않으므로 아동의 개인정보도 수집하지 않습니다.

## 변경

이 방침이 바뀌면 이 문서와 저장소의 변경 기록으로 알립니다. 중요한 변경은 릴리스 노트에도 적습니다.

## 문의

개인정보와 관련한 질문이나 요청은 june295921@gmail.com 으로 보내 주세요.

---

<a id="english"></a>
# NotchAgent Privacy Policy

- Effective: September 26, 2026
- Applies to: NotchAgent 0.1.0 and later (macOS app)
- Contact: june295921@gmail.com

## Summary

NotchAgent does not collect personal information and sends nothing to the developer or to any third-party server. There are no accounts, analytics, ads, telemetry, or update servers. Everything listed below stays on your Mac and is used only by the app.

## Stored on your Mac

In macOS preferences (`~/Library/Preferences/app.notchagent.desktop.plist`):

- The work folders you added, their order, and the current folder
- App settings such as display, hover, notices, and launch at login
- Shortcut, language, accent color, terminal theme, font, and size
- CLI executable paths you entered
- Whether usage display is on, and whether onboarding was completed
- With session restore on: each open tab's kind, folder, order, terminal-reported task title, custom tab name, and CLI conversation id (Claude Code session id, Codex thread id). Conversation bodies are not stored; resuming uses each CLI's own history.

Only with Claude usage display on, the 5-hour and weekly usage percentages and reset times are stored in `~/Library/Application Support/NotchAgent/claude-rate-limits.json`. Turning the feature off deletes the file.

NotchAgent never stores terminal input/output bodies, command history, conversation bodies, API keys, or sign-in tokens. Tab titles are included in the restoration metadata above.

Recent activity keeps up to 50 events in memory while the app runs: agent, task title, folder name, event, time, and read state. It clears on quit. If Notification Center is enabled, the agent, title, folder, and event are passed to macOS local notifications; macOS manages that notification history.

Dropped images or screenshots without an existing file path are received under `NotchAgent-Drops` in the macOS temporary directory, and their paths are inserted into the terminal. Finder files use their original paths and are not copied. Temporary files remain available for the CLI and are subject to macOS temporary-file cleanup. The clipboard is not changed.

The preferences, support folder, and temporary files above can be removed to delete app data. Existing system notifications can be cleared in Notification Center.

## Programs you run

Shells and CLIs you run (Codex, Claude Code, Gemini CLI, and others) act with your user account's permissions. Their network access, file access, and history follow their own terms and privacy policies. NotchAgent does not change their approval or sandbox settings.

## Agent status signals

To show "working", "finished", and "needs you" precisely in the notch and to reopen conversations, NotchAgent uses each CLI's official extension points, only for sessions opened in NotchAgent. Global configuration files are not modified.

- **Claude Code**: hooks run on session start, prompt submit, turn end, and notifications. NotchAgent uses only the event name, notification type, and session id. Everything else in the hook input (working directory, transcript path, last message) is discarded immediately and never stored. Your own hooks keep running alongside.
- **Codex**: NotchAgent is set as the `notify` program that runs when a turn ends. Only the event type and thread id are used; prompts and replies are not stored. If you already configured a `notify` program, it receives the same payload unchanged.

These signals reach the app as local macOS notifications and never leave your Mac.

## Usage display (optional)

- **Codex**: when on, every 5 minutes NotchAgent runs your installed `codex app-server` in read-only mode to read your plan and remaining limits. The Codex CLI talks to OpenAI with your existing sign-in. Results are only displayed, never stored or sent elsewhere.
- **Claude Code**: when on, NotchAgent becomes the status line command for Claude Code sessions opened in NotchAgent. Only the usage percentages and reset times are stored (file above); the rest is passed unchanged to your own status line command without being stored.

NotchAgent never reads the Keychain or sign-in data. Both features can be turned off in Settings at any time.

## Git worktrees

Only when you ask from a folder's menu, NotchAgent runs local `git worktree add` or `git worktree remove`. A worktree with uncommitted changes is never deleted.

## Diagnostic log

For troubleshooting, NotchAgent writes error kinds and events to the macOS system log (for example, "shortcut registration failed"). It never logs terminal content, file paths, or account data, and the log never leaves your Mac unless you attach it to a bug report yourself.

## Permissions

NotchAgent does not request Accessibility, Screen Recording, Contacts, Location, Camera, or Microphone access. It blocks remote programs from overwriting the clipboard (OSC 52). Launch at login is registered only when you turn it on.

macOS notification permission is requested only when you enable Notification Center. Notification Center and sound are off by default.

## Children's privacy

NotchAgent collects no personal information, including from children.

## Changes

Changes to this policy are published in this document and its history in the repository, and important changes are noted in release notes.

## Contact

For privacy questions or requests, email june295921@gmail.com.
