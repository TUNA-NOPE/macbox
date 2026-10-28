#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook: when a prompt mentions a simulator, point the agent at
# the simulators skill. Prints nothing for any other prompt. Needs jq.
# The word list has English and Hebrew; add your own language's words to it.
prompt=$(jq -r '.prompt // ""' 2>/dev/null)
if printf '%s' "$prompt" | grep -qiE 'simulator|emulator|mac-sim|android-sim|android|iphone|ipad|ios app|סימולטור|סימולאטור|סימולטר|אמולטור|אנדרואיד|אנדרויד|אייפון'; then
  jq -n --arg ctx "Simulators on this machine: read the simulators skill first. iOS: mac-sim (iOS Simulators on macbox's macOS VM, one per checkout; --full for widgets/Live Activities/Dynamic Island, --sharp for real-iPhone-pixel stills). Android: android-sim (local emulators, one per checkout). Web: run it locally and look at it in T3 Code's browser (preview_* tools). In T3 Code, show the device in the user's Device panel with device_open (mac-sim t3 prints the ids; Android: hostId local, android-sim serial). After every UI change: run it, screenshot and look, record the whole flow and check that sim-fps reports 60 fps with no dropped frames. Close it when the task is done (mac-sim down / android-sim down)." \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
fi
exit 0
