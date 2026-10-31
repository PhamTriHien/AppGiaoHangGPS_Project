# Kế hoạch hoàn thiện GO-MAU Delivery

Ngày lập: 29/10/2026. Trạng thái: kế hoạch triển khai, chưa phải danh sách đã hoàn thành.

## 1. Mục tiêu và phạm vi

Hoàn thiện ứng dụng giao hàng kết hợp mua bán nhiều cửa hàng, có trải nghiệm mua hàng quen thuộc, nhưng sử dụng thương hiệu riêng. Đợt ra mắt đầu tập trung một ngành hàng hoặc khu vực vận hành; mô hình dữ liệu hỗ trợ mở rộng sau đó. Giữ bốn phân hệ khách hàng, cửa hàng, tài xế và quản trị viên; quản trị đăng nhập ở trang riêng.

Luồng phải chạy xuyên suốt: đăng nhập → tìm sản phẩm/cửa hàng → chọn phân loại → giỏ hàng → báo giá → đặt mua → thanh toán → cửa hàng xử lý → giao hàng → xác nhận → đối soát hoặc hậu mãi.

Không đưa livestream, quảng cáo đấu giá, trả góp, ví giữ tiền hay đề xuất bằng AI vào đường găng ra mắt. Các hạng mục này có thể đánh giá sau khi luồng mua bán và vận hành đã ổn định.

## 2. Hiện trạng đã xác định trong repo

| Hạng mục | Hiện trạng | Khoảng trống |
| --- | --- | --- |
| Tài khoản và phân quyền | Supabase Auth và quyền cloud đã có; đăng nhập chính còn local | Một danh tính thống nhất, khôi phục phiên, phê duyệt vai trò và khóa tài khoản xuyên app |
| Đơn giao hàng | API/RPC cloud có báo giá, trạng thái, lịch sử và quyền sở hữu | Nhiều màn hình cũ còn dùng đơn local; các dịch vụ nâng cao chưa cùng hợp đồng cloud |
| Cửa hàng và món ăn | Có màn hình quản lý menu, xem món và đặt món | Catalog cloud, sản phẩm/phân loại, tồn kho, xuất bản và kiểm duyệt |
| Giỏ hàng | Có luồng giỏ đặt món | Giỏ cloud, chia đơn theo shop, giá và tồn kho do server xác nhận |
| Ưu đãi | Có voucher, xu, chiến dịch và trò chơi local | Ngân sách, giới hạn, chống nhận trùng và ghi nhận server |
| Thanh toán | Tích hợp payOS cho cước vận chuyển cloud | Thanh toán tiền hàng, phân bổ theo shop, hoàn tiền và đối soát |
| Vận chuyển | Tài xế nội bộ và tích hợp GHN | Liên kết đơn mua hàng với từng vận đơn; mở rộng loại dịch vụ có kiểm soát |
| Đồng bộ | Hàng đợi v9 tách dự án/tài khoản, giữ thao tác chưa xác nhận | Cache và dữ liệu của toàn bộ màn hình chưa cùng nguồn cloud |
| Triển khai | Đã có kiểm tra cấu hình và migration | Backend HTTPS, provider credentials và kiểm chứng giao dịch thực tế trước mở bán |

Có giao diện hoặc integration không có nghĩa đã đủ điều kiện vận hành thật. Không dùng tên bảng legacy làm hợp đồng dữ liệu thương mại mới.

## 3. Nguyên tắc triển khai

