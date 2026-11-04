part of 'customer_subsystem_views.dart';

extension _CustomerDraftsView on _CustomerSubsystemEntryState {
  Future<bool> _confirmReplaceCustomerForm() async {
    if (_dropoffCtrl.text.trim().isEmpty &&
        _recipientNameCtrl.text.trim().isEmpty &&
        _recipientPhoneCtrl.text.trim().isEmpty &&
        _pkgDescCtrl.text.trim().isEmpty &&
        _additionalStops.isEmpty &&
        _editingDraftId == null) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Thay nội dung đơn đang soạn?'),
            content: const Text(
              'Các thay đổi chưa lưu sẽ bị thay thế. Đơn nháp đã lưu vẫn được giữ lại.',
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx, false),
                icon: const GhstButtonIcon.glyph(GhstActionKind.checkCircle, size: 16),

                label: const Text('Giữ lại'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const GhstButtonIcon.glyph(GhstActionKind.edit, size: 16),

                label: const Text('Thay thế'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _resetCustomerOrderForm() {
    _draftFormRevision++;
    for (final controller in [
      _pickupCtrl,
      _dropoffCtrl,
      _recipientNameCtrl,
      _recipientPhoneCtrl,
      _extraDropoffCtrl,
      _extraRecipientNameCtrl,
      _extraRecipientPhoneCtrl,
      _pkgDescCtrl,
      _codCtrl,
      _declaredValueCtrl,
      _voucherCtrl,
    ]) {
      controller.clear();
    }
    _weightCtrl.text = '1.0';
    _dimCtrl.text = '20 x 15 x 10 cm';
    _pkgCategory = 'Quần áo & Thời trang';
    _selectedService = DeliveryServiceType.express30m;
    _cashFeePayer = 'Người gửi trả phí';
    _isScheduledDelivery = false;
    _scheduledDeliverySlot = '13:00 - 15:00';
    _additionalStops.clear();
    _isRoundTrip = false;
    _preferEcoEv = false;
    _greenFundContributed = false;
    _lastTspSavedMeters = null;
    _pinnedPickupLocation = null;
    _pinnedDropoffLocation = null;
    _osrmPreviewPoints = null;
    _osrmDistMeters = null;
    _osrmDurationSec = null;
    _editingDraftId = null;
    _userEditedPickupManually = false;
  }

  Map<String, dynamic> _captureCustomerDraft() {
    Map<String, double>? point(GeoPoint? p) =>
        p == null ? null : {'latitude': p.latitude, 'longitude': p.longitude};
    return {
      'pickup': _pickupCtrl.text,
      'dropoff': _dropoffCtrl.text,
      'recipientName': _recipientNameCtrl.text,
      'recipientPhone': _recipientPhoneCtrl.text,
      'category': _pkgCategory,
      'description': _pkgDescCtrl.text,
      'weight': _weightCtrl.text,
      'dimensions': _dimCtrl.text,
      'cod': _codCtrl.text,
      'declaredValue': _declaredValueCtrl.text,
      'roundTrip': _isRoundTrip,
      'preferEcoEv': _preferEcoEv,
      'greenFund': _greenFundContributed,
      'service': _selectedService.name,
      'payer': _cashFeePayer,
      'pickupPoint': point(_pinnedPickupLocation),
      'dropoffPoint': point(_pinnedDropoffLocation),
      'stops': _additionalStops
          .map((s) => Map<String, dynamic>.from(s))
          .toList(),
      'scheduled': _isScheduledDelivery,
      'slot': _scheduledDeliverySlot,
    };
  }

  void _restoreCustomerDraft(Map<String, dynamic> draft) {
    final ownerId = _store.activeAuthenticatedUser?.id;
    if (ownerId == null || draft['ownerId']?.toString() != ownerId) return;
    _resetCustomerOrderForm();
    final fields = Map<String, dynamic>.from(draft['fields'] as Map);
    GeoPoint? point(dynamic value) {
      if (value is! Map) return null;
      final lat = value['latitude'];
      final lng = value['longitude'];
      if (lat is! num ||
          lng is! num ||
          !lat.isFinite ||
          !lng.isFinite ||
          lat.abs() > 90 ||
          lng.abs() > 180) {
        return null;
      }
      return GeoPoint(latitude: lat.toDouble(), longitude: lng.toDouble());
    }

    _pickupCtrl.text = '${fields['pickup'] ?? ''}';
    _dropoffCtrl.text = '${fields['dropoff'] ?? ''}';
    _recipientNameCtrl.text = '${fields['recipientName'] ?? ''}';
    _recipientPhoneCtrl.text = '${fields['recipientPhone'] ?? ''}';
    _pkgCategory = '${fields['category'] ?? 'Quần áo & Thời trang'}';
    _pkgDescCtrl.text = '${fields['description'] ?? ''}';
    _weightCtrl.text = '${fields['weight'] ?? '1.0'}';
    _dimCtrl.text = '${fields['dimensions'] ?? ''}';
    _codCtrl.text = '${fields['cod'] ?? ''}';
    _declaredValueCtrl.text = '${fields['declaredValue'] ?? ''}';
    _isRoundTrip = fields['roundTrip'] == true;
    _preferEcoEv = fields['preferEcoEv'] == true;
    _greenFundContributed = fields['greenFund'] == true;
    _cashFeePayer = fields['payer'] == 'Người nhận trả phí'
        ? 'Người nhận trả phí'
        : 'Người gửi trả phí';
    _selectedService =
        DeliveryServiceType.values
            .where((s) => s.name == fields['service'])
            .firstOrNull ??
        DeliveryServiceType.standard;
    _pinnedPickupLocation = point(fields['pickupPoint']);
    _pinnedDropoffLocation = point(fields['dropoffPoint']);
    _additionalStops
      ..clear()
      ..addAll(
        (fields['stops'] as List? ?? const [])
            .whereType<Map>()
            .take(4)
            .map((s) => Map<String, dynamic>.from(s)),
      );
    _isScheduledDelivery = fields['scheduled'] == true;
    _scheduledDeliverySlot =
        const [
          '09:00 - 11:00',
          '13:00 - 15:00',
          '15:00 - 17:00',
          '18:00 - 20:00',
        ].contains(fields['slot'])
        ? fields['slot'] as String
        : '13:00 - 15:00';
    _editingDraftId = draft['id'] as String;
    _userEditedPickupManually = true;
    _voucherCtrl.clear();
    _osrmPreviewPoints = null;
    _osrmDistMeters = null;
    _osrmDurationSec = null;
    _selectedScreenIndex = 2;
  }

  Future<void> _saveCustomerDraft() async {
    if (_savingDraft) return;
    final ownerId = _store.activeAuthenticatedUser?.id;
    final revision = _draftFormRevision;
    _rebuildCustomerUi(() => _savingDraft = true);
    try {
      final id = await _store.saveCustomerOrderDraft(
        draftId: _editingDraftId,
        fields: _captureCustomerDraft(),
      );
      if (!mounted || _store.activeAuthenticatedUser?.id != ownerId) return;
      _rebuildCustomerUi(() {
        if (revision == _draftFormRevision) _editingDraftId = id;
        _draftsFuture = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã lưu đơn nháp.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không lưu được đơn nháp. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      _rebuildCustomerUi(() => _savingDraft = false);
    }
  }

  void _openCustomerDrafts() {
    _rebuildCustomerUi(() {
      _draftsFuture = _store.customerOrderDrafts();
      _selectedScreenIndex = 14;
    });
  }

  Widget _buildCustomerDraftsView() {
    _draftsFuture ??= _store.customerOrderDrafts();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Đơn nháp',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Tải lại đơn nháp',
              onPressed: _openCustomerDrafts,
              icon: const GhstButtonIcon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _draftsFuture,
          builder: (draftContext, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              return TextButton.icon(
                onPressed: _openCustomerDrafts,
                icon: const GhstButtonIcon(Icons.refresh),
                label: const Text('Không tải được đơn nháp. Thử lại'),
              );
            }
            final ownerId = _store.activeAuthenticatedUser?.id;
            final rows = (snapshot.data ?? const [])
                .where((row) => ownerId != null && row['ownerId'] == ownerId)
                .toList();
            if (rows.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Chưa có đơn nháp.'),
              );
            }
            return Column(
              children: rows.map((draft) {
                final fields = draft['fields'] as Map? ?? const {};
                final date = DateTime.fromMillisecondsSinceEpoch(
                  draft['updatedAtMs'] as int,
                );
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  leading: const GhstButtonIcon(Icons.drafts_outlined),
                  title: Text(
                    '${fields['recipientName']?.toString().trim().isNotEmpty == true ? fields['recipientName'] : 'Đơn chưa có người nhận'}',
                  ),
                  subtitle: Text(
                    '${fields['dropoff'] ?? ''}\n${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                  ),
                  onTap: () async {
                    if (!await _confirmReplaceCustomerForm() || !mounted) {
                      return;
                    }
                    _rebuildCustomerUi(() => _restoreCustomerDraft(draft));
                  },
                  trailing: IconButton(
                    tooltip: 'Xóa đơn nháp',
                    icon: const GhstButtonIcon(Icons.delete_outline),
                    onPressed: () async {
                      final ownerId = _store.activeAuthenticatedUser?.id;
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Xóa đơn nháp?'),
                          actions: [
                            TextButton.icon(
                              onPressed: () => Navigator.pop(ctx, false),
                              icon: const GhstButtonIcon.glyph(GhstActionKind.checkCircle, size: 16),

                              label: const Text('Giữ lại'),
                            ),
                            TextButton.icon(
                              onPressed: () => Navigator.pop(ctx, true),
                              icon: const GhstButtonIcon.glyph(GhstActionKind.delete, size: 16),

                              label: const Text('Xóa'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true ||
                          !mounted ||
                          ownerId != _store.activeAuthenticatedUser?.id) {
                        return;
                      }
                      try {
                        await _store.deleteCustomerOrderDraft(
                          draft['id'] as String,
                        );
                        if (!mounted ||
                            ownerId != _store.activeAuthenticatedUser?.id) {
                          return;
                        }
                        if (_editingDraftId == draft['id']) {
                          _editingDraftId = null;
                        }
                        _openCustomerDrafts();
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Không xóa được đơn nháp.'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
