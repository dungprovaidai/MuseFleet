# MuseFleet

Ứng dụng **native iOS 17+**, SwiftUI + WebKit, quản lý nhiều profile đăng nhập vào [Muse chính thức của Meta](https://muse.ai/). Metadata nằm trên iPhone; từng profile dùng persistent `WKWebsiteDataStore` với UUID riêng. Không có thư viện runtime bên ngoài, máy chủ theo dõi hay bản sao chatbot.

**Trạng thái phát triển, chưa đạt đầy đủ acceptance criteria.** Không có bằng chứng đăng nhập Muse trên WKWebView hoặc thông báo Muse thật khi app đóng. Không được hiểu bộ kiểm thử fixture, giao diện Inbox hoặc IPA chưa ký là bằng chứng các tính năng đó hoạt động. Xem [PROGRESS.md](PROGRESS.md), [RESEARCH.md](RESEARCH.md) và [TEST_REPORT.md](TEST_REPORT.md) để biết kết quả hiện tại.

Repository: <https://github.com/dungprovaidai/MuseFleet> (private).

## Tính năng triển khai trong source

- Profile riêng: tên, avatar, màu, vai trò, ghi chú, project, tags, group, yêu thích, thứ tự và URL mở gần nhất.
- Home, Accounts, Inbox, Settings; giao diện sáng/tối, quick switcher và công cụ browser native.
- Website data store riêng cho mỗi UUID; LRU giới hạn số WebView đang giữ trong RAM.
- Inbox lưu trên máy, chống trùng, trạng thái đọc, lọc; native local notification plumbing và định tuyến an toàn đến đúng profile.
- Khóa ứng dụng bằng xác thực thiết bị/Face ID/Touch ID; che nội dung khi app mất trạng thái active.
- Xcode project, shared scheme, XCTest/XCUITest, pipeline CI và hai chế độ đóng gói IPA.

Các mục này mô tả code được viết; kết quả build và runtime chỉ được công nhận khi có bằng chứng trong test report.

## Giới hạn thông báo P0

Chưa có bộ nhận diện DOM Muse sau đăng nhập được kiểm chứng. **Production observer mặc định báo detection unavailable** và không tạo sự kiện giả. Chưa có upstream webhook chính thức được kiểm chứng, APNs credentials hay relay được triển khai. Vì vậy MuseFleet hiện **chưa bảo đảm nhận phản hồi khi xem tài khoản khác, khóa màn hình, chạy nền hoặc bị force quit**.

iOS không cho chạy WKWebView liên tục trong nền. Local notification có thể hiển thị một sự kiện đã biết; nó không tự phát hiện phản hồi mới. Web Push của một Home Screen web app không tự chuyển thành notification của MuseFleet. Xem [NOTIFICATIONS.md](NOTIFICATIONS.md).

## Build và cài đặt

Xem [BUILD_IPA.md](BUILD_IPA.md) cho Xcode/macOS, GitHub Actions, unsigned/signed IPA, secrets và checksum. IPA chưa ký không cài trực tiếp được trên iPhone thông thường. Không có Apple signing credentials trong repository.

macOS Actions mặc định được chặn bằng repository variable để tránh chạy khi chưa xác nhận chi phí/hạn mức. GitHub Actions chỉ làm CI/build, không theo dõi Muse.

## Thiết lập tài khoản

Hướng dẫn riêng: [ACCOUNT_SETUP.md](ACCOUNT_SETUP.md).

1. Cài bản app đã ký hợp lệ; mở Accounts → Add account.
2. Đặt tên, vai trò, màu/avatar và lưu profile. UUID là định danh của website data store, không phải tên tài khoản Meta.
3. Mở profile và đăng nhập trực tiếp trên website Muse. Chỉ nhập mật khẩu/OTP vào giao diện chính thức; không gửi chúng vào issue, logs hoặc công cụ AI.
4. Tạo profile thứ hai và đăng nhập tài khoản khác. Thực hiện checklist isolation trong [TEST_REPORT.md](TEST_REPORT.md).
5. Nếu nhà cung cấp từ chối embedded browser, ghi nhận lỗi đã che thông tin nhạy cảm. Không đổi user agent để vượt bảo vệ, sao chép cookies hoặc cho rằng đăng nhập Safari đã đăng nhập WKWebView.
6. Xóa profile luôn cần xác nhận; chọn rõ có xóa website data hay giữ lại. Xóa app hoặc làm mất website data có thể mất các phiên đăng nhập.

## Bảo mật và hỗ trợ

[SECURITY.md](SECURITY.md) mô tả ranh giới bảo mật, dữ liệu được lưu, giới hạn xóa dữ liệu và kiểm tra trước release. Không đính kèm hội thoại riêng, cookie, OTP, provisioning profile hay chứng chỉ trong báo cáo lỗi.

App icon gốc nằm trong `design/AppIcon.svg`; bản PNG opaque 1024px nằm trong asset catalog. Ảnh screenshot chỉ được bàn giao sau khi chụp app chạy thực tế trên simulator/thiết bị.

## Roadmap theo blocker

1. Thực thi build/test trên macOS có hạn mức được xác nhận, sửa mọi lỗi compiler/test và xuất IPA thật.
2. Người dùng kiểm thử hai tài khoản Muse trên iPhone, khôi phục phiên và luồng đăng nhập chính thức.
3. Xác minh UI/IDs/trạng thái của phản hồi, approval và task hoàn tất; thêm adapter observer có fixture regression từ cấu trúc đã được phép quan sát.
4. Chỉ tích hợp một nguồn sự kiện chính thức đã chứng minh đủ coverage. Sau đó mới xin bật relay/APNs, ký đúng entitlement và kiểm thử khóa máy/force quit.
5. Đo RAM/thời gian chuyển profile và hoàn thiện accessibility trên thiết bị thật.
