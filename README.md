# Terminal Board (`tb`)

[Hướng dẫn phím tắt và quản lý pane](SHORTCUTS.md)

`tb` la cong cu danh rieng cho Windows, chia terminal hien tai thanh nhieu
pane doc lap trong Windows Terminal.
No chi quan ly bo cuc; moi pane van la terminal binh thuong de ban tu chay
`claude`, `codex`, server, log, hoac lenh bat ky.

## Cai dat

Mo PowerShell tai thu muc du an va chay:

```powershell
.\install.ps1
```

Hoac tren may Windows khac: giai nen goi phat hanh va nhap dup `setup.cmd`.

Mo mot terminal moi de PATH duoc cap nhat.

Bo cai cung tao shim `tb.cmd` trong thu muc WindowsApps cua nguoi dung, nen
lenh thuong co the dung ngay ca khi Windows Terminal dang giu PATH cu.

## Su dung

```powershell
tb 5
tb 3 rows
tb
tb 5 --dry-run
tb 5 --new-window
```

- `tb 5`: chia pane hien tai thanh 5 cot bang nhau.
- `tb 3 rows`: chia pane hien tai thanh 3 hang bang nhau.
- `tb`: dung lai so luong va bo cuc gan nhat; mac dinh la 5 cot.
- `--new-window`: tao mot cua so Windows Terminal moi.
- `--dry-run`: chi in lenh se chay.

Moi pane moi se sao chep profile terminal Windows dang hoat dong. Vi du, neu
ban dang o PowerShell thi cac pane moi cung la PowerShell; neu dang o CMD thi
cac pane moi cung la CMD.

Gioi han hien tai la 1-12 pane. De dong mot pane, dung phim tat dong pane cua
Windows Terminal (`Ctrl+Shift+W` theo cau hinh mac dinh). De go cai dat:

```powershell
.\uninstall.ps1
```

## Kiem thu

```powershell
pwsh -NoProfile -File .\tests\TerminalBoard.Tests.ps1
```
