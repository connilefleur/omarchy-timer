# Omarchy Timer

A countdown timer for the [Omarchy](https://omarchy.org) bar. When it ends, it can
**stop whatever is playing** (music, YouTube, a movie), **stop playback and suspend
the computer**, or ring an alarm that keeps going until you stop it.

Good for falling asleep to a video, steeping tea, or a quick focus block.

![Picking what happens when the timer ends](preview.png)

## Features

- **Stop playback.** Pauses every playing media player at once: Chromium, Firefox,
  Spotify, mpv, and anything else that supports MPRIS. These are the same players
  your media keys control.
- **Stop playback & suspend.** Pauses media, then puts the computer to sleep after a
  15-second countdown you can cancel. Omarchy locks the screen on the way down.
- **Alarm sounds.** Alarm clock, Bell, Ringtone, or Chime. The sound loops until you
  press Esc, click the notification, or click the timer icon.
- **Notification only.** A silent notification and nothing else.
- **Styled like Omarchy.** The prompt matches Omarchy's reminder prompt. The bar icon
  sits with the other indicators next to the clock and stays hidden until a timer is
  running.
- **Pause, resume, extend, cancel.** From the bar, the popup, or the command line.
- **Survives restarts.** A running timer keeps going through a shell restart or a
  plugin reload.

## Requirements

- Omarchy 4 (the Quickshell-based `omarchy-shell` with plugin support)
- `pipewire-audio` for `pw-play` (installed on Omarchy by default)
- `sound-theme-freedesktop` for the alarm sounds (installed on Omarchy by default)

## Install

```bash
omarchy plugin add https://github.com/connilefleur/omarchy-timer.git
omarchy plugin enable io.github.connilefleur.timer --after omarchy.indicators
```

This puts the icon in the center of the bar, right after the other indicators
(reminder, night light, do not disturb). New plugins install disabled so you can
read the code first, and the second command enables it in that spot.

## Usage

1. Hover the center of the bar to reveal the timer icon, then click it.
2. Type the minutes and press **Enter**.
3. Choose what happens when the timer ends and press **Enter** (or click a row).

While the timer runs, the bar shows the time left. Click the icon again to pause,
add time, start a new timer, or cancel.

### Durations

Minutes are the default unit, but other formats work too:

| You type  | Timer        |
| --------- | ------------ |
| `25`      | 25 minutes   |
| `0.5`     | 30 seconds   |
| `1,5`     | 1 min 30 s   |
| `1h30`    | 1 h 30 min   |
| `90s`     | 90 seconds   |
| `2m30s`   | 2 min 30 s   |
| `10:00`   | 10 minutes   |

Decimals work with a dot or a comma (`0.5`, `0,5`, `.5`). Pressing **Enter** on an
empty prompt reuses your last duration.

### When the timer ends

| Option              | What happens                                                  |
| ------------------- | ------------------------------------------------------------- |
| Stop playback       | Pauses all playing media and shows a notification             |
| Stop playback & suspend | Pauses all playing media, then suspends after a 15 s countdown |
| Alarm clock         | Loops the alarm sound until stopped                           |
| Bell                | Loops a bell until stopped                                    |
| Ringtone            | Loops a phone ringtone until stopped                          |
| Chime               | Loops a short chime until stopped                             |
| Notification only   | Shows a notification, no sound                                |

When an alarm rings, a **Timer done** card appears on the focused monitor, the
bar icon blinks, and a notification stays up until clicked. Any of these stops it:
**Esc**, **Enter**, a click on the card, the notification, or the bar icon.

With **Stop playback & suspend**, the card counts down "Suspending in 15 s" instead.
The same actions cancel the suspend, so it never puts the computer to sleep while
you're still using it. The option is hidden when suspend is turned off in Omarchy
(`omarchy toggle suspend`). If the shell restarts during the countdown, the
countdown picks up where it was instead of suspending right away.

### Keys in the popup

| Key                     | Action                                          |
| ----------------------- | ----------------------------------------------- |
| `Enter`                 | Confirm                                         |
| `Esc`                   | Go back or close (stops an alarm or a suspend)  |
| `↑` `↓` / `j` `k` / Tab | Move through the list                           |
| `1`–`7`                 | Choose a row directly                           |
| `Space`                 | Preview the highlighted alarm sound             |
| `Backspace`             | Edit the minutes / go back a step               |

### Mouse on the bar icon

| Action       | Idle                   | Running / paused        | Ringing / suspending |
| ------------ | ---------------------- | ----------------------- | -------------------- |
| Left click   | Set a timer            | Manage the timer        | Stop / cancel        |
| Right click  | Restart the last timer | Pause / resume          | Stop / cancel        |
| Middle click |                        | Cancel                  | Stop / cancel        |
| Scroll       |                        | Add / remove one minute |                      |

## Keybinding

Open the timer prompt from the keyboard by adding a binding to
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + T", "Timer", "omarchy-shell io.github.connilefleur.timer open")
```

## Command line

Every action is also available over shell IPC, for scripts and keybindings:

```bash
omarchy-shell io.github.connilefleur.timer open                     # show the prompt
omarchy-shell io.github.connilefleur.timer start 25                 # start with the last alarm choice
omarchy-shell io.github.connilefleur.timer startWith 45 stop-playback
omarchy-shell io.github.connilefleur.timer restart                  # repeat the last timer
omarchy-shell io.github.connilefleur.timer toggle                   # pause / resume
omarchy-shell io.github.connilefleur.timer add 5                    # add 5 minutes
omarchy-shell io.github.connilefleur.timer cancel
omarchy-shell io.github.connilefleur.timer stop                     # stop an alarm or cancel a suspend
omarchy-shell io.github.connilefleur.timer suspendNow               # skip the suspend countdown
omarchy-shell io.github.connilefleur.timer status                   # JSON
omarchy-shell io.github.connilefleur.timer alarms                   # list alarm ids
```

Alarm ids: `stop-playback`, `stop-and-suspend`, `alarm-clock`, `bell`, `ringtone`,
`chime`, `silent`.

## Configure

The bar entry in `~/.config/omarchy/shell.json` accepts one setting:

| Key          | Default | Description                                            |
| ------------ | ------- | ------------------------------------------------------ |
| `alwaysShow` | `false` | Keep the idle icon visible instead of hiding it        |

```bash
omarchy bar set io.github.connilefleur.timer alwaysShow true --json
```

Move the icon like any other widget:

```bash
omarchy bar move io.github.connilefleur.timer --section right
```

## How it works

- `Service.qml` holds the single timer shared by every monitor's bar. It counts
  down against the wall clock, so time spent in suspend still counts.
- **Stop playback** calls `pause()` on every playing MPRIS player through
  Quickshell's MPRIS service. Players that don't support MPRIS are not affected.
- **Suspend** runs `systemctl suspend`, the same command as Omarchy's
  System > Suspend menu item. Omarchy's sleep hook locks the session first.
- Sounds come from `/usr/share/sounds/freedesktop/stereo/` and play through `pw-play`.
- Notifications go through `omarchy-notification-send`.
- The timer state is saved in `~/.local/state/omarchy/timer.json`.

The plugin makes no network requests and never needs `sudo`. Suspend goes through
logind like any other session suspend.

## Update

```bash
omarchy plugin update io.github.connilefleur.timer
```

## Remove

```bash
omarchy plugin remove io.github.connilefleur.timer
rm -f ~/.local/state/omarchy/timer.json   # optional: forget the saved state
```

## Files

```
manifest.json    Plugin manifest (schemaVersion 1)
Service.qml      Timer state, alarms, media control, persistence, IPC
BarWidget.qml    Bar icon and countdown
Flow.qml         Set-timer prompt, manage list, and "Timer done" / suspend card
TimerModel.js    Duration parsing, formatting, and the alarm list
```

## License

[MIT](LICENSE)
