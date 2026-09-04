# Terminal Board (`tb`)

[Hướng dẫn phím tắt và quản lý pane](SHORTCUTS.md)

`tb` la cong cu danh rieng cho Windows, chia terminal hien tai thanh nhieu
pane doc lap trong Windows Terminal.
No chi quan ly bo cuc; moi pane van la terminal binh thuong de ban tu chay
`claude`, `codex`, server, log, hoac lenh bat ky.

## Huong dan nhanh

1. **Cai lan dau**: mo thu muc `Terminal Board Setup` tren Desktop, nhap dup
   `setup.cmd`. Cai xong moi lan la dung duoc, khong can lam lai.
2. **Mo board**: bam Start Menu, go "Terminal Board", Enter. Hoac go
   `tb 5` trong bat ky terminal nao.
3. **Gui anh cho agent**: chup man hinh (`Win+Shift+S`), bam `Ctrl+Alt+C`
   (nghe 1 tieng beep la xong), roi `Ctrl+V` vao o chat cua agent.
4. **Mo nhieu agent cung luc**: bam Start Menu, go "Terminal Board - Agents",
   Enter. Se mo `claude` va `codex` canh nhau trong 1 cua so.
5. **Go cai dat**: chay `.\uninstall.ps1` tai thu muc du an.

Chi tiet tung phan, cach doi profile, cach dong goi lai khi co ban moi... xem
cac muc ben duoi.

## Cai dat

Mo PowerShell tai thu muc du an va chay:

```powershell
.\install.ps1
```

Hoac tren may Windows khac: giai nen goi phat hanh va nhap dup `setup.cmd`.

Mo mot terminal moi de PATH duoc cap nhat.

Bo cai dat chuong trinh va shim `tb.cmd` trong thu muc WindowsApps cua nguoi
dung. Vi vay lenh co the dung ngay, van hoat dong sau khi khoi dong lai Windows
va khong can sua PATH thu cong.

### Dong goi ban phat hanh

De tao mot goi cai dat doc lap (khong can git, chi giai nen/copy va nhap dup
`setup.cmd`), chay tai thu muc du an:

```powershell
.\Build-Release.ps1
```

Ket qua nam trong `dist\TerminalBoard` (thu muc, dung de copy thang ra
Desktop hoac USB) va `dist\TerminalBoard.zip` (dung de chia se). Chay lai
lenh nay moi khi code thay doi de goi cai dat luon la ban moi nhat.

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

## Dan anh cho agent

Terminal khong nhan dan anh truc tiep. `tb img` doc anh dang co trong
clipboard (vi du sau khi chup man hinh bang `Win+Shift+S`), luu thanh file
PNG, roi tu dong copy duong dan file do vao clipboard:

```powershell
tb img
```

Sau do chi can dan (`Ctrl+V`) duong dan vao o chat cua Claude Code, Codex,
ChatGPT... de agent tu doc file anh.

**Nhanh hon:** sau khi cai dat, phim tat `Ctrl+Alt+C` chay `tb img` ngam,
dung o bat ky dau tren Windows, khong can mo terminal truoc. Thanh cong se
co mot tieng beep ngan, khong co anh trong clipboard se co hai tieng beep
tram. Neu `Ctrl+Alt+C` bi trung voi ung dung khac, doi trong Start Menu >
Terminal Board > chuot phai vao "Terminal Board - Capture Image" > Properties
> Shortcut key.

## Profile mo nhieu agent cung luc

Moi profile la mot danh sach lenh, moi lenh chay trong mot pane rieng khi mo
board:

```powershell
tb profile set agents "claude,codex" columns
tb agents
```

- `tb profile list`: liet ke cac profile da luu.
- `tb profile remove agents`: xoa mot profile.
- `tb agents --dry-run`: xem truoc lenh Windows Terminal se chay.

Sau khi cai dat, Start Menu co san 2 shortcut **Terminal Board** (mo `tb`) va
**Terminal Board - Agents** (mo `tb agents`) kem icon rieng, tien bam de mo
ma khong can go lenh.

## Kiem thu

```powershell
pwsh -NoProfile -File .\tests\TerminalBoard.Tests.ps1
```
