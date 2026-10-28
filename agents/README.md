# Agent instructions

What `macbox agents install` wires up for coding agents (Claude Code, Codex, and agents in T3 Code), and how to do it by hand.

- **`simulators-snippet.md`**: the "Simulators" section for the agent's global instructions (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`). The installer puts it between its `<!-- macbox:simulators begin/end -->` markers, replacing an earlier copy, and leaves the rest of the file alone.
- **`hooks/route-simulator.sh`**: a Claude Code `UserPromptSubmit` hook. When a prompt mentions a simulator, an emulator or a phone, it reminds the agent to read the `simulators` skill. Add it to `~/.claude/settings.json`:

  ```json
  {
    "hooks": {
      "UserPromptSubmit": [
        { "hooks": [ { "type": "command", "command": "/path/to/macbox/agents/hooks/route-simulator.sh" } ] }
      ]
    }
  }
  ```

- **Skills**: `skills/simulators` and `skills/phone-builds` are linked into `~/.claude/skills/` and `~/.agents/skills/`.
- **Commands**: `sims/bin/mac-sim` (it finds `mac-sim-remote` beside its real path and copies it to the Mac), `sim-fps`, `android-sim`, `android-gpu-desktop` and `skills/phone-builds/bin/phone-build` are linked into `~/.local/bin/`.
- **User units**: `sims/systemd/mac-sim-idle.{service,timer}` (enable the timer) and, with the Android part, `android-gpu-desktop.service`.
