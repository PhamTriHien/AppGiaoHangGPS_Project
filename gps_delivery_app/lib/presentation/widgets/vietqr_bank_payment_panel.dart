import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config/env_config.dart';
import '../../core/integrations/bank_directory_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/security_and_barcode_utils.dart';

class VietQrBankPaymentPanel extends StatefulWidget {
  const VietQrBankPaymentPanel({
    super.key,
    required this.amountVnd,
    required this.orderReference,
    this.providerQrPayload,
    this.beneficiaryBankBin = '970436',
    this.beneficiaryBankShortName = 'Vietcombank',
    this.beneficiaryAccountNumber = '0071000889',
    this.beneficiaryAccountName = 'GHST EXPRESS',
    this.reconciliationNote,
    this.selectedPayerBankBin,
    this.onPayerBankChanged,
    this.compact = false,
  });

  final double amountVnd;
  final String orderReference;
  final String? providerQrPayload;
  final String beneficiaryBankBin;
  final String beneficiaryBankShortName;
  final String beneficiaryAccountNumber;
  final String beneficiaryAccountName;
  final String? reconciliationNote;
  final String? selectedPayerBankBin;
  final ValueChanged<DirectoryBank>? onPayerBankChanged;
  final bool compact;

  static const List<DirectoryBank> defaultVietnamBanks = [
    DirectoryBank(
      name: 'Ngân hàng TMCP Ngoại thương Việt Nam',
      shortName: 'Vietcombank',
      code: 'VCB',
      bin: '970436',
    ),
    DirectoryBank(
      name: 'Ngân hàng TMCP Quân đội',
      shortName: 'MBBank',
      code: 'MB',
      bin: '970422',
    ),
    DirectoryBank(
      name: 'Ngân hàng TMCP Kỹ thương Việt Nam',
      shortName: 'Techcombank',
      code: 'TCB',
      bin: '970407',
    ),
    DirectoryBank(
      name: 'Ngân hàng TMCP Công thương Việt Nam',
      shortName: 'VietinBank',
      code: 'ICB',
      bin: '970415',
    ),
    DirectoryBank(
      name: 'Ngân hàng TMCP Đầu tư và Phát triển Việt Nam',
      shortName: 'BIDV',
      code: 'BIDV',
      bin: '970418',
    ),
    DirectoryBank(
      name: 'Ngân hàng TMCP Á Châu',
      shortName: 'ACB',
      code: 'ACB',
      bin: '970416',
    ),
    DirectoryBank(
      name: 'Ngân hàng TMCP Việt Nam Thịnh Vượng',
      shortName: 'VPBank',
      code: 'VPB',
      bin: '970432',
    ),
    DirectoryBank(
      name: 'Ngân hàng TMCP Tiên Phong',
      shortName: 'TPBank',
      code: 'TPB',
      bin: '970423',
    ),
    DirectoryBank(
      name: 'Ngân hàng TMCP Sài Gòn Thương Tín',
      shortName: 'Sacombank',
      code: 'STB',
      bin: '970403',
    ),
    DirectoryBank(
      name: 'Ngân hàng Nông nghiệp và Phát triển Nông thôn Việt Nam',
      shortName: 'Agribank',
      code: 'VBA',
      bin: '970405',
    ),
  ];

  static String buildTransferMemo(String rawReference) {
    final cleaned = rawReference
        .replaceAll('#', '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '')
        .toUpperCase();
    if (cleaned.isEmpty) return 'GHST ORDER';
    final shortRef = cleaned.length > 18 ? cleaned.substring(0, 18) : cleaned;
    return 'GHST $shortRef';
  }

  @override
  State<VietQrBankPaymentPanel> createState() => _VietQrBankPaymentPanelState();
}

class _VietQrBankPaymentPanelState extends State<VietQrBankPaymentPanel> {
  List<DirectoryBank> _banks = VietQrBankPaymentPanel.defaultVietnamBanks;
  late String _payerBin =
      widget.selectedPayerBankBin ??
      VietQrBankPaymentPanel.defaultVietnamBanks.first.bin;
  String? _copiedNotice;

  @override
  void initState() {
    super.initState();
    if (EnvConfig.deliveryApiBaseUrl.isNotEmpty) {
      unawaited(_loadLiveDirectory());
    }
  }

  @override
  void didUpdateWidget(covariant VietQrBankPaymentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedPayerBankBin != null &&
        widget.selectedPayerBankBin != oldWidget.selectedPayerBankBin) {
      _payerBin = widget.selectedPayerBankBin!;
    }
  }

  Future<void> _loadLiveDirectory() async {
    try {
      final loaded = await BankDirectoryService.instance.load();
      if (!mounted || loaded.isEmpty) return;
      final merged = <String, DirectoryBank>{
        for (final b in VietQrBankPaymentPanel.defaultVietnamBanks) b.bin: b,
        for (final b in loaded) b.bin: b,
      };
      final sorted = merged.values.toList()
        ..sort((a, b) => a.shortName.compareTo(b.shortName));
      setState(() {
        _banks = sorted;
        if (!_banks.any((b) => b.bin == _payerBin)) {
          _payerBin = _banks.first.bin;
        }
      });
    } catch (_) {}
  }

