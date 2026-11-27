# Thiết lập và kiểm tra tài khoản

MuseFleet lưu **profile trên thiết bị**, không tạo tài khoản Meta. Mỗi profile có UUID riêng; tên, màu và avatar chỉ giúp nhận diện. Giao diện Muse gốc chịu trách nhiệm đăng nhập, lịch sử chat, giao việc, artifact và xác thực.

1. Mở Accounts, chọn Add account, đặt tên dễ phân biệt và lưu. Có thể nhập vai trò, project, ghi chú, tags và group; các trường này nằm trên iPhone.
2. Mở profile, kiểm tra website là `https://muse.ai/`, rồi tự hoàn thành đăng nhập chính thức. Không cung cấp mật khẩu/OTP cho người hỗ trợ hoặc ghi chúng vào tên/ghi chú.
3. Nếu có popup đăng nhập, kiểm tra nguồn chính thức. Khi website chuyển đến bên cấp danh tính chưa được xác minh hoặc từ chối embedded browser, dừng để ghi nhận blocker. MuseFleet không giả danh Safari và không nhập cookie từ một trình duyệt khác.
4. Thêm profile B. Trước khi đăng nhập B, kiểm tra nó không đang dùng phiên của A. Sau đó đăng nhập một tài khoản Muse khác và đối chiếu lịch sử trong giao diện web.
5. Chuyển A/B bằng quick switcher; đóng rồi mở lại app. Phiên chỉ tồn tại trong thời hạn mà Muse và WebKit cho phép. Avatar/tên profile không chứng minh danh tính tài khoản thật; xác nhận bằng giao diện Muse.
6. Dùng Back/Forward hoặc lịch sử chat của Muse để mở hội thoại cũ. MuseFleet lưu URL điều hướng đủ an toàn, không sao chép nội dung hội thoại hay suy ra đường dẫn chat.
7. Khi xóa một profile, đọc lựa chọn xóa website data. Giữ website data đồng nghĩa phiên có thể còn trong container của UUID cũ. Xóa website data không thay việc thu hồi phiên trên các thiết bị khác trong cài đặt Meta.

**Chưa kiểm chứng:** đăng nhập Muse thật trong WKWebView iOS 17, restore sau restart và hai tài khoản Muse độc lập trên iPhone. XCTest fixture kiểm tra cơ chế WebKit, không thay kiểm tra người dùng này. Điền checklist trong [TEST_REPORT.md](TEST_REPORT.md) trước khi dùng làm nơi quản lý phiên quan trọng.

Bật notification permission chỉ cho phép iOS trình bày sự kiện ứng dụng đã biết; nó không tự kết nối thông báo Muse. Đọc [NOTIFICATIONS.md](NOTIFICATIONS.md) trước khi dựa vào cảnh báo.
