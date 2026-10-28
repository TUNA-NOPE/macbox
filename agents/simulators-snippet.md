<!-- macbox:simulators begin -->
## Simulators
Read the `simulators` skill before you start one. Every simulator runs on this machine:
- **iOS:** `mac-sim`, iOS Simulators on macbox's macOS VM (`ssh macbox`), with a pool so each checkout gets its own: slim ones for most work, `--full` for widgets, Live Activities and the Dynamic Island, `--sharp` for real-iPhone-pixel screenshots. In T3 Code, open yours in the user's Device panel with `device_open`, using the `hostId` and `deviceId` that `mac-sim t3` prints.
- **Android** (if set up): `android-sim`, local emulators, one per checkout, so don't wait for another agent's. In T3 Code, open yours in the Device panel with `device_open` (`hostId` `local`, the serial `android-sim serial` prints). Leave an emulator alone if the user opened it from the panel.
- **Web:** run it here (`npx expo start --web`, or the project's own dev server) and look at it in T3 Code's browser.
- **Verify every UI change in the simulator:** run it, take a screenshot and look at it, record the whole flow and check with `sim-fps` that it holds 60 fps with no dropped frames. The skill has the loop and the checklist.
- Close it when the task is done: `mac-sim down` / `android-sim down`.
- If the Mac doesn't answer: `macbox status`, then `macbox up`.
- **A real phone** (an `.ipa` for the user's iPhone, TestFlight, an `.apk`): the `phone-builds` skill (`phone-build`). Free EAS cloud builds go first, then the build runs here.
<!-- macbox:simulators end -->