- Supabase Auth xác thực; backend/API và RPC kiểm tra quyền, giá, tồn kho, thanh toán và chuyển trạng thái. Local RBAC không cấp quyền cloud.
- Cloud là nguồn dữ liệu nghiệp vụ chính. SQLite/localStorage là cache có phạm vi tài khoản và nơi giữ nháp, không phải nơi tự quyết định số dư hoặc giao dịch.
- Tái sử dụng backend, Flutter và cơ chế migration hiện có; tổ chức module trong cùng backend trước khi cân nhắc tách dịch vụ.
- Phân biệt đơn mua hàng, đơn theo shop, giao dịch thanh toán và vận đơn. Không ép tất cả vào một trạng thái đơn giao hàng.
- Tất cả khóa provider và kết nối PostgreSQL ở backend. Web/app chỉ nhận public config và phiên người dùng.
- Migration bổ sung, có sao lưu và kế hoạch phục hồi. Không reset database, không tạo tài khoản giả, không tự tải toàn bộ dữ liệu thiết bị lên cloud.
- Callback, đặt hàng, giữ tồn và ghi sổ phải chịu được gửi lặp, timeout, sự kiện sai thứ tự và nhiều thiết bị cùng thao tác.
- Backend tự xử lý các việc hết hạn và đối soát; không phụ thuộc việc app đang mở. Dùng job bền vững và transactional outbox cho tác vụ ngoài database.

## 4. Các giai đoạn và điều kiện nghiệm thu

### P0. Thống nhất tài khoản, API và dữ liệu

Độ lớn: lớn. Là điều kiện cho tất cả các giai đoạn sau.

- Kiểm kê từng màn hình, thao tác đọc/ghi, bảng dữ liệu và quyền; đánh dấu local, cloud hoặc chưa có backend.
- Đăng nhập/đăng ký/khôi phục mật khẩu thống nhất Supabase Auth. Kiểm tra lại Google OAuth hiện có trước khi thay luồng; cấu hình Gmail gửi OTP không thay thế Google provider.
- Một hồ sơ người dùng; quyền mua hàng cơ bản, tư cách chủ shop/tài xế được phê duyệt riêng. Quyền quản trị tách khỏi tư cách kinh doanh; chỉ chuyển không gian làm việc khi server cho phép.
- Thay các repository local của màn hình chính bằng adapter API; kiểm soát phiên, phân trang, realtime/polling và thông báo lỗi thống nhất.
- Cache theo URL dự án + Auth user ID; xóa trạng thái nhạy cảm trong bộ nhớ khi đăng xuất/đổi tài khoản. Hàng đợi chỉ gửi lại lệnh có chủ sở hữu xác định và hợp đồng backend tương ứng.
- Chuyển dữ liệu local bằng công cụ có xem trước, kiểm tra trùng và quyền sở hữu; có báo cáo bản ghi cần xử lý thủ công. Không suy ra mật khẩu Auth từ hash SQLite.
- Gộp các lối vào cloud riêng thành luồng ứng dụng chính sau khi chuyển xong; thông tin môi trường/API chỉ nằm trong quản trị.

Nghiệm thu: cùng tài khoản trên hai thiết bị đọc đúng hồ sơ và đơn; đổi tài khoản không thấy dữ liệu cũ; gọi API trực tiếp cũng không vượt quyền; màn hình đã chuyển không đọc dữ liệu legacy làm kết quả chính.

### P1. Catalog và gian hàng cloud

Độ lớn: lớn. Phụ thuộc P0.

- Gian hàng: thông tin công khai, ảnh, giờ hoạt động, khu vực phục vụ, tạm nghỉ và trạng thái phê duyệt.
- Sản phẩm: danh mục, ảnh, giá, mô tả, phân loại/SKU, trạng thái còn bán, chuẩn bị, khối lượng và kích thước phục vụ giao hàng.
- Ngành đồ ăn: nhóm lựa chọn/topping, số lượng tối thiểu/tối đa, phụ thu và lịch bán; không ép topping thành hàng hóa tồn kho nếu không phù hợp.
- Tồn kho có sổ biến động, giữ chỗ có thời hạn và giao dịch nguyên tử; quy tắc kiểm soát tồn cho từng ngành hàng.
- Ảnh lưu Storage với quyền ghi theo shop, giới hạn dung lượng và kiểm tra định dạng. Trang công khai không lộ hồ sơ KYC hoặc tài khoản ngân hàng.
- Tìm kiếm và lọc phía server, phân trang; sản phẩm bị ẩn/hết bán không thể mua bằng URL/API cũ.