  void _copyValue(String value, String label) {
    unawaited(
      Clipboard.setData(
        ClipboardData(text: value),
      ).catchError((Object _) {}),
    );
    if (!mounted) return;
    setState(() => _copiedNotice = 'Đã sao chép $label');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeAmount = widget.amountVnd.isFinite && widget.amountVnd > 0
        ? widget.amountVnd
        : 0.0;
    final amountRounded = safeAmount.round();
    final formattedAmount = CurrencyFormatter.formatVnd(safeAmount);
    final memo = VietQrBankPaymentPanel.buildTransferMemo(
      widget.orderReference,
    );
    final providerQr = widget.providerQrPayload?.trim() ?? '';
    final effectiveQrPayload = providerQr.isNotEmpty
        ? providerQr
        : SecurityAndBarcodeUtils.generateEmvVietQrPayload(
            orderCode: memo,
            amountVnd: safeAmount,
            bankBin: widget.beneficiaryBankBin,
            accountNumber: widget.beneficiaryAccountNumber,
          );
    final effectiveBin = _banks.any((b) => b.bin == _payerBin)
        ? _payerBin
        : _banks.first.bin;
    final selectedBank = _banks.firstWhere(
      (b) => b.bin == effectiveBin,
      orElse: () => _banks.first,
    );

    final qrBox = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.ink, width: 1.2),
        boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(3, 3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrMatrixPainterWidget(
            key: const ValueKey('vietqr-matrix-widget'),
            payload: effectiveQrPayload,
            size: widget.compact ? 132 : 152,
          ),
          const SizedBox(height: 6),
          Text(
            providerQr.isNotEmpty
                ? 'Mã QR đối soát tự động · NAPAS 247'
                : 'Mã VietQR chuyển khoản · NAPAS 247',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );

    final detailsColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('vietqr-bank-$effectiveBin-${_banks.length}'),
          initialValue: effectiveBin,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Ngân hàng thanh toán của bạn',
            border: OutlineInputBorder(),
          ),
          items: _banks
              .map(
                (b) => DropdownMenuItem<String>(
                  value: b.bin,
                  child: Text(
                    '${b.shortName} · ${b.code}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (val) {
            if (val == null) return;
            final picked = _banks.firstWhere(
              (b) => b.bin == val,
              orElse: () => _banks.first,
            );
            setState(() => _payerBin = val);
            widget.onPayerBankChanged?.call(picked);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Quét mã bằng ứng dụng ${selectedBank.shortName} hoặc chuyển khoản nhanh 24/7:',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _infoRow(
          label: 'Ngân hàng thụ hưởng',
          value:
              '${widget.beneficiaryBankShortName} · BIN ${widget.beneficiaryBankBin}',
        ),
        _infoRow(
          label: 'Chủ tài khoản',
          value: widget.beneficiaryAccountName,
        ),
        _infoRow(
          label: 'Số tài khoản',
          value: widget.beneficiaryAccountNumber,
          copyTooltip: 'Sao chép số tài khoản',
          onCopy: () =>
              _copyValue(widget.beneficiaryAccountNumber, 'số tài khoản'),
        ),
        _infoRow(
          label: 'Số tiền chuyển',
          value: formattedAmount,
          bold: true,
          copyTooltip: 'Sao chép số tiền',
          onCopy: () => _copyValue('$amountRounded', 'số tiền'),
        ),
        _infoRow(
          label: 'Nội dung chuyển khoản',
          value: memo,
          bold: true,
          copyTooltip: 'Sao chép nội dung chuyển khoản',
          onCopy: () => _copyValue(memo, 'nội dung chuyển khoản'),
        ),
        if (_copiedNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _copiedNotice!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF047857),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border.all(color: AppColors.ink, width: 1.5),
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.qr_code_2_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Chuyển khoản ngân hàng & Quét mã VietQR',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 420) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    qrBox,
                    const SizedBox(width: 14),
                    Expanded(child: detailsColumn),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: qrBox),
                  const SizedBox(height: 12),
                  detailsColumn,
                ],
              );
            },
          ),
          if (widget.reconciliationNote != null &&
              widget.reconciliationNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.reconciliationNote!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF475569),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow({
    required String label,
    required String value,
    bool bold = false,
    String? copyTooltip,
    VoidCallback? onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: const Color(0xFF0F172A),
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              tooltip: copyTooltip,
              onPressed: onCopy,
              icon: const Icon(
                Icons.copy_outlined,
                size: 16,
                color: Color(0xFF2563EB),
              ),
            ),
        ],
      ),
    );
  }
}
