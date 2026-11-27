# MuseFleet 0.1.0 (7) — unsigned IPA

Bản IPA arm64 thật đã được build trên macOS, tải về và xác minh. Bản này **chưa ký để cài trên iPhone**. Chưa kiểm thử đăng nhập Muse thật, thông báo Muse/background hoặc thiết bị vật lý.

## File và source

- [Tải artifact IPA trên GitHub](https://github.com/dungprovaidai/MuseFleet/actions/runs/46065778744/artifacts/15230534206): giải nén ZIP để lấy `MuseFleet-unsigned.ipa`, `.sha256` và `build-metadata.json`. GitHub có thể yêu cầu đăng nhập.
- [Source đúng commit của IPA](https://github.com/dungprovaidai/MuseFleet/tree/222c8c0c94ca2668ac09382452bcf78734738cee) · [Tải ZIP source](https://github.com/dungprovaidai/MuseFleet/archive/222c8c0c94ca2668ac09382452bcf78734738cee.zip).
- [Run build/test thành công](https://github.com/dungprovaidai/MuseFleet/actions/runs/46065778744) · [Artifact kết quả và ảnh simulator](https://github.com/dungprovaidai/MuseFleet/actions/runs/46065778744/artifacts/15230584240).

GitHub chỉ giữ artifact một ngày, hết hạn khoảng **20:56 UTC ngày 28/11/2026**. Đã lưu bản tải về trong workspace Windows:

```text
D:\DUNGG\ios\musefleet\artifacts\delivery-46065778744\
  MuseFleet-unsigned.ipa
  MuseFleet-unsigned.ipa.sha256
  build-metadata.json
  independent-validation.json
  test-evidence.json
  MuseFleet-simulator-Settings.png
```

Các bundle `.xcresult` và attachment gốc được giữ tại `artifacts/results-46065778744/`. Artifact build không được commit vào source.

## Danh tính bản build

| Mục | Giá trị |
|---|---|
| Version / build | 0.1.0 / 7 |
| Source commit | `222c8c0c94ca2668ac09382452bcf78734738cee` |
| Bundle ID | `com.dungprovaidai.musefleet` |
| Nền tảng / CPU | iOS / arm64 |
| Minimum iOS | 17.0; chưa chạy test trên iOS 17 |
| Xcode / SDK | Xcode 26.3 (17C529) / iPhoneOS 26.2 |
| Kích thước IPA | 1,000,442 bytes |
| Executable | Mach-O arm64 thật, 4,135,976 bytes |
| Chữ ký / provisioning | Không có; unsigned |

SHA-256 của **file IPA**, không phải ZIP artifact bên ngoài:

```text
c384d3dcde36061bb4a5a3872d3ee976e6f6425f5c5ade168b66743e7844879d
```

Đã đối chiếu checksum bằng validator và `Get-FileHash` độc lập trên Windows; metadata khớp runner. macOS xác nhận executable không có chữ ký. ZIP CRC, cấu trúc bundle, arm64 Mach-O và metadata iOS đều qua kiểm tra.

## Kiểm thử và cài đặt

Unit tests trên simulator: **31 qua, 1 skip, không lỗi**. Test bị skip cần quyền thông báo hệ thống. UI smoke test: **1 qua**, gồm tạo profile, lưu qua lần mở lại và điều hướng Accounts/Inbox/Settings. Ảnh Settings thực tế đã được kiểm tra. Database `.xcresult` xác nhận tổng 32 test thành công và 1 skip, gồm UI test.

Simulator dùng chữ ký ad hoc cục bộ để truy cập Keychain. Đây không phải chữ ký phân phối của IPA cho thiết bị. Muốn cài trên iPhone thông thường phải ký/provision phù hợp; xem [INSTALLATION.md](INSTALLATION.md). Chưa có signed IPA, bản cài iPhone hay TestFlight.

Production Muse observer vẫn báo unavailable đến khi có bằng chứng UI sau đăng nhập. Fixture tests không chứng minh phản hồi Muse thật hoặc thông báo khi khóa máy/chạy nền. Chi tiết kết quả và phần còn thiếu nằm trong [TEST_REPORT.md](TEST_REPORT.md).
