import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import 'cloud_membership_panel.dart';
import 'theme_mode_toggle.dart';
import 'ghst_button_icon.dart';

const cloudAccountRoles = {
  'customer': 'Khách hàng',
  'merchant': 'Cửa hàng',
  'driver': 'Tài xế',
};

String formatIsoBirthDate(String? iso) {
  final raw = iso?.trim() ?? '';
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (match == null) return '';
  return '${match.group(3)}/${match.group(2)}/${match.group(1)}';
}

String? parseBirthDateToIso(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  int? y;
  int? m;
  int? d;
  final isoMatch = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(value);
  final vnMatch = RegExp(
    r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$',
  ).firstMatch(value);
  final compactMatch = RegExp(r'^(\d{2})(\d{2})(\d{4})$').firstMatch(value);
  if (isoMatch != null) {
    y = int.tryParse(isoMatch.group(1)!);
    m = int.tryParse(isoMatch.group(2)!);
    d = int.tryParse(isoMatch.group(3)!);
  } else if (vnMatch != null) {
    d = int.tryParse(vnMatch.group(1)!);
    m = int.tryParse(vnMatch.group(2)!);
    y = int.tryParse(vnMatch.group(3)!);
  } else if (compactMatch != null) {
    d = int.tryParse(compactMatch.group(1)!);
    m = int.tryParse(compactMatch.group(2)!);
    y = int.tryParse(compactMatch.group(3)!);
  } else {
    return null;
  }
  if (y == null || m == null || d == null) return null;
  final parsed = DateTime.utc(y, m, d);
  if (parsed.year != y || parsed.month != m || parsed.day != d) return null;
  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  if (parsed.isBefore(DateTime.utc(1900, 1, 1)) || parsed.isAfter(today)) {
    return null;
  }
  final mm = m.toString().padLeft(2, '0');
  final dd = d.toString().padLeft(2, '0');
  return '$y-$mm-$dd';
}

class BirthDateSlashFormatter extends TextInputFormatter {
  const BirthDateSlashFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    if (raw.isEmpty) return TextEditingValue.empty;

    final isoPaste = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(
      raw.trim(),
    );
    if (isoPaste != null) {
      final converted =
          '${isoPaste.group(3)}/${isoPaste.group(2)}/${isoPaste.group(1)}';
      return TextEditingValue(
        text: converted,
        selection: TextSelection.collapsed(offset: converted.length),
      );
    }

    final isDeleting = raw.length < oldValue.text.length;

    if (!isDeleting && (raw.endsWith('/') || raw.endsWith('-'))) {
      final dayPad = RegExp(r'^([1-9])[/-]$').firstMatch(raw);
      if (dayPad != null) {
        final padded = '0${dayPad.group(1)}/';
        return TextEditingValue(
          text: padded,
          selection: TextSelection.collapsed(offset: padded.length),
        );
      }
      final monthPad = RegExp(r'^(\d{2})/([1-9])[/-]$').firstMatch(raw);
      if (monthPad != null) {
        final padded = '${monthPad.group(1)}/0${monthPad.group(2)}/';
        return TextEditingValue(
          text: padded,
          selection: TextSelection.collapsed(offset: padded.length),
        );
      }
    }

    final allDigits = raw.replaceAll(RegExp(r'\D'), '');
    if (allDigits.isEmpty) return TextEditingValue.empty;
    final digits = allDigits.length > 8 ? allDigits.substring(0, 8) : allDigits;

    final String formatted;
    if (digits.length < 2) {
      formatted = digits;
    } else if (digits.length == 2) {
      formatted = isDeleting ? digits : '$digits/';
    } else if (digits.length == 3) {
      formatted = '${digits.substring(0, 2)}/${digits.substring(2)}';
    } else if (digits.length == 4) {
      final base = '${digits.substring(0, 2)}/${digits.substring(2, 4)}';
      formatted = isDeleting ? base : '$base/';
    } else {
      formatted =
          '${digits.substring(0, 2)}/${digits.substring(2, 4)}/${digits.substring(4)}';
    }

    final rawCursor = newValue.selection.end.clamp(0, raw.length);
    final digitsBeforeCursor = raw
        .substring(0, rawCursor)
        .replaceAll(RegExp(r'\D'), '')
        .length
        .clamp(0, digits.length);

    int cursorOffset = 0;
    if (digitsBeforeCursor > 0) {
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        final code = formatted.codeUnitAt(i);
        if (code >= 48 && code <= 57) {
          seen++;
          if (seen == digitsBeforeCursor) {
            cursorOffset = i + 1;
            break;
          }
        }
      }
      if (!isDeleting &&
          digitsBeforeCursor == digits.length &&
          cursorOffset < formatted.length &&
          formatted[cursorOffset] == '/') {
        cursorOffset++;
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }
}