Nghiệm thu: shop A không sửa hàng shop B; thay giá và ẩn hàng phản ánh trên thiết bị khách; nhiều khách mua đồng thời không làm tồn âm.

### P2. Giao diện người mua và luồng checkout

Độ lớn: lớn. Phụ thuộc P1.

- Điều hướng chính: Khám phá, Đơn hàng, Thông báo, Tài khoản; giỏ hàng có lối vào nhất quán. Giữ đặt giao hàng trực tiếp thành một dịch vụ rõ ràng.
- Trang khám phá có tìm kiếm, danh mục, cửa hàng phù hợp địa chỉ và sản phẩm thật; không chèn banner, đánh giá hoặc số lượt bán giả.
- Chi tiết sản phẩm: thư viện ảnh, giá theo lựa chọn, tồn khả dụng, cửa hàng, điều kiện giao và đánh giá đã xác minh.
- Trang shop: tìm trong shop, danh mục, thông tin hoạt động, đánh giá và theo dõi/yêu thích.
- Giỏ cloud theo tài khoản, gộp SKU hợp lệ, chia nhóm shop, lưu khi đổi thiết bị. Chỉ lưu ID và lựa chọn; checkout đọc lại giá server.
- Checkout: sổ địa chỉ cloud, địa chỉ và tọa độ hợp lệ, ghi chú, lịch nhận nếu được hỗ trợ, phương thức thanh toán, ưu đãi và chi tiết tổng tiền theo shop.
- Báo giá có hạn và phiên bản; thay số lượng/địa chỉ/ưu đãi phải tính lại. Giá thay đổi cần khách xác nhận lại.
- Một checkout sinh đơn cha và đơn shop theo giao dịch; giữ tồn và mã yêu cầu chống lặp. Không gửi request độc lập từng shop rồi báo cả giỏ thành công khi mới tạo được một phần.
- Trạng thái đầy đủ: đang tải, rỗng, mất mạng, hết hàng, giá thay đổi, thanh toán chưa rõ kết quả; layout desktop/mobile không tràn nội dung.

Nghiệm thu: giỏ hai shop tạo đúng hai đơn con, tiền đúng và không trùng khi bấm lại; nháp offline không tự trở thành đơn đã xác nhận; restart app vẫn khôi phục trạng thái thanh toán.

### P3. Tiền hàng, giao dịch và đối soát

Độ lớn: rất lớn. Phụ thuộc P2; chốt chính sách vận hành trước khi mở bán.

- Mở rộng payment model từ cước giao hàng sang tổng checkout gồm tiền hàng, cước và giảm giá; lưu snapshot và phân bổ rõ từng shop.
- Xử lý trường hợp nhiều shop, một shop hủy, COD và trả trước; chốt phương án thu tiền/phân bổ theo khả năng provider, không mặc định provider hỗ trợ split payment.
- Chỉ xác nhận thu tiền từ bằng chứng provider đã kiểm chứng. Callback trùng, thiếu tiền, dư tiền, sai đơn, timeout hoặc đến muộn đi qua quy trình đối soát.
- Sổ giao dịch bất biến, cân bằng và tách trạng thái thanh toán khỏi trạng thái giao hàng. Số dư doanh thu dự kiến không được trình bày như tiền đã có thể rút.
- Đối soát tiền hàng, COD, phí nền tảng, cước hãng và khoản trả shop; bảng kê có nguồn đối chiếu, xuất dữ liệu và lịch sử duyệt.
- Hoàn tiền toàn phần/một phần có lý do, phê duyệt và trạng thái. Chỉ đánh dấu hoàn tiền khi provider hoặc người vận hành có bằng chứng chuyển trả; không giả định payOS hiện tại đã có API hoàn tiền.
- Phân quyền người đề nghị và người phê duyệt thao tác tài chính; lưu audit. Không triển khai ví giữ tiền khách trong phạm vi ra mắt đầu.

