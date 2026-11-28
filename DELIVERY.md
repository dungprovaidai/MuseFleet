# MuseFleet 0.1.1 (8) — diagnostic unsigned IPA

Bản IPA arm64 thật đã được build trên macOS, tải về và xác minh. Bản chẩn đoán hiện mã lỗi WebKit/network an toàn, không hiện URL/credentials và không bỏ qua TLS. Bản này **chưa ký để cài trên iPhone**. Chưa kiểm thử đăng nhập Muse thật, thông báo Muse/background hoặc thiết bị vật lý.

## File và source

- [Tải artifact IPA trên GitHub](https://github.com/dungprovaidai/MuseFleet/actions/runs/46090966062/artifacts/15241228164): giải nén ZIP để lấy `MuseFleet-unsigned.ipa`, `.sha256` và `build-metadata.json`. GitHub có thể yêu cầu đăng nhập.
- [Source đúng commit của IPA](https://github.com/dungprovaidai/MuseFleet/tree/f2bbe8c2ae886e988c9e92d049fa2618750ea3ad) · [Tải ZIP source](https://github.com/dungprovaidai/MuseFleet/archive/f2bbe8c2ae886e988c9e92d049fa2618750ea3ad.zip).
- [Run build/test thành công](https://github.com/dungprovaidai/MuseFleet/actions/runs/46090966062) · [Artifact kết quả và ảnh simulator](https://github.com/dungprovaidai/MuseFleet/actions/runs/46090966062/artifacts/15241940923).

GitHub chỉ giữ artifact một ngày, hết hạn khoảng **01:09 UTC ngày 29/11/2026**. Đã lưu bản tải về trong workspace Windows:

```text
D:\DUNGG\ios\musefleet\artifacts\delivery-46090966062\
  MuseFleet-unsigned.ipa
  MuseFleet-unsigned.ipa.sha256
  build-metadata.json
  independent-validation.json
  test-evidence.json
  MuseFleet-simulator-Settings.png
```

Các bundle `.xcresult` và attachment gốc được giữ tại `artifacts/results-46090966062/`. Bản gốc 0.1.0 vẫn nằm trong `artifacts/delivery-46065778744/`. Artifact build không được commit vào source.

## Danh tính bản build

| Mục | Giá trị |
|---|---|
| Version / build | 0.1.1 / 8 |
| Source commit | `f2bbe8c2ae886e988c9e92d049fa2618750ea3ad` |
| Bundle ID | `com.dungprovaidai.musefleet` |
| Nền tảng / CPU | iOS / arm64 |
| Minimum iOS | 17.0; chưa chạy test trên iOS 17 |
| Xcode / SDK | Xcode 26.3 (17C529) / iPhoneOS 26.2 |
| Kích thước IPA | 1,000,869 bytes |
| Executable | Mach-O arm64 thật, 4,136,144 bytes |
| Chữ ký / provisioning | Không có; unsigned |

SHA-256 của **file IPA**, không phải ZIP artifact bên ngoài:

```text
3f7d72b27a553d339a0827f93a03aca06d840d091c8cd69b6d8ed7d406ebb98b
```

Đã đối chiếu checksum bằng validator và `Get-FileHash` độc lập trên Windows; metadata khớp runner. macOS xác nhận executable không có chữ ký. ZIP CRC, cấu trúc bundle, arm64 Mach-O và metadata iOS đều qua kiểm tra.

## Kiểm thử và cài đặt

Unit tests trên simulator: **32 qua, 1 skip, không lỗi**. Test bị skip cần quyền thông báo hệ thống. UI smoke test: **1 qua**, gồm tạo profile, lưu qua lần mở lại và điều hướng Accounts/Inbox/Settings. Database `.xcresult` xác nhận tổng 33 test thành công và 1 skip, gồm UI test.

Khi thử trên máy, đọc dòng lỗi trong banner, ví dụ `network error -1200` (TLS/chứng chỉ), `network error -1003` (DNS), hoặc `WebKit error 4`. Chỉ gửi mã và nội dung phân loại; không cần URL hội thoại hay thông tin tài khoản. Bản 0.1.1 bổ sung chẩn đoán, **chưa xác nhận lỗi tải trang đã được sửa**.

Simulator dùng chữ ký ad hoc cục bộ để truy cập Keychain. Đây không phải chữ ký phân phối của IPA cho thiết bị. Muốn cài trên iPhone thông thường phải ký/provision phù hợp; xem [INSTALLATION.md](INSTALLATION.md). Chưa có signed IPA, bản cài iPhone hay TestFlight.

Production Muse observer vẫn báo unavailable đến khi có bằng chứng UI sau đăng nhập. Fixture tests không chứng minh phản hồi Muse thật hoặc thông báo khi khóa máy/chạy nền. Chi tiết kết quả và phần còn thiếu nằm trong [TEST_REPORT.md](TEST_REPORT.md).
