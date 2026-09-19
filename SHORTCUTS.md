# Terminal Board and Windows Terminal shortcuts

This page collects the commands you will use most after creating a board with
`tb`. The Windows Terminal shortcuts may differ if you changed them in
`Settings > Actions`.

## Terminal Board commands

| Command | What it does |
| --- | --- |
| `tb ui` | Open the settings screen: working folder, number of panes, and what each pane runs (Terminal, Claude Code, Codex, Antigravity) |
| `tb desk` | Open the workspace you saved last time right away, without asking again |
| `tb 5` | Split the selected pane into 5 equal columns |
| `tb 3 rows` | Split the selected pane into 3 equal rows |
| `tb` | Reuse the most recent count and layout |
| `tb 5 --new-window` | Open a clean new window with 5 panes |
| `Win + Shift + S`, then `Ctrl + V` | Take a screenshot and paste it into the terminal: the background helper saves the picture and pastes its file path |
| `Alt + V` | Claude Code on Windows only: paste the clipboard picture directly |
| `tb clip` / `tb clip on` / `tb clip off` | Check / turn on / turn off the background screenshot helper |
| `tb img` | Save the clipboard picture to a file manually and copy its path to the clipboard |
| `tb profile set <name> <cmd1,cmd2,...>` | Save a multi-agent profile |
| `tb agents` | Open every pane of the `agents` profile, one agent per pane |
| `tb profile list` / `tb profile remove <name>` | List / delete profiles |
| `tb help` | Show help |

If the current tab already has several panes, use `--new-window` to get a fresh
board with exactly the number of panes you want.

## Navigating and resizing panes

| Shortcut | What it does |
| --- | --- |
| `Alt + ←` | Move focus to the pane on the left |
| `Alt + →` | Move focus to the pane on the right |
| `Alt + ↑` | Move focus to the pane above |
| `Alt + ↓` | Move focus to the pane below |
| `Alt + Shift + ←` | Resize to the left |
| `Alt + Shift + →` | Resize to the right |
| `Alt + Shift + ↑` | Resize upward |
| `Alt + Shift + ↓` | Resize downward |

## Creating and closing panes

| Shortcut | What it does |
| --- | --- |
| `Alt + Shift + +` | Split a new pane to the right |
| `Alt + Shift + -` | Split a new pane below |
| `Alt + Shift + D` | Duplicate the current pane's profile |
| `Ctrl + Shift + W` | Close the selected pane |
| `exit` | Quit the shell; a normal pane closes by itself |

When a tab has only one pane left, `Ctrl + Shift + W` closes the whole tab.

## Managing tabs

| Shortcut | What it does |
| --- | --- |
| `Ctrl + Shift + T` | Open a new tab |
| `Ctrl + Tab` | Switch to the next tab |
| `Ctrl + Shift + Tab` | Switch to the previous tab |
| `Ctrl + Shift + P` | Open the Command Palette |

## Moving a pane to its own tab or window

Turn the selected pane into a new tab in the same window:

```powershell
wt -w 0 move-pane -t 99
```

Move a pane straight into its own window:

1. Click the pane to select it.
2. Press `Ctrl + Shift + P`.
3. Search for `Move pane to new window`.
4. Press `Enter`.

You can bind `Ctrl + Alt + N` to this action in `Settings > Actions`, or add the
following action to `settings.json`:

```json
{
  "command": {
    "action": "movePane",
    "window": "new"
  },
  "keys": "ctrl+alt+n"
}
```

## Copy, paste and display

| Shortcut | What it does |
| --- | --- |
| `Ctrl + Shift + C` | Copy the selection |
| `Ctrl + Shift + V` | Paste |
| `Ctrl + Shift + F` | Search in the terminal |
| `Ctrl + +` | Increase the font size |
| `Ctrl + -` | Decrease the font size |
| `Ctrl + 0` | Reset the font size |

## References

- [Windows Terminal panes](https://learn.microsoft.com/windows/terminal/panes)
- [Windows Terminal command-line arguments](https://learn.microsoft.com/windows/terminal/command-line-arguments)
