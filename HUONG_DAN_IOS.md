# Dịch phụ đề liên tục trên iPhone (app iOS gốc)

Cách hoạt động: **tiện ích ghi màn hình** (ReplayKit) đọc vùng phụ đề của app đang chạy → gửi Gemini dịch →
**app SubDich** hiện chữ Việt trong **cửa sổ nhỏ nổi (Picture-in-Picture)** trên mọi app. iOS không cho vẽ đè
lên app khác, nên cửa sổ nổi này là cách hiển thị duy nhất; bạn kéo nó đặt ở đâu tùy ý.

> Mình chưa có Xcode/Mac để biên dịch thử, nên bạn có thể gặp vài lỗi nhỏ lúc build lần đầu.
> Nếu có lỗi, chụp màn hình lỗi gửi mình để sửa.

## Cần có
- Máy Mac có **Xcode 15+**, iPhone **iOS 16+**, cáp USB.
- Apple ID miễn phí (app chạy được 7 ngày rồi phải cài lại) hoặc tài khoản nhà phát triển 99 USD/năm.
- Key Gemini (https://aistudio.google.com/apikey).

## Dựng project (khoảng 10 phút)
1. Xcode → **File ▸ New ▸ Project ▸ iOS ▸ App**. Product Name: `SubDich`, Interface: **SwiftUI**, Language: **Swift**.
   Chọn Team (Apple ID của bạn) và đặt Bundle Identifier, ví dụ `com.tenban.subdich`.
2. Xóa `ContentView.swift` và file `...App.swift` mặc định, rồi kéo 3 file trong thư mục `SubDich/` vào project
   (`SubDichApp.swift`, `ContentView.swift`, `PiPManager.swift`).
3. **File ▸ New ▸ Target ▸ Broadcast Upload Extension**.
   - Product Name: **`broadcast`** (đúng chữ thường này, vì Bundle ID phải là `<bundle app>.broadcast`).
   - **Bỏ chọn** "Include UI Extension". Nhấn Finish, nếu Xcode hỏi Activate scheme thì chọn Activate.
4. Trong target `broadcast`: mở `SampleHandler.swift` và **thay toàn bộ** bằng file `broadcast/SampleHandler.swift`;
   kéo thêm `broadcast/Translator.swift` vào target này.
5. Kéo `Shared/Shared.swift` vào project, trong khung bên phải (File Inspector ▸ Target Membership) **tick cả hai**
   target: `SubDich` và `broadcast`.
6. Cho **cả hai target** (Signing & Capabilities):
   - **+ Capability ▸ App Groups** → thêm group có tên đúng là `group.` + Bundle ID app chính,
     ví dụ `group.com.tenban.subdich`, và tick group đó ở cả hai target.
   - Chọn cùng một Team.
7. Chỉ target `SubDich`: **+ Capability ▸ Background Modes** → tick **Audio, AirPlay, and Picture in Picture**.
8. Ở cả hai target, mục General ▸ **Minimum Deployments** đặt thấp hơn hoặc bằng iOS đang dùng (nên là 16.0).
9. Cắm iPhone, bật **Chế độ nhà phát triển** (Cài đặt ▸ Quyền riêng tư & Bảo mật ▸ Chế độ nhà phát triển),
   chọn iPhone làm thiết bị đích, bấm **Run**. Lần đầu có thể phải vào Cài đặt ▸ Cài đặt chung ▸
   VPN & Quản lý thiết bị để tin cậy tài khoản của bạn.

## Cách dùng
1. Mở app **Dich phu de**, dán API key, chỉnh **vùng phụ đề** (cách lề trên, chiều cao...) cho khớp với
   chỗ phụ đề thường hiện.
2. Bấm **1. Bật cửa sổ chữ Việt (PiP)**. Cửa sổ nhỏ hiện ra, kéo nó lên **phía trên màn hình** (xa vùng phụ đề).
3. Bấm nút ghi màn hình bên cạnh dòng **2.**, chọn **broadcast**, bấm **Bắt đầu phát sóng**.
4. Chuyển sang app muốn xem (YouTube, trình phát phim, game...). Chữ Việt hiện trong cửa sổ nổi.
5. Tắt: vuốt xuống từ góc phải màn hình, bấm vào nút ghi màn hình đang đỏ, chọn Dừng.

## Giới hạn / lưu ý
- **Đặt cửa sổ PiP ra ngoài vùng phụ đề.** Nếu nó che lên vùng đang dịch, app có thể đọc chính chữ Việt của nó.
- App có bảo vệ bản quyền (Netflix, Disney+...) sẽ ra hình đen khi ghi màn hình, không dịch được.
- iOS giới hạn bộ nhớ của tiện ích ghi màn hình (~50 MB). Nếu ghi bị dừng giữa chừng, chỉnh vùng phụ đề nhỏ hơn.
- Có thể hiện chữ chậm 1–3 giây sau lời thoại do thời gian gửi và dịch.
- Nếu app chính bị iOS dừng khi ở nền, chữ sẽ không cập nhật nữa: mở lại app SubDich, bấm lại bước 1.
- Key Gemini lưu trên điện thoại. Không chia sẻ file build cho người khác.
- Đặt model nào cũng được trong ô Model. Nếu model báo lỗi, app tự thử model dự phòng.

---
# Cách B: build file .ipa trên GitHub (không cần Mac)

1. Tạo tài khoản GitHub (miễn phí), tạo repo mới (có thể để Private).
2. Giải nén `ios-project.zip` rồi kéo **toàn bộ nội dung** vào repo (nút Add file ▸ Upload files). Thư mục
   `.github` là thư mục ẩn: nếu GitHub không nhận, tự tạo file `.github/workflows/build.yml` bằng
   Add file ▸ Create new file rồi dán nội dung từ file cùng tên trong zip.
3. Vào tab **Actions** ▸ **Build IPA** ▸ **Run workflow**. Chờ khoảng 5–10 phút.
4. Mở lần chạy vừa xong, tải mục **SubDich-ipa** ở cuối trang, giải nén sẽ có `SubDich.ipa` (chưa ký).
5. Trên Windows, cài **Sideloadly** (cần iTunes bản từ trang Apple), cắm iPhone, kéo `SubDich.ipa` vào,
   đăng nhập Apple ID rồi bấm Start. Bật Chế độ nhà phát triển trên iPhone và tin cậy tài khoản trong
   Cài đặt ▸ Cài đặt chung ▸ VPN & Quản lý thiết bị.

Lưu ý: chưa kiểm thử. Có thể lỗi ở bước build (gửi mình log lỗi của Actions). App có tiện ích ghi màn hình dùng
App Groups, Apple ID miễn phí có thể không cho ký thành công; khi đó phải dùng tài khoản nhà phát triển 99 USD/năm.
Bản ký bằng Apple ID miễn phí hết hạn sau 7 ngày.
