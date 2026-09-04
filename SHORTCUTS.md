# Phím tắt Terminal Board và Windows Terminal

Tài liệu này tổng hợp các lệnh thường dùng sau khi tạo board bằng `tb`.
Các phím tắt Windows Terminal có thể khác nếu bạn đã thay đổi trong
`Settings > Actions`.

## Lệnh Terminal Board

| Lệnh | Chức năng |
| --- | --- |
| `tb 5` | Chia pane đang chọn thành 5 cột bằng nhau |
| `tb 3 rows` | Chia pane đang chọn thành 3 hàng bằng nhau |
| `tb` | Dùng lại số lượng và bố cục gần nhất |
| `tb 5 --new-window` | Mở một cửa sổ mới sạch với 5 pane |
| `tb img` | Lưu ảnh trong clipboard ra file, copy đường dẫn vào clipboard |
| `Ctrl + Alt + C` | Phím tắt toàn hệ thống, làm việc như `tb img` nhưng không cần mở terminal |
| `tb profile set <tên> <lệnh1,lệnh2,...>` | Lưu một profile nhiều agent |
| `tb agents` | Mở tất cả pane của profile `agents`, mỗi pane chạy 1 agent |
| `tb profile list` / `tb profile remove <tên>` | Xem / xóa profile |
| `tb help` | Hiển thị trợ giúp |

Nếu tab hiện tại đã có nhiều pane, nên dùng `--new-window` để tạo một board
mới có đúng số pane mong muốn.

## Điều hướng và thay đổi kích thước pane

| Phím tắt | Chức năng |
| --- | --- |
| `Alt + ←` | Chuyển sang pane bên trái |
| `Alt + →` | Chuyển sang pane bên phải |
| `Alt + ↑` | Chuyển sang pane phía trên |
| `Alt + ↓` | Chuyển sang pane phía dưới |
| `Alt + Shift + ←` | Thay đổi kích thước về bên trái |
| `Alt + Shift + →` | Thay đổi kích thước về bên phải |
| `Alt + Shift + ↑` | Thay đổi kích thước lên trên |
| `Alt + Shift + ↓` | Thay đổi kích thước xuống dưới |

## Tạo và đóng pane

| Phím tắt | Chức năng |
| --- | --- |
| `Alt + Shift + +` | Tạo pane dọc bên phải |
| `Alt + Shift + -` | Tạo pane ngang bên dưới |
| `Alt + Shift + D` | Nhân đôi profile của pane hiện tại |
| `Ctrl + Shift + W` | Đóng pane đang chọn |
| `exit` | Thoát shell; pane thường sẽ tự đóng |

Khi tab chỉ còn một pane, `Ctrl + Shift + W` sẽ đóng cả tab.

## Quản lý tab

| Phím tắt | Chức năng |
| --- | --- |
| `Ctrl + Shift + T` | Mở tab mới |
| `Ctrl + Tab` | Chuyển sang tab tiếp theo |
| `Ctrl + Shift + Tab` | Chuyển về tab trước |
| `Ctrl + Shift + P` | Mở Command Palette |

## Tách pane thành tab hoặc cửa sổ riêng

Chuyển pane đang chọn thành một tab mới trong cùng cửa sổ:

```powershell
wt -w 0 move-pane -t 99
```

Tách thẳng pane thành cửa sổ riêng:

1. Bấm chọn pane.
2. Nhấn `Ctrl + Shift + P`.
3. Tìm `Move pane to new window`.
4. Nhấn `Enter`.

Bạn có thể tự đặt `Ctrl + Alt + N` cho thao tác này trong
`Settings > Actions`, hoặc thêm action sau vào `settings.json`:

```json
{
  "command": {
    "action": "movePane",
    "window": "new"
  },
  "keys": "ctrl+alt+n"
}
```

## Sao chép, dán và hiển thị

| Phím tắt | Chức năng |
| --- | --- |
| `Ctrl + Shift + C` | Sao chép nội dung đã chọn |
| `Ctrl + Shift + V` | Dán |
| `Ctrl + Shift + F` | Tìm kiếm trong terminal |
| `Ctrl + +` | Tăng cỡ chữ |
| `Ctrl + -` | Giảm cỡ chữ |
| `Ctrl + 0` | Trả về cỡ chữ mặc định |

## Tham khảo

- [Windows Terminal panes](https://learn.microsoft.com/windows/terminal/panes)
- [Windows Terminal command-line arguments](https://learn.microsoft.com/windows/terminal/command-line-arguments)