Nghiệm thu: đối chiếu được từng khoản thu/chi với đơn và giao dịch ngoài hệ thống; thử callback lặp/sai thứ tự, hủy một shop và hoàn một phần không nhân đôi bút toán hoặc làm sai tổng tiền.

### P4. Xử lý đơn cửa hàng và giao nhận

Độ lớn: lớn. Phụ thuộc P2, phối hợp P3.

- Shop có hàng đợi đơn mới, xác nhận/từ chối theo hạn, chuẩn bị, đóng gói và bàn giao; thông báo và audit mọi thay đổi.
- Liên kết đơn shop với một hoặc nhiều vận đơn khi cần; quy định rõ giao một phần, tách kiện, hủy và giao lại.
- Đồng bộ dịch vụ nội bộ đang có: tiêu chuẩn, nhanh, 2H, đa điểm, khứ hồi và xe điện. Chỉ hiển thị loại đã được backend hỗ trợ và có cách tính phí thật.
- Tài xế có hàng đợi phù hợp, nhận đơn nguyên tử, điều hướng, bằng chứng lấy/giao, lý do thất bại và giao lại/hoàn hàng.
- GHN là phương án fulfillment riêng; không đồng thời giao một vận đơn cho GHN và tài xế nội bộ. Callback và đối soát dùng đúng môi trường staging/production.
- Chia sẻ theo dõi bằng token thu hồi được, có hạn; ẩn điện thoại đầy đủ, OTP, KYC, bằng chứng riêng tư và dữ liệu ngoài phạm vi người xem.

Nghiệm thu: chạy được đơn nội bộ và đơn hãng từ shop đến kết thúc; trạng thái giao hàng không tự xác nhận thu COD hay hoàn tiền; quyền xem địa chỉ/GPS thay đổi đúng vai trò và giai đoạn.

### P5. Hậu mãi, đánh giá và tương tác

Độ lớn: vừa đến lớn. Phụ thuộc P3/P4.

- Hủy trước/sau xác nhận với điều kiện và phí minh bạch; mọi trường hợp trả trước liên kết xử lý tiền.
- Trả hàng/hoàn tiền theo từng dòng sản phẩm: lý do, ảnh, hạn yêu cầu, phản hồi shop, bằng chứng, vận đơn hoàn và quản trị giải quyết tranh chấp.
- Chỉ người mua đủ điều kiện được đánh giá sản phẩm/shop; tách đánh giá tài xế khỏi sản phẩm; ảnh có kiểm duyệt và cơ chế báo cáo.
- Chat người mua/shop và hỗ trợ theo đơn, tệp riêng tư, chống spam; thông báo trong app và push không gửi dữ liệu nhạy cảm không cần thiết.
- Theo dõi shop, yêu thích sản phẩm và mua lại; mua lại vẫn kiểm tra giá, tồn và trạng thái bán hiện tại.

Nghiệm thu: không gửi đánh giá bằng đơn người khác; không đổi trả vượt số lượng đã mua; mọi yêu cầu hậu mãi truy được quyết định và giao dịch liên quan.

### P6. Khuyến mãi và công cụ quản trị thương mại

Độ lớn: lớn. Phụ thuộc nền checkout và tài chính đã ổn định.

- Voucher shop, voucher nền tảng và freeship có bên tài trợ, ngân sách, điều kiện áp dụng và quy tắc cộng dồn.
- Flash sale có tồn phân bổ, thời gian server, giới hạn theo người và giữ ưu đãi nguyên tử khi đặt đơn.
- Xu và điểm thưởng có sổ phát sinh server, quy tắc tích/đổi/thu hồi khi hủy hoặc hoàn tiền. Loại bỏ phần thưởng khởi tạo và kết quả may rủi tự cấp trên client khỏi luồng production.
- Trò chơi khuyến mãi chỉ bật sau khi có quy tắc vận hành, ngân sách và đánh giá nghĩa vụ áp dụng; không là điều kiện ra mắt.
- Admin quản lý shop, sản phẩm, đơn mua, vận đơn, giao dịch, tranh chấp, chương trình và cấu hình provider trong các mục rõ ràng.
- Báo cáo từ dữ liệu thực: doanh thu gộp, đơn hủy/hoàn, phí, thời gian xử lý, tỷ lệ giao và khoản chưa đối soát. Phân biệt số liệu ước tính với số liệu đã quyết toán.

