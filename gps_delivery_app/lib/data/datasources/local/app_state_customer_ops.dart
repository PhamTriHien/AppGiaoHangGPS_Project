part of 'app_state_store.dart';

extension AppStateCustomerOps on AppStateStore {
  Future<Map<String, dynamic>> previewLegacyAddresses({
    required String identifier,
    required String password,
  }) async {
    await initializeDatabase();
    final user = findUserByPhoneOrEmail(identifier);
    if (user == null ||
        user.status != 'ACTIVE' ||
        password.trim().isEmpty ||
        user.passwordHash !=
            SecurityAndBarcodeUtils.hashPasswordWithSalt(
              password.trim(),
              _normalizePhone(user.phone),
            )) {
      throw StateError('Không xác minh được tài khoản trên thiết bị.');
    }
    // This verifies the local source only. It never activates a legacy session
    // or grants cloud ownership by matching an email or phone number.
    final rows = await _sqliteDb.getEntityRecords('customer_order_drafts');
    final device = LiveDeliveryService.instance;
    if (device.installationId.isEmpty) await device.loadInstallationIdentity();
    return {
      'source_instance': device.installationId,
      'source_id': user.id,
      'source_name': user.fullName,
      'draft_count': rows.where((r) => r['ownerId'] == user.id).length,
      'addresses': [
        for (final address in savedAddresses.where(
          (a) => _normalizePhone(a.userPhone) == _normalizePhone(user.phone),
        ))
          {
            'source_id': address.id,
            'details': {
              'label': address.label,
              'recipient_name': user.fullName,
              'recipient_phone': _normalizePhone(user.phone),
              'full_address': address.fullAddress,
              'latitude': address.location.latitude,
              'longitude': address.location.longitude,
            },
          },
      ],
    };
  }

  Future<List<Map<String, dynamic>>> customerOrderDrafts() async {
    final ownerId = activeAuthenticatedUser?.id;
    if (ownerId == null) return const [];
    final rows = await _sqliteDb.getEntityRecords('customer_order_drafts');
    if (activeAuthenticatedUser?.id != ownerId) return const [];
    return rows.where((row) => row['ownerId'] == ownerId).toList();
  }

  Future<String> saveCustomerOrderDraft({
    String? draftId,
    required Map<String, dynamic> fields,
  }) async {
    final ownerId = activeAuthenticatedUser?.id;
    if (ownerId == null) throw StateError('Cần đăng nhập để lưu đơn nháp.');
    final id = draftId ?? const Uuid().v4();
    if (!RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(id)) {
      throw ArgumentError('Mã đơn nháp không hợp lệ.');
    }
    // Copy the form before yielding so later edits cannot change this save.
    final copy = jsonDecode(jsonEncode(fields)) as Map<String, dynamic>;
    if (jsonEncode(copy).length > 50000) {
      throw ArgumentError('Nội dung đơn nháp quá dài.');
    }
    await _sqliteDb.upsertEntityRecord(
      tableName: 'customer_order_drafts',
      recordId: '$ownerId:$id',
      payload: {
        'id': id,
        'ownerId': ownerId,
        'fields': copy,
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      },
    );
    _notifyStoreChanged();
    return id;
  }

  Future<void> deleteCustomerOrderDraft(String draftId) async {
    final ownerId = activeAuthenticatedUser?.id;
    if (ownerId == null) return;
    await _sqliteDb.deleteRows(
      'local_relational_entities',
      where: 'table_name = ? AND record_id = ?',
      whereArgs: ['customer_order_drafts', '$ownerId:$draftId'],
    );
    _notifyStoreChanged();
  }
}
