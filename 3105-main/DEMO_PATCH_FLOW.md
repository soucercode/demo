# Proxy SHOP DHP — Demo Patch Flow

This build implements the patch UX as a safe in-app demo.

## Flow

1. Open a patch project.
2. Tap a `.3105` file.
3. A Patch sheet appears with the file name, bundle ID and target path.
4. Tap **Áp dụng patch**.
5. A 3-second progress indicator is shown.
6. The app writes the replacement payload to its own sandbox under:

`Application Support/ProxySHOPDHP/DemoGameData/<bundleID>/...`

7. The app reads the file back and verifies that the written bytes match.
8. Only after verification does the UI show **Áp dụng patch thành công**.

Files without a replacement payload are shown as **File đang được bảo trì** and cannot be applied.

## Important

This demo does not modify, inject into, or write to Free Fire/Free Fire MAX containers. It only simulates the destination structure inside the Proxy SHOP DHP app sandbox so the UI and state flow can be tested safely.