Nghiệm thu: không vượt ngân sách khi nhiều người đổi mã cùng lúc; một giao dịch không nhận thưởng hai lần; số liệu báo cáo khớp dữ liệu gốc và có bộ lọc thời gian/phạm vi rõ ràng.

### P7. Triển khai và ra mắt có kiểm soát

Độ lớn: lớn, thực hiện hạ tầng sớm từ P0; chỉ mở bán sau các cổng nghiệm thu cần thiết.

- Tách dev/staging/production; backend HTTPS chạy liên tục, kiểm tra health/readiness, quản lý cấu hình và khóa trên server.
- Chuẩn bị domain, redirect Auth, email giao dịch, callback payOS/GHN và cấu hình mobile push cần thiết. Kiểm tra provider thật với tài khoản và môi trường được phép.
- CI chạy phân tích, test, kiểm tra migration/RLS và build; deploy có phiên bản, tương thích app cũ, backup và diễn tập khôi phục.
- Giám sát lỗi, độ trễ, job thất bại, webhook và hàng đợi; cảnh báo cho người vận hành, có cách đối soát và chạy lại an toàn.
- Kiểm thử tải theo lưu lượng mục tiêu đã chốt; kiểm thử cạnh tranh tồn kho, tranh nhận đơn, tài khoản bị khóa và mất mạng giữa giao dịch.
- Hoàn thiện điều khoản, quyền riêng tư, chính sách vận chuyển/hủy/đổi trả, quy trình hỗ trợ và các yêu cầu phát hành/kinh doanh phù hợp mô hình thực tế; xác minh khi chốt phạm vi triển khai.
- Pilot với shop/tài xế/người mua thật được mời; dữ liệu kiểm thử tách khỏi production. Mở rộng sau khi kiểm chứng đối soát, hỗ trợ và khả năng phục hồi.

Nghiệm thu: đặt mua và xử lý giao dịch xuyên suốt trên môi trường triển khai; không có dữ liệu demo trong production; khôi phục backup thành công; người vận hành xử lý được các ca thanh toán chưa rõ kết quả và khiếu nại.

## 5. Mô hình dữ liệu dự kiến

Tên bảng cuối cùng theo quy ước migration trong repo. Đây là nhóm thực thể cần thiết, không phải schema đã được tạo.

| Nhóm | Thực thể và quan hệ |
| --- | --- |
| Danh tính | Auth user, hồ sơ, tư cách thành viên shop, phê duyệt tài xế, quyền operator |
| Catalog | Shop, danh mục, sản phẩm, media, SKU, lựa chọn món, lịch bán |
| Tồn kho | Số lượng, giao dịch tồn, reservation, hạn giữ, trả tồn |
| Mua hàng | Cart, cart item, quote, checkout, purchase order, shop order, order item snapshot |
| Giao nhận | Liên kết shop order/kiện với delivery_cloud_orders, assignment, bằng chứng và lịch sử |
| Tài chính | Payment attempt, receipt, allocation, ledger entry, refund, settlement và COD collection |
| Ưu đãi | Campaign, voucher, reservation/redemption, ngân sách, reward ledger |
| Hậu mãi | Return request/item, dispute, evidence, resolution và review theo dòng đơn |
| Hạ tầng | Notification, outbox, durable job, idempotency record, audit và theo dõi lỗi |

Giá, mô tả mua, lựa chọn, giảm giá và phí được chụp lại tại thời điểm mua. Thay đổi catalog sau này không viết lại đơn lịch sử. Dùng đơn vị tiền nguyên, tránh số thực cho bút toán tiền VND.

## 6. Thứ tự thực thi và điểm dừng phát hành

