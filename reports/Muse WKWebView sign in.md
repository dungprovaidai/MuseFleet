# Đăng nhập Muse trong WKWebView

## Kết luận

Ảnh của người dùng cho thấy app đã hủy redirect main-frame; ảnh kế tiếp xác định hostname là `auth.muse.ai`. Bản 0.1.3 đã sửa luồng `auth.meta.com`, nhưng ảnh mới chứng minh redirect kế tiếp sang hostname Muse-specific vẫn bị chặn. Tra DNS công khai qua hai nhà cung cấp độc lập cho thấy `auth.muse.ai` CNAME tới `star.c10r.facebook.com`; đồng thời frontend Muse hiện có hành vi công khai liên quan đến saved-account/AYMH redirect cycle. Đây là đủ căn cứ để thêm đúng HTTPS origin `auth.muse.ai`, không wildcard domain.

Đây là thay đổi chính sách dựa trên hostname do người dùng quan sát, DNS delegation công khai và ngữ cảnh frontend Muse. Nó không chứng minh path phía sau hostname hoặc tính tương thích WKWebView. HTTPS GET không đăng nhập tới root trả 404; ảnh không lộ path/query nên không thể kiểm tra endpoint cụ thể. Không có form nào được gửi, không dùng tài khoản, cookie, OTP hay token. XCTest kiểm tra exact host và từ chối host giả/HTTP/cổng bất thường; simulator không kiểm chứng dịch vụ Meta thật. Cần thử bản đã ký trên iPhone để xác nhận bước đăng nhập.

## Kết quả build hiện tại

- IPA unsigned 0.1.4 (build 11), arm64 iOS; kiểm thử Apple runner đang chạy.
- Commit source: `5d7282608f21008d3828f4dd749a1f4b052df1b3`.
- Tải IPA/checksum sẽ được ghi vào [DELIVERY.md](../DELIVERY.md) sau khi workflow hoàn tất và artifact được xác minh.

## Bằng chứng và giới hạn

Mã JavaScript công khai của `muse.ai` chứa URL OIDC `https://auth.meta.com/oidc`, giới hạn callback đăng nhập ở origin HTTPS của auth cùng các trang `/auth_platform` trên `www.facebook.com`/`www.instagram.com`, và tham chiếu trang điều khoản Meta trên `auth.meta.com`. Đây là bằng chứng về cấu hình client được phục vụ tại thời điểm nghiên cứu; tài nguyên frontend có thể đổi, và các chuỗi endpoint không chứng minh trình duyệt của người dùng đã đi qua chúng. Meta xác nhận web Muse sử dụng Meta Account, nhưng tài liệu công khai được kiểm tra không hứa hỗ trợ đăng nhập trong ứng dụng WKWebView của bên thứ ba.

Hai truy vấn DNS-over-HTTPS (Google, Cloudflare) cùng trả CNAME `auth.muse.ai` tới `star.c10r.facebook.com`. HTTPS GET không đăng nhập tới root trả HTTP 404; không kết luận host hỏng vì path thực trong screenshot đã bị lược bỏ. Bundle Muse công khai có UI về saved accounts/AYMH và redirect-cycle, nhưng không chứa hostname `auth.muse.ai`; host được thêm nhờ quan sát thực tế của người dùng kết hợp DNS delegation, không dựa vào capture giao thức bên thứ ba.

`ASWebAuthenticationSession` không phải đường thay thế tự động cho profile WKWebView: Apple mô tả đó là phiên xác thực do hệ thống quản lý có callback riêng, không phải API nhận `WKWebsiteDataStore(forIdentifier:)`. Chuyển cookie hoặc token qua các phiên bị loại trừ vì phá cách ly và không có hợp đồng hỗ trợ.

Nếu vẫn lỗi, chỉ cần người dùng báo hostname an toàn hiện trong app và mã lỗi nếu có. Không gửi URL, path/query, email/số điện thoại, mã xác minh, ảnh đăng nhập hoặc thông tin phiên. Không thêm hostname tiếp theo cho đến khi đối chiếu với tài nguyên Muse mới và nguồn chính thức.

## Nguồn

- [Trang Muse](https://muse.ai/) và JavaScript công khai hiện tại: [`0tmjjrf9k1ayz.js`](https://muse.ai/_next/static/immutable/chunks/0tmjjrf9k1ayz.js), [`0tumyugx4k7kx.js`](https://muse.ai/_next/static/immutable/chunks/0tumyugx4k7kx.js).
- [Meta: How to get started with Muse](https://www.meta.com/help/superintelligence/1331373868832401/); [Meta: Manually Build a Login Flow](https://developers.facebook.com/documentation/facebook-login/guides/advanced/manual-flow/).
- [Apple: WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore); [Apple: ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession); [Apple: WKNavigationDelegate](https://developer.apple.com/documentation/webkit/wknavigationdelegate).
- [Google DNS-over-HTTPS](https://dns.google/resolve?name=auth.muse.ai&type=CNAME); [Cloudflare DNS-over-HTTPS](https://cloudflare-dns.com/dns-query?name=auth.muse.ai&type=CNAME).
- Muse first-party frontend bundles: [`0vkin0knyrcae.js`](https://muse.ai/_next/static/immutable/chunks/0vkin0knyrcae.js), [`3ou-wk-9p7bb8.js`](https://muse.ai/_next/static/immutable/chunks/3ou-wk-9p7bb8.js).
- [MuseFleet Actions run 46095940301](https://github.com/dungprovaidai/MuseFleet/actions/runs/46095940301), source `6f84487c6f37dcbcfa758b9d776b8c8a596c65e4`.
