# Proxy SHOP DHP — build demo

Source UI đã được thay bằng giao diện demo Proxy SHOP DHP:

- Home: card Free Fire Max / Free Fire, không có menu dưới.
- Khung iOS + Device + Có Hỗ Trợ ở trên cùng.
- Nút ⚙️ ở góc phải phía trên mở Cài Đặt.
- Cài Đặt: Ngôn Ngữ, Kiểm Tra Cập Nhật, Xóa Bộ Nhớ Đệm, Chia Sẻ, Thông Tin Ứng Dụng, License Key, Chính Sách.
- Bấm Free Fire/Free Fire Max mở màn hình demo có tab Proxy / Định Vị / Mod NV và các công tắc giao diện.
- License Key là **demo local**: key được lưu trên thiết bị/app và gắn với HWID app-scoped. Chưa có server cấp phép thật.

## GitHub Actions

Workflow `.github/workflows/ios-build.yml` tạo **IPA unsigned** để kiểm tra build. IPA unsigned cần được ký bằng Apple Developer/eSign hoặc công cụ ký hợp lệ trước khi cài trên iPhone.

## Xcode

Mở `ThreeOneOSFive.xcodeproj`, chọn scheme `3105`, target iPhone, đặt Team/Signing trong Xcode rồi Archive.

## Proxy SHOP DHP update

- Home shows live iOS version, device model, and the configured compatibility status.
- Settings supports Vietnamese/English.
- License UI accepts `DHP-IPA-XXXXXX` keys and can call the included `server/` API.
- Device identity uses IDFV/app-scoped Device ID; iOS apps should not claim to read the hardware UDID.
- Feature switches are UI-only demo controls. Unintegrated features intentionally show maintenance and switch back off.
- The included server provides a generic admin dashboard and key management. Keep admin credentials on the server via environment variables.
