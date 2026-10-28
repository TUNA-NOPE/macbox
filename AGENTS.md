# For an agent setting up macbox

You're asked to give this Linux host a macOS VM with Xcode, iOS Simulators and T3 Code's Device
panel. You can do almost all of it yourself, including the steps in macOS's GUI. Work through
`./macbox next` until every line is ticked; [docs/setup.md](docs/setup.md) explains each step.

## Ground rules

- **Ask the user before you change the host itself:** packages, groups (`usermod`), sysctl,
  Docker's installation. `./macbox doctor` says what's missing; show them the commands.
- **Never ask for a password in chat, and never put one in a command line.** The macOS user's
  password is typed into the VM. Have the user type it into the VM's screen, or, if they give it
  to you through a channel they choose, pipe it: `./macbox type -` reads stdin.
- **An Apple Account is the user's.** macbox never signs in to one. Downloading Xcode's `.xip` needs
  a sign-in at developer.apple.com: ask the user to download it and tell you the path.
- **Apple's license:** macOS's license allows it only on Apple hardware. Make sure the user knows
  before you install it (README, "License and legal").
- `./macbox build` takes 20 to 60 minutes and installing macOS another 30 to 60. Run them in the
  background and report progress, rather than waiting in silence.

## The GUI steps, as an agent

The VM's screen is `./macbox screenshot /tmp/s.png`; look at the PNG. Coordinates are the guest's
pixels at the current resolution (`./macbox status`).

```sh
./macbox screenshot /tmp/s.png           # look
./macbox click 960 540                   # left click; add right or double
./macbox type 'Disk Utility'             # US keyboard layout
./macbox key ret                         # ret, tab, esc, space, up, down, meta-space, meta-q, ctrl-c ...
./macbox scroll 960 540 5                # 5 notches down (negative: up)
./macbox wait 120 /tmp/s.png             # wait up to 120 s for the screen to change, then a screenshot
```

Take a screenshot after every action and check that it did what you meant before the next one.
Installing macOS restarts the VM several times; `wait` is the way to sit through it.

The sequence:
1. `./macbox create`, `./macbox boot-picker on`, `./macbox up`.
2. Recovery: Disk Utility → View → Show All Devices → "QEMU HARDDISK Media" → Erase (APFS, GUID) →
   quit → Reinstall macOS → the disk → agree → wait (30 to 60 min, several restarts; leave OpenCore's
   menu to its default).
3. When Setup Assistant or a broken desktop shows: `./macbox down && ./macbox up`, stop OpenCore's
   countdown with an arrow key, choose Recovery, Utilities → Terminal, then `./macbox recovery-fix`.
   It reboots; choose macOS.
4. Setup Assistant: country, keyboard, skip the Apple Account, an administrator named `dev`. The
   user picks the password and types it, or gives it to you as above. Turn off Location Services,
   analytics, Screen Time and Siri.
5. Open Terminal (`./macbox key meta-space`, type `Terminal`, `ret`), then `./macbox ssh-bootstrap`;
   the password again, then `ssh macbox true`.
6. Optional, in System Settings > General > Sharing: the (i) next to Remote Login, "Allow full
   disk access for remote users" on.

From there everything is over SSH: `./macbox down`, `./macbox disk nvme`,
`./macbox boot-picker off`, `./macbox up`, `./macbox provision` (sudo asks for the password once,
in an interactive terminal: if you have none, ask the user to run that one command), the user's
`.xip` with `./macbox xcode <path>`, `./macbox pool`, `./macbox t3 register` (then open the Device
panel once and `./macbox t3 fix-hub`), `./macbox agents install`.

## When you're done

`./macbox next` shows every step ticked. Check it end to end from an Expo app's checkout:

```sh
mac-sim up && mac-sim run && mac-sim shot /tmp/home.png && mac-sim down
```

Look at `/tmp/home.png`. If the user runs T3 Code, open the simulator in their Device panel with
`device_open`, using the ids `mac-sim t3` prints.
