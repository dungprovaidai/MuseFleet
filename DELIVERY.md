# MuseFleet 0.1.3 (10) — verified-login-path diagnostic IPA

Bản IPA arm64 thật đã được build trên macOS, tải về và xác minh. Bản 0.1.3 cho phép các HTTPS origin/path đăng nhập Meta được xác nhận từ mã frontend công khai Muse; host đăng nhập bị chặn khác sẽ hiện chỉ hostname, không có path/query. Đây là tương thích điều hướng có giới hạn, **không phải xác nhận đăng nhập Muse chạy trên thiết bị**. Bản này **chưa ký để cài trên iPhone**; chưa kiểm thử tài khoản Muse thật hoặc thiết bị vật lý.

## File và source

- [Tải artifact IPA trên GitHub](https://github.com/dungprovaidai/MuseFleet/actions/runs/46095940301/artifacts/15243895075): giải nén ZIP để lấy `MuseFleet-unsigned.ipa`, `.sha256` và `build-metadata.json`. GitHub có thể yêu cầu đăng nhập.
- [Source đúng commit của IPA](https://github.com/dungprovaidai/MuseFleet/tree/6f84487c6f37dcbcfa758b9d776b8c8a596c65e4) · [Tải ZIP source](https://github.com/dungprovaidai/MuseFleet/archive/6f84487c6f37dcbcfa758b9d776b8c8a596c65e4.zip).
- [Run build/test thành công](https://github.com/dungprovaidai/MuseFleet/actions/runs/46095940301) · [Artifact kết quả và ảnh simulator](https://github.com/dungprovaidai/MuseFleet/actions/runs/46095940301/artifacts/15243905022).
- [Nghiên cứu redirect đăng nhập Muse](reports/Muse%20WKWebView%20sign%20in.md) · [Ghi chú nguồn](research_notes/Muse%20WKWebView%20sign%20in/findings.md).

GitHub chỉ giữ artifact một ngày, hết hạn khoảng **02:07 UTC ngày 29/11/2026**. Đã lưu bản tải về trong workspace Windows:

```text
D:\DUNGG\ios\musefleet\artifacts\delivery-46095940301\
  MuseFleet-unsigned.ipa
  MuseFleet-unsigned.ipa.sha256
  build-metadata.json
  independent-validation.json
  test-evidence.json
  MuseFleet-simulator-Settings.png
```

Các bundle `.xcresult` và attachment gốc được giữ tại `artifacts/results-46095940301/`. Bản 0.1.2 nằm trong thư mục delivery theo run cũ. Artifact build không được commit vào source.

## Danh tính bản build

| Mục | Giá trị |
|---|---|
| Version / build | 0.1.3 / 10 |
| Source commit | `6f84487c6f37dcbcfa758b9d776b8c8a596c65e4` |
| Bundle ID | `com.dungprovaidai.musefleet` |
| Nền tảng / CPU | iOS / arm64 |
| Minimum iOS | 17.0; chưa chạy test trên iOS 17 |
| Xcode / SDK | Xcode 26.3 (17C529) / iPhoneOS 26.2 |
| Kích thước IPA | 1,002,475 bytes |
| Executable | Mach-O arm64 thật, 4,137,144 bytes |
| Chữ ký / provisioning | Không có; unsigned |

SHA-256 của **file IPA**, không phải ZIP artifact bên ngoài:

```text
433d08fff50414a3136c390eb165c45880ed9abf5aed096b2ca6fa8d5be7c1fb
```

Đã đối chiếu checksum bằng validator và `Get-FileHash` độc lập trên Windows; metadata khớp runner. macOS xác nhận executable không có chữ ký. ZIP CRC, cấu trúc bundle, arm64 Mach-O và metadata iOS đều qua kiểm tra.

## Kiểm thử và cài đặt

Unit tests trên simulator: **32 qua, 1 skip, không lỗi**. Test bị skip cần quyền thông báo hệ thống. UI smoke test: **1 qua**, gồm tạo profile, lưu qua lần mở lại và điều hướng Accounts/Inbox/Settings. Database `.xcresult` xác nhận 33 test thành công (32 unit + 1 UI) và 1 skip. XCTest policy xác nhận host/path đăng nhập được phép, còn host giả mạo, scheme không an toàn, cổng khác thường và đường dẫn ngoài luồng đều bị từ chối.

Khi thử trên máy, tự hoàn tất đăng nhập Muse bằng luồng chính thức. Nếu trang vẫn không mở và banner báo redirect bị chặn, chỉ gửi hostname hiển thị; không gửi URL đăng nhập, mã xác minh hay thông tin tài khoản. **Chưa xác nhận đăng nhập Muse đã chạy thành công**: điều đó cần kiểm tra trên iPhone của bạn.

Simulator dùng chữ ký ad hoc cục bộ để truy cập Keychain. Đây không phải chữ ký phân phối của IPA cho thiết bị. Muốn cài trên iPhone thông thường phải ký/provision phù hợp; xem [INSTALLATION.md](INSTALLATION.md). Chưa có signed IPA, bản cài iPhone hay TestFlight.

Production Muse observer vẫn báo unavailable đến khi có bằng chứng UI sau đăng nhập. Fixture tests không chứng minh phản hồi Muse thật hoặc thông báo khi khóa máy/chạy nền. Chi tiết kết quả và phần còn thiếu nằm trong [TEST_REPORT.md](TEST_REPORT.md).