String maskCitizenId(String? citizenId) {
  final raw = citizenId?.trim() ?? '';
  if (!RegExp(r'^\d{12}$').hasMatch(raw)) return '';
  return '••••••••${raw.substring(8)}';
}

/// Edits only server-supported fields; approved roles remain server-owned.
class CloudProfileForm extends StatefulWidget {
  const CloudProfileForm({
    super.key,
    required this.session,
    this.lease,
    this.onSaved,
    this.onCancel,
  });

  final CloudAccountSession session;
  final CloudSessionLease? lease;
  final VoidCallback? onSaved, onCancel;

  @override
  State<CloudProfileForm> createState() => _CloudProfileFormState();
}

class _CloudProfileFormState extends State<CloudProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: _initialName(),
  );
  late final _phone = TextEditingController(
    text: widget.session.account?['phone'] as String? ?? '',
  );
  late final _birthDate = TextEditingController(
    text: formatIsoBirthDate(
      widget.session.account?['birth_date'] as String?,
    ),
  );
  late final _citizenId = TextEditingController(
    text: widget.session.account?['citizen_id'] as String? ?? '',
  );
  late final _identity = widget.session.service.identityScope;
  late String _requested = _initialRole();
  bool _busy = false, _invalidated = false, _revealCitizenId = false;
  String? _error, _notice;

  String _initialName() {
    final saved =
        (widget.session.account?['full_name'] as String?)?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    try {
      final metadata = Supabase.instance.client.auth.currentUser?.userMetadata;
      final candidate =
          (metadata?['full_name'] ?? metadata?['name'])?.toString().trim() ??
          '';
      return candidate.length <= 120 ? candidate : candidate.substring(0, 120);
    } catch (_) {
      return '';
    }
  }

  String _initialRole() {
    if (widget.session.schemaVersion >= 3) return 'customer';
    final account = widget.session.account;
    final role = account?['requested_role'] ?? account?['role'];
    return cloudAccountRoles.containsKey(role) ? role as String : 'customer';
  }

  bool get _allowed =>
      !_invalidated &&
      widget.session.verified &&
      widget.session.service.identityScope == _identity &&
      widget.session.account?['blocked'] != true &&
      (widget.lease?.valid ?? true);

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (!_allowed) {
      _invalidated = true;
      _name.clear();
      _phone.clear();
      _birthDate.clear();
      _citizenId.clear();
      _revealCitizenId = false;
      _requested = 'customer';
      _error = null;
      _notice = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    _name.dispose();
    _phone.dispose();
    _birthDate.dispose();
    _citizenId.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    if (_busy || !_allowed) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime initial = DateTime(2000, 1, 1);
    final currentIso = parseBirthDateToIso(_birthDate.text);
    if (currentIso != null && currentIso.isNotEmpty) {
      final parts = currentIso.split('-').map(int.parse).toList();
      initial = DateTime(parts[0], parts[1], parts[2]);
    }
    if (initial.isAfter(today)) initial = today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900, 1, 1),
      lastDate: today,
      helpText: 'Chọn ngày tháng năm sinh',
      cancelText: 'Hủy',
      confirmText: 'Chọn',
    );
    if (picked == null || !mounted || !_allowed) return;
    final dd = picked.day.toString().padLeft(2, '0');
    final mm = picked.month.toString().padLeft(2, '0');
    setState(() {
      _birthDate.text = '$dd/$mm/${picked.year}';
    });
  }

  Future<void> _save() async {
    if (_busy || !_allowed || !_form.currentState!.validate()) return;
    final isoBirth = parseBirthDateToIso(_birthDate.text);
    if (isoBirth == null) return;
    final rawCitizen = _citizenId.text.trim();
    final hadBirthDate =
        (widget.session.account?['birth_date'] as String?)?.isNotEmpty == true;
    final hadCitizenId =
        (widget.session.account?['citizen_id'] as String?)?.isNotEmpty == true;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.session.saveProfile(
        fullName: _name.text,
        phone: _phone.text,
        requestedRole: _requested,
        birthDate: isoBirth.isNotEmpty || hadBirthDate ? isoBirth : null,
        citizenId: rawCitizen.isNotEmpty || hadCitizenId ? rawCitizen : null,
      );
      if (mounted && _allowed) {
        setState(() => _notice = 'Đã lưu hồ sơ.');
        widget.onSaved?.call();
      }
    } catch (error) {
      if (mounted && _allowed) {
        setState(
          () => _error = error is PublicApiException
              ? error.message
              : 'Không lưu được hồ sơ. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const Text('Phiên làm việc đã thay đổi. Vui lòng mở lại hồ sơ.');
    }
    final tokens = GhstThemeTokens.of(context);
    final account = widget.session.account;
    final verifiedKyc = widget.session.identityVerified;
    final kycTone = verifiedKyc ? tokens.emerald : tokens.amber;
    final formBox = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Thông tin tài khoản',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(widget.session.service.email),
            if (account != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: kycTone.fill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kycTone.border),
                ),
                child: Row(
                  children: [
                    GhstButtonIcon(
                      verifiedKyc
                          ? Icons.verified_user_outlined
                          : Icons.badge_outlined,
                      size: 18,
                      color: kycTone.icon,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        verifiedKyc
                            ? 'Đã định danh CCCD · Hồ sơ cá nhân đã xác thực'
                            : 'Bổ sung ngày tháng năm sinh và CCCD 12 số để hoàn tất định danh cá nhân',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: kycTone.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const ThemeModeSelectorCard(),
            ],
            if (account != null && widget.session.schemaVersion < 3)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Vai trò: ${cloudAccountRoles[account['role']]}'),
              ),
            if (account?['requested_role'] != null &&
                widget.session.schemaVersion < 3)
              Text(
                'Chờ duyệt vai trò ${cloudAccountRoles[account!['requested_role']]}',
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              enabled: !_busy,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Họ và tên',
                counterText: '',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value == null ||
                      value.trim().isEmpty ||
                      value.trim().length > 120
                  ? 'Họ tên từ 1 đến 120 ký tự.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              enabled: !_busy,
              maxLength: 10,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại',
                counterText: '',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  RegExp(r'^0[35789][0-9]{8}$').hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Số điện thoại Việt Nam không hợp lệ.',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _birthDate,
              enabled: !_busy,
              maxLength: 10,
              keyboardType: TextInputType.number,
              inputFormatters: const [BirthDateSlashFormatter()],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Ngày tháng năm sinh',
                hintText: 'dd/MM/yyyy',
                counterText: '',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_birthDate.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Xóa ngày sinh',
                        icon: const GhstButtonIcon(Icons.close, size: 18),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _birthDate.clear()),
                      ),
                    IconButton(
                      tooltip: 'Chọn ngày sinh',
                      icon: const GhstButtonIcon(Icons.calendar_month_outlined),
                      onPressed: _busy ? null : _pickBirthDate,
                    ),
                  ],
                ),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return null;
                return parseBirthDateToIso(text) == null
                    ? 'Ngày sinh không hợp lệ, nhập theo ngày/tháng/năm.'
                    : null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _citizenId,
              enabled: !_busy,
              maxLength: 12,
              keyboardType: TextInputType.number,
              obscureText: !_revealCitizenId && _citizenId.text.isNotEmpty,
              obscuringCharacter: '•',
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Số CCCD định danh',
                hintText: 'Nhập 12 chữ số căn cước công dân',
                counterText: '',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_citizenId.text.isNotEmpty)
                      IconButton(
                        tooltip: _revealCitizenId ? 'Ẩn CCCD' : 'Hiện CCCD',
                        icon: GhstButtonIcon(
                          _revealCitizenId
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _revealCitizenId = !_revealCitizenId,
                              ),
                      ),
                    if (_citizenId.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Xóa CCCD',
                        icon: const GhstButtonIcon(Icons.close, size: 18),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _citizenId.clear()),
                      ),
                  ],
                ),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return null;
                return RegExp(r'^\d{12}$').hasMatch(text)
                    ? null
                    : 'Số CCCD định danh phải gồm đúng 12 chữ số.';
              },
            ),
            const SizedBox(height: 14),
            if (widget.session.schemaVersion < 3)
              DropdownButtonFormField<String>(icon: const GhstButtonIcon.glyph(GhstActionKind.down, size: 18), initialValue: _requested, isExpanded: true, decoration: const InputDecoration(
                  labelText: 'Đăng ký vai trò',
                  border: OutlineInputBorder(),
                ), items: cloudAccountRoles.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(), onChanged: _busy
                    ? null
                    : (value) => setState(() => _requested = value!),),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_notice != null) Text(_notice!),
            if (_busy) const LinearProgressIndicator(),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const GhstButtonIcon(Icons.save_outlined),
              label: const Text('Lưu hồ sơ'),
            ),
            if (widget.onCancel != null)
              TextButton.icon(
                onPressed: _busy ? null : widget.onCancel,
                icon: const GhstButtonIcon.glyph(GhstActionKind.back, size: 16),

                label: const Text('Quay lại'),
              ),
            if (account != null && widget.session.schemaVersion >= 3)
              CloudMembershipPanel(
                session: widget.session,
                lease: widget.lease,
              ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) {
          return SingleChildScrollView(child: formBox);
        }
        return formBox;
      },
    );
  }
}
