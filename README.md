# CCShortcutLauncher 1.4.0

Control Center module cho iOS 16 Dopamine/rootless. Settings tải thủ công danh
mục My Shortcuts; mỗi module giữ danh sách Shortcut riêng. Tap module có nhiều
Shortcut thì hiện popup để chọn, module chỉ có một Shortcut thì chạy thẳng.
Mọi trường hợp đều chạy nền, không đưa app Shortcuts lên foreground.

## Cài đặt nhanh

Thêm repo sau vào Sileo rồi cài **CCShortcutLauncher**:

```text
https://dinhno12313.github.io/
```

[Add to Sileo](sileo://source/https://dinhno12313.github.io/)

Package release trực tiếp cũng có tại
[GitHub Releases](https://github.com/dinhno12313/CCShortcutLauncher/releases/tag/v1.4.0).

## Chức năng

- Nhiều module Control Center 1×1 thông qua CCSupport, mặc định 2, tối đa 8.
  Mỗi module có danh sách Shortcut và tên riêng.
- Module chỉ chứa đúng một Shortcut sẽ chạy ngay khi tap, không hiện popup, và
  lấy luôn glyph của Shortcut đó làm icon trong Control Center.
- Mỗi module có trang cấu hình riêng ngay trong **Settings → Control Center**,
  ngoài đường vào cũ ở **Settings → Shortcut Launcher**.
- Nút **Load My Shortcuts** lưu cache tên, workflow UUID, glyph và màu icon của
  toàn bộ Shortcut.
- Màn hình quản lý của từng module có phần đã thêm với nút trừ/tay nắm kéo và
  phần chưa thêm với nút cộng, sắp xếp theo tên.
- **Load My Shortcuts** chỉ cache danh mục, không tự thêm Shortcut nào vào
  module. Người dùng tự chọn.
- Trang quản lý và popup hiển thị icon đã đọc từ `ZSHORTCUTICON`; glyph được
  dựng qua `WFWorkflowIcon`/`WFWorkflowIconDrawer` của framework Shortcuts
  giống chính ứng dụng. CoreText và icon chung chỉ còn là fallback an toàn.
- Bundle có icon riêng trong danh sách thêm module tại **Settings → Control
  Center**.
- Tap module để mở action sheet chứa danh sách đã cache.
- Chọn một hàng để chạy Shortcut tương ứng.
- Gọi `WFSpringBoardWorkflowRunnerClient` để chạy trong nền.
- Đọc lại cache sau mỗi lần tap, không cần respring sau khi tải lại danh mục.
- Chặn tap lặp trong khi workflow trước vẫn đang chạy.
- Theo dõi workflow đến khi hoàn tất, kể cả Shortcut chạy lâu hơn 60 giây.
- Không gọi `shortcuts://` và không fallback sang app Shortcuts.

## Kiến trúc

`cslresolved` là LaunchDaemon chạy dưới user `mobile`. Nó có entitlement giới
hạn cho vùng lưu trữ Shortcuts và chỉ mở `Shortcuts.sqlite` ở chế độ read-only.
Daemon nằm yên sau khi khởi động. Chỉ khi người dùng bấm **Load My Shortcuts**,
nó đọc database đúng một lần rồi lưu mảng `ShortcutsCatalog` gồm tên, UUID,
`iconGlyph` và `iconColor`.

Module không mở database; nó chỉ tạo popup từ cache. Module được CCSupport nạp
qua provider bundle để provider trả trực tiếp settings icon cho danh sách
Control Center. Resolver không tự tải khi Settings mở, không theo dõi thay đổi
và không retry nền.

## Dependencies

Máy build:

- Theos và iPhoneOS 16.5 SDK; deployment target iOS 16.0.
- Header/stub CCSupport, ControlCenterUIKit và Preferences.
- `libsqlite3`, clang, make và `ldid`.

iPhone:

- iOS 16.x và Dopamine/rootless jailbreak.
- CCSupport (`com.opa334.ccsupport`).
- PreferenceLoader (`preferenceloader`).

## Build

```sh
cd CCShortcutLauncher
export THEOS=/path/to/theos
./scripts/check-build-env.sh
make clean package FINALPACKAGE=1
```

## Cài đặt

Chép package vào `/var/mobile/`, sau đó:

```sh
sudo dpkg -i '/var/mobile/com.dinhnguyenx.ccshortcutlauncher_1.4.0_iphoneos-arm64.deb'
sudo sbreload
```

Post-install script tự load resolver daemon. Sau đó:

1. Vào **Settings → Shortcut Launcher**.
2. Bấm **Load My Shortcuts** và ghi lại số lượng báo về.
3. Chỉnh **Number of Modules** nếu muốn khác 2, rồi `sbreload`.
4. Vào **Settings → Control Center** và thêm các module **Shortcut Launcher**.
5. Tap từng module trong danh sách đó để chọn Shortcut, đổi thứ tự, đổi tên.
6. Mở Control Center rồi tap module. Module nhiều Shortcut hiện popup đúng thứ
   tự đã sắp; module một Shortcut chạy ngay.

## Log chẩn đoán

```sh
idevicesyslog -m '[CCShortcutLauncher]' --no-colors
```

Đường chạy thành công:

```text
[CCShortcutLauncher][Resolver] CATALOG_REQUESTED
[CCShortcutLauncher][Resolver] CATALOG_LOADED count=... skipped=... icons=... completeIcons=... synchronized=1
[CCShortcutLauncher][Background] START_SENT name="Tên Shortcut" workflowID=...
[CCShortcutLauncher][Background] RUNNING name="Tên Shortcut"
[CCShortcutLauncher][Background] FINISHED_OBSERVED name="Tên Shortcut"
```

## Giới hạn

- Trên iOS 16.1, presenter của module được tìm qua runtime có kiểm tra;
  các exception đồng bộ được chặn trước khi thoát khỏi module.
- Catalog lọc `ZTOMBSTONED` và `ZHIDDENFROMLIBRARYANDSYNC` khi schema hỗ trợ.
- Cấu hình lưu UUID theo thứ tự cho từng module; Shortcut mới tải thêm không tự
  chen vào danh sách đã chọn.
- Đổi số lượng module cần respring: CCSupport chỉ hỏi provider một lần mỗi
  process. Bản cũ nâng cấp lên giữ nguyên module đã đặt trong Control Center vì
  module đầu tiên dùng lại identifier cũ.
- Bản 1.3.x không chọn gì thì mặc định popup hiện toàn bộ Shortcut. Từ 1.4.0
  mặc định là rỗng; lựa chọn cũ đã lưu sẽ được chuyển vào module đầu tiên.
- Popup chưa có thanh tìm kiếm; danh sách dài dùng khả năng cuộn của action sheet.
- Shortcut trùng tên được gắn thêm tám ký tự đầu của UUID để phân biệt.
- Shortcut yêu cầu UI, mở khóa hoặc cấp quyền mới vẫn có thể cần tương tác.
- WorkflowKit là private API của iOS; package giới hạn firmware ở iOS 16.x.
- Khi tạo, đổi tên hoặc xóa Shortcut, cần bấm lại **Load My Shortcuts**.
- Cache cũ không có metadata icon sẽ dùng icon dự phòng cho tới khi bấm
  lại **Load My Shortcuts**.

## Gỡ bỏ

```sh
sudo dpkg -r com.dinhnguyenx.ccshortcutlauncher
sudo sbreload
```

Preremove script unload resolver daemon trước khi gỡ file.

## License

CCShortcutLauncher được phát hành theo [MIT License](LICENSE).
