# Ký và cài MuseFleet trên iPhone

Đã xác minh IPA unsigned chẩn đoán 0.1.1 (build 8) từ run 46090966062, source `f2bbe8c`; link và SHA-256 nằm trong [DELIVERY.md](DELIVERY.md). Kiểm tra commit, tên bundle `com.dungprovaidai.musefleet`, trạng thái ký trong `build-metadata.json` và SHA-256 trước khi cài. Bằng chứng build/test được ghi trong [TEST_REPORT.md](TEST_REPORT.md).

## Kiểm tra file tải xuống trên Windows

Tải artifact IPA từ tab Actions của [repository](https://github.com/dungprovaidai/MuseFleet/actions), giải nén ZIP artifact vào một thư mục riêng, rồi chạy:

```powershell
Get-FileHash .\MuseFleet-unsigned.ipa -Algorithm SHA256
Get-Content .\MuseFleet-unsigned.ipa.sha256
Get-Content .\build-metadata.json
```

Hai giá trị SHA-256 phải giống nhau, không phân biệt chữ hoa/thường. File `.ipa` bản thân là ZIP chứa `Payload/MuseFleet.app`; việc giải nén được không chứng minh chữ ký cho phép iPhone chạy.

## Bản unsigned

`MuseFleet-unsigned.ipa` là ứng dụng iPhone arm64 **chưa được ký để cài đặt**. AirDrop, ứng dụng Files hoặc đổi tên file không làm nó cài được trên iPhone thông thường. Developer Mode cũng không bỏ yêu cầu chữ ký/provisioning.

Đường thử chính thức với tài khoản Apple miễn phí, nếu có Mac:

1. Clone source tại đúng commit của artifact và mở `MuseFleet.xcodeproj` trong Xcode phù hợp.
2. Đăng nhập Apple Account trong Xcode Settings → Accounts, trực tiếp trong giao diện Apple.
3. Chọn target MuseFleet → Signing & Capabilities → Automatically manage signing, rồi chọn Personal Team của bạn. Nếu App ID mặc định không khả dụng, dùng một bundle ID riêng bạn kiểm soát; bản cài đó sẽ có định danh khác artifact gốc.
4. Kết nối iPhone, xác nhận Trust trên thiết bị và bật Developer Mode nếu Xcode yêu cầu.
5. Chọn iPhone làm run destination rồi Product → Run. Xác nhận tin cậy developer profile trong Settings nếu hệ thống yêu cầu.
6. Personal Team có giới hạn ứng dụng/thiết bị và provisioning ngắn hạn (thường 7 ngày). Dùng lại Xcode để cấp lại khi hết hạn. Không coi phương thức này có khả năng APNs.

Đây là build-and-sign từ cùng source bằng công cụ Apple, không phải thao tác cài trực tiếp unsigned IPA. Một công cụ re-sign bên thứ ba vẫn phải tạo chữ ký/profile hợp lệ cho thiết bị của bạn và tuân theo điều kiện Apple. Chưa có công cụ re-sign Windows nào được kiểm thử trong phiên này; không cung cấp mật khẩu Apple, mã xác thực hoặc signing key cho agent này.

## Bản signed bằng GitHub Actions

Nếu đã có Apple team phù hợp và certificate/private key + provisioning profile hợp lệ:

1. Làm theo [BUILD_IPA.md](BUILD_IPA.md), thêm signing assets qua GitHub Secrets, không commit hoặc gửi vào chat.
2. Profile development/ad hoc phải có đúng bundle ID, team, certificate còn hạn và UDID iPhone đích. Bật Push Notifications chỉ khi team/profile thực sự cho phép.
3. Chạy Build IPA với `signed=true` sau khi signed validation đã qua các gate. Lấy `MuseFleet-signed.ipa`, checksum và metadata của run thành công.
4. Trên Mac có Apple Configurator, kết nối iPhone và dùng Add → Apps → Choose from my Mac để chọn IPA được phép cài trên thiết bị đó. Development builds có thể yêu cầu Developer Mode/trust; làm theo thông báo của iOS.
5. App Store export không phải IPA ad hoc để kéo vào mọi iPhone. TestFlight cần quy trình App Store Connect riêng; dự án không tự upload hay phát hành.

Chưa có signing credentials được cung cấp và chưa có signed IPA được xác minh. Pipeline phải fail thay vì gắn nhãn signed cho chữ ký hoặc profile không xác minh được. Không tự mua Apple Developer membership.

## Sau cài đặt

Mở bốn tab và [thiết lập profile](ACCOUNT_SETUP.md). Tự đăng nhập hai tài khoản Muse trong các cửa sổ riêng; làm checklist [TEST_REPORT.md](TEST_REPORT.md), đặc biệt app lock, restart, xóa tài khoản và giới hạn notification. Việc cài app thành công không chứng minh nguồn thông báo Muse thật hoặc nhận được khi khóa máy.

Ứng dụng không yêu cầu máy tính chạy liên tục để dùng browser. Các phương thức ký có hạn có thể yêu cầu kết nối lại định kỳ; yêu cầu đó khác máy chủ giám sát Muse 24/7.
