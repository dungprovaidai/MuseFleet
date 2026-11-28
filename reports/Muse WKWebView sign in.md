# Đăng nhập Muse trong WKWebView

## Kết luận

Ảnh mới của người dùng xác nhận MuseFleet đã hủy một redirect main-frame theo allowlist; thông báo WebKit 102 chỉ là kết quả nhìn thấy sau khi bị hủy, không phải bằng chứng mất mạng. Mã JavaScript công khai mà trang Muse đang tải cấu hình OIDC tại `auth.meta.com` và kiểm tra một số đường chuyển tiếp Facebook/Instagram. Bản MuseFleet 0.1.3 vì vậy cho phép HTTPS trên đúng `auth.meta.com`, cùng Facebook/Instagram chỉ ở `/auth_platform`; các host giả, giao thức không an toàn, cổng khác thường và trang mạng xã hội ngoài đường dẫn đó vẫn bị chặn.

Đây là sửa chính sách dựa trên **frontend công khai hiện tại**, không phải hợp đồng hỗ trợ chính thức hay bằng chứng đã đăng nhập thành công. Không có form nào được gửi, không dùng tài khoản, cookie, OTP hay token. Bộ XCTest kiểm tra allowlist và che hostname; simulator không kiểm chứng dịch vụ Meta thật. Cần thử bản đã ký trên iPhone để biết Muse có hoàn tất luồng đăng nhập trong WKWebView.

## Kết quả build hiện tại

- IPA unsigned 0.1.3 (build 10), arm64 iOS; 32 unit tests và một UI test qua, một test notification bị skip vì chưa cấp quyền.
- SHA-256: `433d08fff50414a3136c390eb165c45880ed9abf5aed096b2ca6fa8d5be7c1fb`.
- Tải IPA và điều kiện ký/cài: [DELIVERY.md](../DELIVERY.md). Kết quả XCTest/IPA: [TEST_REPORT.md](../TEST_REPORT.md).

## Bằng chứng và giới hạn

Mã JavaScript công khai của `muse.ai` chứa URL OIDC `https://auth.meta.com/oidc`, giới hạn callback đăng nhập ở origin HTTPS của auth cùng các trang `/auth_platform` trên `www.facebook.com`/`www.instagram.com`, và tham chiếu trang điều khoản Meta trên `auth.meta.com`. Đây là bằng chứng về cấu hình client được phục vụ tại thời điểm nghiên cứu; tài nguyên frontend có thể đổi, và các chuỗi endpoint không chứng minh trình duyệt của người dùng đã đi qua chúng. Meta xác nhận web Muse sử dụng Meta Account, nhưng tài liệu công khai được kiểm tra không hứa hỗ trợ đăng nhập trong ứng dụng WKWebView của bên thứ ba.

`ASWebAuthenticationSession` không phải đường thay thế tự động cho profile WKWebView: Apple mô tả đó là phiên xác thực do hệ thống quản lý có callback riêng, không phải API nhận `WKWebsiteDataStore(forIdentifier:)`. Chuyển cookie hoặc token qua các phiên bị loại trừ vì phá cách ly và không có hợp đồng hỗ trợ.

Nếu vẫn lỗi, chỉ cần người dùng báo hostname an toàn hiện trong app và mã lỗi nếu có. Không gửi URL, path/query, email/số điện thoại, mã xác minh, ảnh đăng nhập hoặc thông tin phiên. Không thêm hostname tiếp theo cho đến khi đối chiếu với tài nguyên Muse mới và nguồn chính thức.

## Nguồn

- [Trang Muse](https://muse.ai/) và JavaScript công khai hiện tại: [`0tmjjrf9k1ayz.js`](https://muse.ai/_next/static/immutable/chunks/0tmjjrf9k1ayz.js), [`0tumyugx4k7kx.js`](https://muse.ai/_next/static/immutable/chunks/0tumyugx4k7kx.js).
- [Meta: How to get started with Muse](https://www.meta.com/help/superintelligence/1331373868832401/); [Meta: Manually Build a Login Flow](https://developers.facebook.com/documentation/facebook-login/guides/advanced/manual-flow/).
- [Apple: WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore); [Apple: ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession); [Apple: WKNavigationDelegate](https://developer.apple.com/documentation/webkit/wknavigationdelegate).
- [MuseFleet Actions run 46095940301](https://github.com/dungprovaidai/MuseFleet/actions/runs/46095940301), source `6f84487c6f37dcbcfa758b9d776b8c8a596c65e4`.
