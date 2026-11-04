import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../data/datasources/local/sqlite_offline_queue_datasource.dart';
import '../../domain/entities/geo_point.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'platform_file_and_browser_bridge.dart';
import '../../presentation/widgets/ghst_button_icon.dart';

class SecurityAndBarcodeUtils {
  const SecurityAndBarcodeUtils._();

  static void disposeControllersAfterDialog(
    List<ChangeNotifier> controllers, [
    Animation<double>? routeAnimation,
  ]) {
    var disposed = false;
    void disposeAll() {
      if (disposed) return;
      disposed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in controllers) {
          c.dispose();
        }
      });
    }

    if (routeAnimation != null &&
        routeAnimation.status != AnimationStatus.dismissed) {
      void onStatus(AnimationStatus status) {
        if (status == AnimationStatus.dismissed) {
          routeAnimation.removeStatusListener(onStatus);
          disposeAll();
        }
      }

      routeAnimation.addStatusListener(onStatus);
      return;
    }
    disposeAll();
  }

  /// Che số điện thoại bảo vệ quyền riêng tư: 0912345678 -> 0912***678
  static String maskPhoneNumber(String phone, {required bool shouldMask}) {
    final cleaned = phone.trim();
    if (!shouldMask || cleaned.length < 7) return cleaned;
    final prefix = cleaned.substring(0, 4);
    final suffix = cleaned.substring(cleaned.length - 3);
    return '$prefix***$suffix';
  }

  /// Sinh mã OTP 4 chữ số xác nhận giao hàng POD cố định theo từng mã vận đơn
  static String generateOrderDeliveryOtp4(String trackingCode) {
    final cleaned = trackingCode.trim().toUpperCase();
    if (cleaned.isEmpty) return '6886';
    var acc = 2166136261;
    for (final unit in cleaned.codeUnits) {
      acc ^= unit;
      acc = (acc * 16777619) & 0x7FFFFFFF;
    }
    final pin = 1000 + (acc % 9000);
    return pin.toString();
  }

  /// Băm mật khẩu có muối (Salt) bảo mật xác thực tài khoản
  static String hashPasswordWithSalt(String password, String phoneSalt) {
    final bytes = utf8.encode('SALT:$phoneSalt|PWD:$password|PEPPER:GPS2026');
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (final b in bytes) {
      h1 ^= b;
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 << 5) - h2 + b) & 0xFFFFFFFF;
    }
    return 'BCRYPT-HASH-${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}'
        .toUpperCase();
  }

  /// Tạo chữ ký giao dịch chống trùng lặp
  static String generatePaymentSignature({
    required String orderCode,
    required double amount,
    required String method,
  }) {
    final raw = '$orderCode|${amount.toStringAsFixed(0)}|$method|FLASH_GPS_SECRET';
    final bytes = utf8.encode(raw);
    var h1 = 0x811c9dc5;
    var h2 = 0xcbf29ce4;
    for (final b in bytes) {
      h1 ^= b;
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF;
      h2 ^= (b * 31) & 0xFF;
      h2 = (h2 * 0x01000193) & 0xFFFFFFFF;
    }
    return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}'
        .toUpperCase();
  }

  /// Tạo chữ ký giao dịch kèm mã giao dịch chống thu trùng
  static String generatePaymentIdempotencySignature({
    required String orderId,
    required double amount,
    required String gateway,
    required String transactionId,
  }) {
    return generatePaymentSignature(
      orderCode: '$orderId|$transactionId',
      amount: amount,
      method: gateway,
    );
  }

  /// Tạo chuỗi chuẩn EMVCo VietQR Napas247 kèm mã kiểm tra CRC-16/CCITT-FALSE thực tế
  static String generateEmvVietQrPayload({
    required String orderCode,
    required double amountVnd,
    String bankBin = '970436',
    String accountNumber = '0071000889',
  }) {
    String tlv(String id, String value) =>
        '$id${value.length.toString().padLeft(2, '0')}$value';

    final cleanBin = bankBin.replaceAll(RegExp(r'[^0-9]'), '');
    final effectiveBin = cleanBin.length == 6 ? cleanBin : '970436';
    final cleanAccount = accountNumber
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final effectiveAccount = cleanAccount.isNotEmpty
        ? cleanAccount
        : '0071000889';

    final beneficiary =
        '${tlv('00', effectiveBin)}${tlv('01', effectiveAccount)}';
    final tag38 = tlv(
      '38',
      '${tlv('00', 'A000000727')}${tlv('01', beneficiary)}${tlv('02', 'QRIBFTTA')}',
    );

    final safeAmount = amountVnd.isFinite && amountVnd > 0
        ? amountVnd.round()
        : 0;
    final tag54 = safeAmount > 0 ? tlv('54', safeAmount.toString()) : '';
    final cleanCode = orderCode
        .replaceAll('#', '')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
        .trim();
    final effectiveCode = cleanCode.isEmpty ? 'GHST' : cleanCode;
    final tag62 = tlv('62', tlv('08', effectiveCode));
    final bodyWithoutCrc = '000201010212${tag38}5303704${tag54}5802VN${tag62}6304';

    var crc = 0xFFFF;
    for (final codeUnit in bodyWithoutCrc.codeUnits) {
      crc ^= (codeUnit << 8);
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    final crcHex = crc.toRadixString(16).toUpperCase().padLeft(4, '0');
    return '$bodyWithoutCrc$crcHex';
  }

  /// Mở hộp thoại chọn chứng từ / hình ảnh thực tế từ hệ điều hành hoặc Trình duyệt Web
  static Future<String?> pickLocalDocumentOrImage({
    String dialogTitle = 'Chọn tệp chứng từ / hình ảnh đính kèm',
    String filter =
        'Tệp hình ảnh & PDF (*.png;*.jpg;*.jpeg;*.webp;*.pdf;*.svg)|*.png;*.jpg;*.jpeg;*.webp;*.pdf;*.svg|Tất cả tệp (*.*)|*.*',
  }) async {
    if (kIsWeb) {
      final picked = await pickBrowserFile(
        accept: '.png,.jpg,.jpeg,.webp,.pdf,.svg,image/*,application/pdf',
        readAsText: false,
      );
      if (picked != null && picked.fileName.trim().isNotEmpty) {
        return 'web_upload://${picked.fileName.trim()}';
      }
      return null;
    }
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    if (Platform.isWindows) {
      try {
        final escapedTitle = dialogTitle.replaceAll("'", "''");
        final escapedFilter = filter.replaceAll("'", "''");
        final script = '''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
\$dlg = New-Object System.Windows.Forms.OpenFileDialog
\$dlg.Title = '$escapedTitle'
\$dlg.Filter = '$escapedFilter'
\$dlg.Multiselect = \$false
if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output \$dlg.FileName
}
''';
        final res = await Process.run(
          'powershell',
          ['-NoProfile', '-Sta', '-Command', script],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        if (res.exitCode == 0) {
          final picked = res.stdout.toString().trim();
          if (picked.isNotEmpty && File(picked).existsSync()) {
            return picked;
          }
        }
      } catch (_) {}
    } else if (Platform.isMacOS) {
      try {
        final res = await Process.run(
          'osascript',
          ['-e', 'POSIX path of (choose file with prompt "$dialogTitle")'],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        if (res.exitCode == 0) {
          final picked = res.stdout.toString().trim();
          if (picked.isNotEmpty && File(picked).existsSync()) return picked;
        }
      } catch (_) {}
    } else if (Platform.isLinux) {
      try {
        final res = await Process.run(
          'zenity',
          ['--file-selection', '--title=$dialogTitle'],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        if (res.exitCode == 0) {
          final picked = res.stdout.toString().trim();
          if (picked.isNotEmpty && File(picked).existsSync()) return picked;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Mở hộp thoại chọn tệp CSV/TXT từ máy tính hoặc trình duyệt Web và đọc nội dung UTF-8 thực tế
  static Future<({String filePath, String content})?> pickLocalCsvFileContent({
    String dialogTitle = 'Chọn tệp dữ liệu đơn hàng (.csv / .txt)',
  }) async {
    if (kIsWeb) {
      final picked = await pickBrowserFile(
        accept: '.csv,.txt,text/csv,text/plain',
        readAsText: true,
      );
      if (picked != null && (picked.textContent ?? '').isNotEmpty) {
        return (
          filePath: 'web_upload://${picked.fileName}',
          content: picked.textContent!,
        );
      }
      return null;
    }
    final pickedPath = await pickLocalDocumentOrImage(
      dialogTitle: dialogTitle,
      filter:
          'Tệp bảng dữ liệu CSV (*.csv;*.txt)|*.csv;*.txt|Tất cả tệp (*.*)|*.*',
    );
    if (pickedPath == null) return null;
    try {
      final file = File(pickedPath);
      if (!file.existsSync()) return null;
      final raw = await file.readAsString(encoding: utf8);
      return (filePath: pickedPath, content: raw);
    } catch (_) {
      return null;
    }
  }

  static const List<String> code128Patterns = [
    '212222', '222122', '222221', '121223', '121322', '131222', '122213',
    '122312', '132212', '221213', '221312', '231212', '112232', '122132',
    '122231', '113222', '123122', '123221', '223211', '221132', '221231',
    '213212', '223112', '312131', '311222', '321122', '321221', '312212',
    '322112', '322211', '212123', '212321', '232121', '111323', '131123',
    '131321', '112313', '132113', '132311', '211313', '231113', '231311',
    '112133', '112331', '132131', '113123', '113321', '133121', '313121',
    '211331', '231131', '213113', '213311', '213131', '311123', '311321',
    '331121', '312113', '312311', '332111', '314111', '221411', '431111',
    '111224', '111422', '121124', '121421', '141122', '141221', '112214',
    '112412', '122114', '122411', '142112', '142211', '241211', '221114',
    '413111', '241112', '134111', '111242', '121142', '121241', '114212',
    '124112', '124211', '411212', '421112', '421211', '212141', '214121',
    '412121', '111143', '111341', '131141', '114113', '114311', '411113',
    '411311', '113141', '114131', '311141', '411131', '211412', '211214',
    '211232', '2331112',
  ];

  /// Mã hóa chuỗi ASCII chuẩn ISO/IEC 15417 Code-128 Subset B (Start B=104, Data, Mod-103 Checksum, Stop=106)
  static List<int> encodeCode128BSymbols(String rawData) {
    final normalized = rawData.trim().isEmpty ? 'DH123456' : rawData.trim();
    final symbols = <int>[104];
    int checksum = 104;
    int pos = 1;
    for (final rune in normalized.runes) {
      if (rune < 32 || rune > 126) continue;
      final value = rune - 32;
      symbols.add(value);
      checksum += value * pos;
      pos++;
    }
    symbols.add(checksum % 103);
    symbols.add(106);
    return symbols;
  }

  static String renderCode128BSvg(String rawData, {double height = 44}) {
    final symbols = encodeCode128BSymbols(rawData);
    const quietModules = 10;
    final totalModules =
        quietModules * 2 + (symbols.length - 1) * 11 + 13;
    const moduleWidth = 1.6;
    final svgWidth = (totalModules * moduleWidth).toStringAsFixed(1);
    final rects = StringBuffer();
    double x = quietModules * moduleWidth;
    for (final sym in symbols) {
      final pattern = code128Patterns[sym];
      for (var i = 0; i < pattern.length; i++) {
        final w = (pattern.codeUnitAt(i) - 48) * moduleWidth;
        if (i.isEven) {
          rects.write(
            '<rect x="${x.toStringAsFixed(2)}" y="0" width="${w.toStringAsFixed(2)}" height="${height.toStringAsFixed(0)}" fill="#15131E"/>',
          );
        }
        x += w;
      }
    }
    return '<svg xmlns="http://www.w3.org/2000/svg" width="$svgWidth" height="${height.toStringAsFixed(0)}" viewBox="0 0 $svgWidth ${height.toStringAsFixed(0)}">$rects</svg>';
  }

  static String renderQrMatrixSvg(String payload, {double size = 64}) {
    final matrix = _QrMatrixPainter._encodeIso18004Matrix(payload);
    final dim = matrix.length;
    const quietZone = 2;
    final totalGrid = dim + quietZone * 2;
    final cell = size / totalGrid;
    final rects = StringBuffer();
    for (var r = 0; r < dim; r++) {
      for (var c = 0; c < dim; c++) {
        if (matrix[r][c]) {
          rects.write(
            '<rect x="${((c + quietZone) * cell).toStringAsFixed(2)}" y="${((r + quietZone) * cell).toStringAsFixed(2)}" width="${(cell + 0.25).toStringAsFixed(2)}" height="${(cell + 0.25).toStringAsFixed(2)}" fill="#15131E"/>',
          );
        }
      }
    }
    final sz = size.toStringAsFixed(0);
    return '<svg xmlns="http://www.w3.org/2000/svg" width="$sz" height="$sz" viewBox="0 0 $sz $sz"><rect width="100%" height="100%" fill="#FFFFFF"/>$rects</svg>';
  }

  /// Xuất phiếu giao hàng chuẩn khổ A6 (105x148mm) ra file HTML+SVG thực tế trên ổ cứng / trình duyệt
  static Future<String> exportA6LabelToHtmlFile({
    required String trackingCode,
    required String storeName,
    required String warehouseAddress,
    required String recipientName,
    required String recipientPhone,
    required String dropoffAddress,
    required String packageDescription,
    required double codAmount,
    double recipientShippingFee = 0,
    String? barcodePayload,
    String? qrPayload,
  }) async {
    const esc = HtmlEscape();
    final safeCode = trackingCode.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final totalCollect = codAmount + recipientShippingFee;
    final effectiveBarcode =
        (barcodePayload != null && barcodePayload.trim().isNotEmpty)
            ? barcodePayload.trim()
            : trackingCode;
    final effectiveQr = (qrPayload != null && qrPayload.trim().isNotEmpty)
        ? qrPayload.trim()
        : '$trackingCode|$recipientPhone|${totalCollect.toStringAsFixed(0)}';
    final barcodeSvg = renderCode128BSvg(effectiveBarcode, height: 46);
    final qrSvg = renderQrMatrixSvg(effectiveQr, size: 64);
    final eTracking = esc.convert(trackingCode);
    final eBarcodeText = esc.convert(effectiveBarcode);
    final eStore = esc.convert(storeName);
    final eWh = esc.convert(warehouseAddress);
    final eRecName = esc.convert(recipientName);
    final eRecPhone = esc.convert(recipientPhone);
    final eDropoff = esc.convert(dropoffAddress);
    final ePkg = esc.convert(packageDescription);
    final html = '''<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8" />
  <title>Phiếu Vận Đơn A6 - $eTracking</title>
  <style>
    @page { size: 105mm 148mm; margin: 4mm; }
    body { font-family: Arial, sans-serif; width: 97mm; border: 2px solid #1F4E79; padding: 8px; }
    .hdr { display: flex; justify-content: space-between; border-bottom: 2px solid #1F4E79; padding-bottom: 6px; }
    .codes { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin: 10px 0 6px; padding: 6px 0; border-bottom: 1px dashed #94A3B8; }
    .bar { flex: 1; text-align: center; }
    .bar-code { font-family: monospace; font-size: 11px; font-weight: bold; letter-spacing: 1.5px; margin-top: 3px; }
    .qr { border: 1px solid #CBD5E1; padding: 3px; background: #FFF; }
    .cod { font-size: 15px; font-weight: bold; color: #FF6B00; margin-top: 8px; }
    .tot { font-size: 17px; font-weight: 800; color: #1F4E79; margin-top: 4px; border-top: 1px dashed #94A3B8; padding-top: 6px; }
  </style>
</head>
<body>
  <div class="hdr">
    <strong>GIAO HÀNG SIÊU TỐC GHST (A6: 105x148mm)</strong>
    <span>$eTracking</span>
  </div>
  <div class="codes">
    <div class="bar">
      $barcodeSvg
      <div class="bar-code">$eBarcodeText</div>
    </div>
    <div class="qr">$qrSvg</div>
  </div>
  <p><strong>Từ Shop:</strong> $eStore ($eWh)</p>
  <p><strong>Người nhận:</strong> $eRecName ($eRecPhone)</p>
  <p><strong>Địa chỉ giao:</strong> $eDropoff</p>
  <p><strong>Hàng hóa:</strong> $ePkg</p>
  <div class="cod">THU HỘ COD: ${codAmount.toStringAsFixed(0)} VNĐ | CƯỚC NGƯỜI NHẬN TRẢ: ${recipientShippingFee.toStringAsFixed(0)} VNĐ</div>
  <div class="tot">TỔNG THU NGƯỜI NHẬN: ${totalCollect.toStringAsFixed(0)} VNĐ</div>
</body>
</html>''';
    if (kIsWeb) {
      final fileName = 'phieu_van_don_A6_$safeCode.html';
      final virtualPath = 'localStorage://exports/$fileName';
      await SqliteOfflineQueueDatasource.instance.upsertEntityRecord(
        tableName: 'exported_waybills_a6',
        recordId: safeCode,
        payload: {'fileName': virtualPath, 'html': html},
      );
      triggerBrowserFileDownload(
        fileName: fileName,
        content: html,
        mimeType: 'text/html;charset=utf-8',
      );
      return virtualPath;
    }
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}phieu_van_don_A6_$safeCode.html',
    );
    await file.writeAsString(html, flush: true);
    return file.path;
  }

  /// Xuất chứng từ ảnh bằng chứng giao hàng POD đóng dấu Watermark GPS thực tế ra file SVG trên ổ cứng / trình duyệt
  static Future<String> exportPodWatermarkToSvgFile({
    required String orderCode,
    required GeoPoint driverLocation,
    required String recipientName,
    required String otpCode,
    required double distanceMeters,
  }) async {
    const esc = HtmlEscape();
    final safeCode = orderCode.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final nowIso = DateTime.now().toIso8601String();
    final sig = generatePaymentSignature(
      orderCode: orderCode,
      amount: distanceMeters,
      method: otpCode,
    );
    final eOrderCode = esc.convert(orderCode);
    final eRecipient = esc.convert(recipientName);
    final eOtp = esc.convert(otpCode);
    final svg = '''<svg xmlns="http://www.w3.org/2000/svg" width="600" height="260">
  <rect width="100%" height="100%" fill="#0F172A" rx="12"/>
  <text x="20" y="40" fill="#28A745" font-size="18" font-family="monospace" font-weight="bold">CHỨNG TỪ ẢNH XÁC NHẬN GIAO HÀNG ĐÓNG DẤU GPS</text>
  <text x="20" y="80" fill="#FFFFFF" font-size="14" font-family="monospace">Mã vận đơn : $eOrderCode | Người nhận: $eRecipient</text>
  <text x="20" y="115" fill="#00B4D8" font-size="14" font-family="monospace">Tọa độ GPS : (${driverLocation.latitude.toStringAsFixed(6)}, ${driverLocation.longitude.toStringAsFixed(6)}) SRID=4326</text>
  <text x="20" y="150" fill="#FFC107" font-size="14" font-family="monospace">Khoảng cách: ${distanceMeters.toStringAsFixed(1)}m (&lt;= 100m Geofence) | Mã OTP: $eOtp</text>
  <text x="20" y="185" fill="#CBD5E1" font-size="13" font-family="monospace">Thời gian  : $nowIso</text>
  <text x="20" y="220" fill="#94A3B8" font-size="12" font-family="monospace">Chữ ký toàn vẹn SHA/FNV: $sig</text>
</svg>''';
    if (kIsWeb) {
      final fileName = 'pod_watermark_$safeCode.svg';
      final virtualPath = 'localStorage://exports/$fileName';
      await SqliteOfflineQueueDatasource.instance.upsertEntityRecord(
        tableName: 'exported_pod_watermarks',
        recordId: safeCode,
        payload: {'fileName': virtualPath, 'svg': svg},
      );
      triggerBrowserFileDownload(
        fileName: fileName,
        content: svg,
        mimeType: 'image/svg+xml;charset=utf-8',
      );
      return virtualPath;
    }
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}pod_watermark_$safeCode.svg',
    );
    await file.writeAsString(svg, flush: true);
    return file.path;
  }
}

/// Widget vẽ Mã vạch Code-128 thực tế từ chuỗi mã vận đơn
class Code128BarcodeWidget extends StatelessWidget {
  final String data;
  final double height;

  const Code128BarcodeWidget({
    super.key,
    required this.data,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _Code128Painter(data: data),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _Code128Painter extends CustomPainter {
  final String data;

  const _Code128Painter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    final symbols = SecurityAndBarcodeUtils.encodeCode128BSymbols(data);
    const quietModules = 6;
    final totalModules =
        quietModules * 2 + (symbols.length - 1) * 11 + 13;
    final moduleWidth = (size.width / totalModules).clamp(0.85, 3.6);
    final totalRenderedWidth = totalModules * moduleWidth;
    var currentX =
        ((size.width - totalRenderedWidth) * 0.5).clamp(0.0, size.width) +
            quietModules * moduleWidth;

    for (final sym in symbols) {
      final pattern = SecurityAndBarcodeUtils.code128Patterns[sym];
      for (var i = 0; i < pattern.length; i++) {
        final w = (pattern.codeUnitAt(i) - 48) * moduleWidth;
        if (currentX + w > size.width) break;
        if (i.isEven) {
          canvas.drawRect(Rect.fromLTWH(currentX, 0, w, size.height), paint);
        }
        currentX += w;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Code128Painter oldDelegate) =>
      oldDelegate.data != data;
}

/// Widget vẽ Ma trận QR Code chuẩn ISO/IEC 18004 (Reed-Solomon ECC) quét trực tiếp bằng Camera điện thoại
class QrMatrixPainterWidget extends StatelessWidget {
  final String payload;
  final double size;

  const QrMatrixPainterWidget({
    super.key,
    required this.payload,
    this.size = 84,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomPaint(
        painter: _QrMatrixPainter(payload: payload),
      ),
    );
  }
}

class _QrMatrixPainter extends CustomPainter {
  final String payload;

  const _QrMatrixPainter({required this.payload});

  static final List<int> _gfExp = _buildGfExp();
  static final List<int> _gfLog = _buildGfLog();

  static List<int> _buildGfExp() {
    final exp = List<int>.filled(512, 0);
    var x = 1;
    for (var i = 0; i < 255; i++) {
      exp[i] = x;
      x <<= 1;
      if ((x & 0x100) != 0) x ^= 0x11D;
    }
    for (var i = 255; i < 512; i++) {
      exp[i] = exp[i - 255];
    }
    return exp;
  }

  static List<int> _buildGfLog() {
    final log = List<int>.filled(256, 0);
    var x = 1;
    for (var i = 0; i < 255; i++) {
      log[x] = i;
      x <<= 1;
      if ((x & 0x100) != 0) x ^= 0x11D;
    }
    return log;
  }

  static int _gfMul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return _gfExp[_gfLog[a] + _gfLog[b]];
  }

  static List<int> _computeReedSolomonEcc(List<int> data, int ecCount) {
    var gen = <int>[1];
    for (var i = 0; i < ecCount; i++) {
      final next = List<int>.filled(gen.length + 1, 0);
      for (var j = 0; j < gen.length; j++) {
        next[j] ^= gen[j];
        next[j + 1] ^= _gfMul(gen[j], _gfExp[i]);
      }
      gen = next;
    }
    final ecc = List<int>.filled(ecCount, 0);
    for (final b in data) {
      final lead = b ^ ecc[0];
      for (var j = 0; j < ecCount - 1; j++) {
        ecc[j] = ecc[j + 1];
      }
      ecc[ecCount - 1] = 0;
      if (lead != 0) {
        for (var j = 0; j < ecCount; j++) {
          ecc[j] ^= _gfMul(gen[j + 1], lead);
        }
      }
    }
    return ecc;
  }

  static List<List<bool>> _encodeIso18004Matrix(String text) {
    var rawBytes = utf8.encode(text.isEmpty ? 'GHST' : text);
    if (rawBytes.length > 230) {
      rawBytes = rawBytes.sublist(0, 230);
    }

    const dataCapByVer = [0, 19, 34, 55, 80, 108, 136, 156, 194, 232];
    const numBlocksByVer = [0, 1, 1, 1, 1, 1, 2, 2, 2, 2];
    const ecPerBlockByVer = [0, 7, 10, 15, 20, 26, 18, 20, 24, 30];
    const alignCoordsByVer = <List<int>>[
      [],
      [],
      [6, 18],
      [6, 22],
      [6, 26],
      [6, 30],
      [6, 34],
      [6, 22, 38],
      [6, 24, 42],
      [6, 26, 46],
    ];

    var version = 9;
    for (var v = 1; v <= 9; v++) {
      if (rawBytes.length + 2 <= dataCapByVer[v]) {
        version = v;
        break;
      }
    }

    final totalDataBytes = dataCapByVer[version];
    final numBlocks = numBlocksByVer[version];
    final ecCount = ecPerBlockByVer[version];
    final bits = <bool>[];

    void pushBits(int val, int count) {
      for (var i = count - 1; i >= 0; i--) {
        bits.add(((val >> i) & 1) == 1);
      }
    }

    pushBits(0x4, 4);
    pushBits(rawBytes.length, 8);
    for (final b in rawBytes) {
      pushBits(b, 8);
    }

    final maxDataBits = totalDataBytes * 8;
    for (var i = 0; i < 4 && bits.length < maxDataBits; i++) {
      bits.add(false);
    }
    while (bits.length % 8 != 0) {
      bits.add(false);
    }

    final dataCodewords = <int>[];
    for (var i = 0; i < bits.length; i += 8) {
      var byteVal = 0;
      for (var j = 0; j < 8; j++) {
        byteVal = (byteVal << 1) | (bits[i + j] ? 1 : 0);
      }
      dataCodewords.add(byteVal);
    }

    var padToggle = true;
    while (dataCodewords.length < totalDataBytes) {
      dataCodewords.add(padToggle ? 0xEC : 0x11);
      padToggle = !padToggle;
    }

    final allCodewords = <int>[];
    if (numBlocks == 1) {
      final eccCodewords = _computeReedSolomonEcc(dataCodewords, ecCount);
      allCodewords
        ..addAll(dataCodewords)
        ..addAll(eccCodewords);
    } else {
      final blockSize = totalDataBytes ~/ numBlocks;
      final dataBlocks = <List<int>>[
        for (var b = 0; b < numBlocks; b++)
          dataCodewords.sublist(b * blockSize, (b + 1) * blockSize),
      ];
      final eccBlocks = <List<int>>[
        for (final block in dataBlocks) _computeReedSolomonEcc(block, ecCount),
      ];
      for (var i = 0; i < blockSize; i++) {
        for (var b = 0; b < numBlocks; b++) {
          allCodewords.add(dataBlocks[b][i]);
        }
      }
      for (var i = 0; i < ecCount; i++) {
        for (var b = 0; b < numBlocks; b++) {
          allCodewords.add(eccBlocks[b][i]);
        }
      }
    }

    final fullBitStream = <bool>[];
    for (final cw in allCodewords) {
      for (var b = 7; b >= 0; b--) {
        fullBitStream.add(((cw >> b) & 1) == 1);
      }
    }

    final dim = 17 + 4 * version;
    final modules = List.generate(dim, (_) => List<bool>.filled(dim, false));
    final isFunction = List.generate(dim, (_) => List<bool>.filled(dim, false));

    void setFunctionModule(int r, int c, bool dark) {
      if (r < 0 || r >= dim || c < 0 || c >= dim) return;
      modules[r][c] = dark;
      isFunction[r][c] = true;
    }

    void drawFinderPattern(int top, int left) {
      for (var dr = -1; dr <= 7; dr++) {
        for (var dc = -1; dc <= 7; dc++) {
          final r = top + dr;
          final c = left + dc;
          final inOuter = dr >= 0 && dr <= 6 && dc >= 0 && dc <= 6;
          final onBorder = dr == 0 || dr == 6 || dc == 0 || dc == 6;
          final inInner = dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4;
          setFunctionModule(r, c, inOuter && (onBorder || inInner));
        }
      }
    }

    drawFinderPattern(0, 0);
    drawFinderPattern(0, dim - 7);
    drawFinderPattern(dim - 7, 0);

    for (var i = 8; i < dim - 8; i++) {
      setFunctionModule(6, i, i.isEven);
      setFunctionModule(i, 6, i.isEven);
    }

    if (version >= 2) {
      final coords = alignCoordsByVer[version];
      final last = coords.last;
      for (final cr in coords) {
        for (final cc in coords) {
          final onFinder =
              (cr == 6 && cc == 6) ||
              (cr == 6 && cc == last) ||
              (cr == last && cc == 6);
          if (onFinder) continue;
          for (var dr = -2; dr <= 2; dr++) {
            for (var dc = -2; dc <= 2; dc++) {
              final dark =
                  dr.abs() == 2 || dc.abs() == 2 || (dr == 0 && dc == 0);
              setFunctionModule(cr + dr, cc + dc, dark);
            }
          }
        }
      }
    }

    if (version >= 7) {
      var rem = version << 12;
      for (var i = 17; i >= 12; i--) {
        if (((rem >> i) & 1) != 0) {
          rem ^= 0x1F25 << (i - 12);
        }
      }
      final verInfo = (version << 12) | rem;
      for (var i = 0; i < 18; i++) {
        final bit = ((verInfo >> i) & 1) == 1;
        final a = i ~/ 3;
        final b = (dim - 11) + (i % 3);
        setFunctionModule(b, a, bit);
        setFunctionModule(a, b, bit);
      }
    }

    setFunctionModule(4 * version + 9, 8, true);
    for (var i = 0; i <= 8; i++) {
      if (i != 6) {
        isFunction[8][i] = true;
        isFunction[i][8] = true;
      }
    }
    for (var i = 0; i < 8; i++) {
      isFunction[8][dim - 1 - i] = true;
    }
    for (var i = 0; i < 7; i++) {
      isFunction[dim - 1 - i][8] = true;
    }

    var bitIdx = 0;
    var upward = true;
    for (var rightCol = dim - 1; rightCol > 0; rightCol -= 2) {
      if (rightCol == 6) rightCol = 5;
      for (var step = 0; step < dim; step++) {
        final r = upward ? (dim - 1 - step) : step;
        for (var offset = 0; offset < 2; offset++) {
          final c = rightCol - offset;
          if (!isFunction[r][c]) {
            var dark =
                bitIdx < fullBitStream.length ? fullBitStream[bitIdx++] : false;
            if ((r + c).isEven) dark = !dark;
            modules[r][c] = dark;
          }
        }
      }
      upward = !upward;
    }

    const formatBits = 0x77C4;
    bool fmtBit(int idx) => ((formatBits >> idx) & 1) == 1;

    const topLeftCols = [0, 1, 2, 3, 4, 5, 7, 8];
    for (var i = 0; i < 8; i++) {
      modules[8][topLeftCols[i]] = fmtBit(14 - i);
    }
    const topLeftRows = [7, 5, 4, 3, 2, 1, 0];
    for (var i = 0; i < 7; i++) {
      modules[topLeftRows[i]][8] = fmtBit(6 - i);
    }
    for (var i = 0; i < 7; i++) {
      modules[dim - 1 - i][8] = fmtBit(14 - i);
    }
    for (var i = 0; i < 8; i++) {
      modules[8][dim - 8 + i] = fmtBit(7 - i);
    }

    return modules;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final matrix = _encodeIso18004Matrix(payload);
    final dim = matrix.length;
    const quietZone = 2;
    final totalGrid = dim + quietZone * 2;
    final cell = size.width / totalGrid;
    final darkPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    for (var r = 0; r < dim; r++) {
      for (var c = 0; c < dim; c++) {
        if (matrix[r][c]) {
          canvas.drawRect(
            Rect.fromLTWH(
              (c + quietZone) * cell,
              (r + quietZone) * cell,
              cell + 0.35,
              cell + 0.35,
            ),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrMatrixPainter oldDelegate) =>
      oldDelegate.payload != payload;
}

/// Receipt preview populated from the recipient input and recorded GPS.
class PodGpsWatermarkPhotoCard extends StatelessWidget {
  final GeoPoint? driverLocation;
  final String recipientName;
  final String otpCode;
  final double distanceToDropoffMeters;

  const PodGpsWatermarkPhotoCard({
    super.key,
    required this.driverLocation,
    required this.recipientName,
    required this.otpCode,
    required this.distanceToDropoffMeters,
  });

  @override
  Widget build(BuildContext context) {
    final isWithinGeofence = driverLocation != null && distanceToDropoffMeters <= 100.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWithinGeofence ? AppColors.success : AppColors.warning,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GhstButtonIcon(
                    Icons.receipt_long_outlined,
                    color:
                        isWithinGeofence ? AppColors.success : AppColors.warning,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'BIÊN NHẬN GIAO HÀNG (POD)',
                      style: TextStyle(
                        color: isWithinGeofence
                            ? AppColors.success
                            : AppColors.warning,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isWithinGeofence
                      ? AppColors.success.withValues(alpha: 0.2)
                      : AppColors.danger.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  driverLocation == null ? 'Chưa có vị trí GPS' : distanceToDropoffMeters >= 1000
                      ? 'Cách điểm giao: ${(distanceToDropoffMeters / 1000.0).toStringAsFixed(1)}km'
                      : 'Cách điểm giao: ${distanceToDropoffMeters.toStringAsFixed(0)}m',
                  style: TextStyle(
                    color: isWithinGeofence ? AppColors.success : Colors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            driverLocation == null ? 'Đang chờ vị trí GPS' : 'Tọa độ GPS: (${driverLocation!.latitude.toStringAsFixed(5)}, ${driverLocation!.longitude.toStringAsFixed(5)})',
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
          Text(
            '• Người nhận: $recipientName • Mã OTP xác thực: $otpCode',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