1. P0: chốt danh tính, bảng nguồn và hợp đồng API; chuyển màn hình đăng nhập, hồ sơ và đơn chính.
2. P1: xây catalog cloud và tồn kho; shop đăng một sản phẩm thật, thiết bị khách tìm thấy và xem được.
3. P2: hoàn thiện một checkout xuyên suốt, sau đó mở giỏ nhiều shop và kiểm thử cạnh tranh.
4. P3/P4: nối tiền hàng, đối soát và fulfillment; không mở thanh toán thật khi chưa xử lý được trạng thái không chắc chắn.
5. P5: hoàn thiện hậu mãi tối thiểu trước pilot có giao dịch thật.
6. P7: nghiệm thu staging và pilot giới hạn. Hạ tầng triển khai, giám sát và backup được chuẩn bị từ P0.
7. P6 và phần mở rộng P5: triển khai sau luồng cốt lõi; có thể dùng ưu đãi đơn giản trước, chưa bật hệ thống xu/trò chơi.

Mỗi lần triển khai gồm migration, API/RLS, giao diện liên quan, kiểm thử rủi ro và bằng chứng nghiệm thu. Không tính hoàn thành khi chỉ có màn hình hoặc endpoint chưa được nối vào luồng chính.

## 7. Lô công việc bắt đầu trước

- [x] Lập ma trận màn hình → repository → bảng/API → quyền → trạng thái local/cloud (P0_SYNC_MATRIX.md).
- [x] Code/profile schema 3 và kiểm thử cô lập cho quyền mua cơ bản cùng hai tư cách merchant/driver độc lập; operator duyệt riêng, chưa áp dụng cloud hoặc nghiệm thu hai thiết bị thật.
- [x] Giao diện chính mới dùng Supabase Auth và phiên/hồ sơ server; giữ trang quản trị riêng và dữ liệu legacy tách biệt. Google/recovery email thật còn cần nghiệm thu.
- [x] Hồ sơ, sổ địa chỉ, đơn mua và dịch vụ gửi hàng ở app chính gọi API theo phiên; lịch sử legacy vẫn riêng, không nhập tự động.
- [x] Bổ sung sổ địa chỉ cloud và chọn địa chỉ trong form đặt đơn cloud; chưa thay toàn bộ màn hình legacy.
- [x] Dùng controller phiên/hồ sơ chung trong màn hình đơn cloud; kiểm thử khôi phục, thu hồi quyền, tài khoản bị khóa, phản hồi cũ và đổi dự án.
- [x] Đưa phiên cloud lên cấp app, tái sử dụng form hồ sơ và bảo vệ các trang/hộp thoại con khi phiên thay đổi; chưa chuyển login/lịch sử chính khỏi SQLite.
- [x] Trang chi tiết/lịch sử đơn cloud và gửi lại đơn giao hàng với báo giá mới; kiểm tra quyền trước khi hiện thông tin, không dùng dữ liệu local dự phòng. Chưa phải luồng mua lại sản phẩm hoặc lịch sử trong giao diện chính.
- [ ] Kiểm thử hai tài khoản, hai thiết bị, đăng xuất/đổi dự án, phiên hết hạn và tài khoản bị khóa.
- [x] Migration catalog/stock/cart/checkout COD đầu tiên, UI merchant và kiểm thử SQL/gateway/Flutter đã có; chưa áp dụng project thật. Không bao gồm mọi yêu cầu P1/P2.

Tiến độ chi tiết, các mục chưa thực hiện và cổng nghiệm thu nằm trong EXECUTION_CHECKLIST.md. Chưa có giai đoạn nào được chứng nhận hoàn tất thương mại chỉ từ các ô code đã tích ở trên.

Ước lượng thời gian chỉ nên chốt sau ma trận P0 và một luồng catalog/checkout đầu tiên. Phạm vi này lớn hơn bổ sung giao diện; nhân lực, ngành hàng, chính sách tiền/hoàn hàng và cấu hình provider là các yếu tố quyết định tiến độ.
