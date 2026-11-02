# MyDash

App iPhone của bạn cho màn hình dash NMAX / XMAX. Dựa trên https://github.com/lntvan166/maxdash (không sửa gì trong repo đó).

## Tình trạng

| Phần | Trạng thái |
|---|---|
| 1. Khung dự án (XcodeGen, Info.plist, workflow) | xong, chưa build |
| 2. Mã giao thức Link A (`Packages/DashProtocol`) | xong, chưa chạy bằng Swift thật |
| 3. Test theo bộ vector | xong, sẽ chạy trong GitHub Actions |
| 4. Đọc link chia sẻ từ Google Maps (`ShareLinkParser`) | xong phần đọc link, test bằng vector; chưa có nút Share trong app |
| 5. Chỉ đường, theo dõi vị trí | chưa làm |
| 6. Vẽ bản đồ thành ảnh JPEG | chưa làm |
| 7. Chạy nền khi khóa máy | chưa làm |
| Kết nối thật với dash (ExternalAccessory) | xong, gửi hình thử (lưới kẻ + số đếm), chưa thử trên xe |

## Trước khi build

Mã định danh app đã đặt là `com.nmax.mydash`. Nếu Sideloadly báo mã này đã bị người khác dùng, thêm vài chữ số (ví dụ `nmax2026`) ở **hai chỗ** trong `project.yml`: `bundleIdPrefix` và `PRODUCT_BUNDLE_IDENTIFIER`.

## Đưa lên GitHub và build

1. Cài GitHub Desktop (desktop.github.com), đăng nhập tài khoản GitHub.
2. File › Add local repository › chọn thư mục này (nếu hỏi, chọn "create a repository").
3. Commit, rồi **Publish repository**. Chọn **Public** để được dùng máy Mac miễn phí không giới hạn.
4. Vào github.com › repo của bạn › tab **Actions** › lần chạy `build-ipa`.
5. Bước **Vector tests** phải **xanh**. Nếu đỏ, KHÔNG ra xe, gửi nội dung lỗi cho trợ lý.
6. Khi xanh, tải artifact `MyDash-ipa`, giải nén ra `MyDash.ipa`, rồi cài bằng Sideloadly.

Không đưa khóa API hay mật khẩu vào repo.
