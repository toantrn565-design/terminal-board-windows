# Terminal Board (`tb`)

[Shortcuts and pane management guide](SHORTCUTS.md)

`tb` is a Windows tool that splits Windows Terminal into several independent
panes. It only manages the layout: every pane is an ordinary terminal where you
run `claude`, `codex`, a dev server, a log tail, or any other command.

## Quick start

1. **Install once**: open the `Terminal Board Setup` folder and double-click
   `setup.cmd`. After that it just works; there is nothing to repeat.
2. **Open a workspace**: click the **Terminal Board** icon on the Desktop (or
   double-click the icon by the clock, or use the Start Menu). The settings
   screen appears: pick the working folder, the number of panes (1-12), the
   layout, and what each pane runs (Terminal, Claude Code, Codex, Antigravity,
   or any command), then click **Open workspace**. Your choices are remembered.
   To open the saved workspace instantly, without the screen, use Start Menu >
   "Terminal Board - Quick Open" or type `tb desk`. You can also type `tb 5` in
   any terminal to split it into 5 panes right away.
3. **Send a screenshot to an agent**: take a screenshot (`Win+Shift+S`), then
   press `Ctrl+V` in the terminal. The picture's file path is pasted and the
   agent reads the image itself. No other key is needed (see "Pasting
   screenshots" below).
4. **Open several agents at once**: the settings screen does this (pick an agent
   per pane). For a one-click Start Menu launcher, create a profile named
   `agents` once (see "Multi-agent profiles" below), then use Start Menu >
   "Terminal Board - Agents".
5. **Uninstall**: run `.\uninstall.ps1` in the project folder.

The sections below cover each part in detail, how to change profiles, and how to
repackage the kit after a change.

## Installation

Open PowerShell in the project folder and run:

```powershell
.\install.ps1
```

Or, on another Windows PC, unzip the release package and double-click
`setup.cmd`.

Open a new terminal afterwards so PATH is refreshed.

The installer puts the program and a `tb.cmd` shim in the user's WindowsApps
folder, so the command works immediately, survives a restart, and needs no
manual PATH edits.

### Building the release package

To create a standalone kit (no git needed, just unzip or copy it and
double-click `setup.cmd`), run this in the project folder:

```powershell
.\Build-Release.ps1
```

The result is `dist\TerminalBoard` (a folder you can copy straight to the
Desktop or a USB stick) and `dist\TerminalBoard.zip` (for sharing). Run it again
whenever the code changes so the kit is always current.

## The settings screen (choose panes and agents)

Open it with the **Terminal Board** icon on the Desktop, with `tb ui`, or by
double-clicking the Terminal Board icon in the system tray (by the clock). On
this screen:

- **Working folder**: every pane starts in this folder.
- **Number of panes**: from 1 to 12. **Layout**: side by side (columns) or
  stacked (rows). Panes are always split into equal sizes.
- **What runs in each pane?**: for each pane choose *Terminal (PowerShell)*,
  *Claude Code*, *Codex*, *Antigravity*, or *Custom* to type any command. Use
  "Quick presets" to set a whole arrangement at once, then adjust single panes.
- **Open workspace**: opens a new maximized window (the taskbar stays visible)
  and remembers your choices. **Save settings** only saves, without opening.

The screen has 4 luxurious colour themes; switch between them with the 4 dots in
the top-right corner (the choice is remembered): **Imperial Gold** (royal gold,
the default), **Midnight Gold** (navy blue with champagne gold), **Emerald Gold**
(emerald green with gold) and **Royal Burgundy** (wine red with rose gold). Each
theme has a soft translucent light-ray pattern behind the panels, so the
background is never one flat colour.

To use **your own picture** as the background, click the picture button next to
the colour dots and choose a PNG or JPG file. The picture shows softly behind the
panels and is remembered (the app keeps its own copy in its data folder, so it is
fine to delete the original). **Right-click** the picture button to remove the
picture and go back to the default pattern.

Settings are stored in `%LOCALAPPDATA%\TerminalBoard\desk.json`. `tb desk` (or
Start Menu > "Terminal Board - Quick Open") opens the saved workspace right away
without showing the settings screen.

The screen is prepared in the background shortly after Windows starts (roughly
80 MB of RAM), so clicking the icon shows it almost instantly (under 0.2
seconds). If it is not used for 6 hours it shuts itself down and the next open
takes about 3 seconds. `tb clip off` turns off the screenshot helper together
with this prepared screen.

## Usage

```powershell
tb 5
tb 3 rows
tb
tb 5 --dry-run
tb 5 --new-window
```

- `tb 5`: split the current pane into 5 equal columns.
- `tb 3 rows`: split the current pane into 3 equal rows.
- `tb`: reuse the most recent count and layout; the default is 5 columns.
- `--new-window`: create a new Windows Terminal window, maximized but with the
  taskbar still visible (not fullscreen). If a window ever goes fullscreen and
  hides the taskbar, press `F11` to leave fullscreen.
- `--dry-run`: only print the command that would run.

Each new pane copies the active Windows Terminal profile. For example, if you are
in PowerShell the new panes are PowerShell too; in CMD they are CMD.

The limit is 1-12 panes. To close a pane use Windows Terminal's close-pane
shortcut (`Ctrl+Shift+W` by default). To uninstall:

```powershell
.\uninstall.ps1
```

## Pasting screenshots

A terminal can only paste text, not pictures: pressing `Ctrl+V` when the
clipboard holds just a picture pastes nothing. So Terminal Board installs a
**screenshot helper** that runs in the background (an icon in the system tray,
by the clock) and starts with Windows:

1. Take a screenshot as usual: `Win+Shift+S`, `PrintScreen`, or copy a picture
   from Paint.
2. The helper saves the picture as a PNG file and adds the file path to the
   clipboard, **keeping the picture too**.
3. Press `Ctrl+V` in the terminal (Claude Code, Codex...): the path appears and
   the agent reads the image file. Press `Ctrl+V` in Word, Paint, a chat app...:
   the picture is pasted as usual.

Pictures are saved in `%LOCALAPPDATA%\TerminalBoard\images` and deleted after 30
days. Only plain pictures (screenshots, pictures from Paint) are handled. A
picture that comes with text, files, or a rich format (Office, browsers...) is
left alone. Right-click the tray icon to Pause, Open the screenshots folder, or
Exit.

**Claude Code on Windows** also has a built-in way that needs no helper: take a
screenshot, then press `Alt+V`.

```powershell
tb clip            # is the screenshot helper running?
tb clip off        # turn it off completely (no autostart with Windows)
tb clip on         # turn it back on
tb img             # save the clipboard picture to a file manually
```

If Windows blocks the helper (antivirus...), Terminal Board still works with
`Alt+V` in Claude Code and the `tb img` command.

## Multi-agent profiles

A profile is a list of commands; each command runs in its own pane when the
board opens:

```powershell
tb profile set agents "claude,codex" columns
tb agents
```

- `tb profile list`: list the saved profiles.
- `tb profile remove agents`: delete a profile.
- `tb agents --dry-run`: preview the Windows Terminal command that would run.

After installation the Start Menu has 3 shortcuts with their own icon:
**Terminal Board** (the settings screen), **Terminal Board - Quick Open** (opens
the saved workspace) and **Terminal Board - Agents** (runs `tb agents`).

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\TerminalBoard.Tests.ps1
```
