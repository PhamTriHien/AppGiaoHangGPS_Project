part of 'app_state_store.dart';

extension AppStateOrderAndAdminOps on AppStateStore {
  bool hasAdminPermission(String permKey) {
    final role = rbacRoles
        .where((r) => r.roleName == currentAdminRoleName)
        .firstOrNull;
    if (role == null) return true;
    return role.permissions[permKey] ?? false;
  }

  bool setAdminActiveRole(
    String roleName, {
    String? adminPassword,
    bool requirePasswordVerification = false,
  }) {
    final activeUser = activeAuthenticatedUser;
    final isNonRootUserWithoutSecurity =
        !hasAdminPermission('Hệ thống: Bảo mật') &&
        activeUser != null &&
        activeUser.id != 'USR-04';
    if (isNonRootUserWithoutSecurity ||
        requirePasswordVerification ||
        adminPassword != null) {
      if (adminPassword == null || !verifySuperAdminPassword(adminPassword)) {
        return false;
      }
    }
    currentAdminRoleName = roleName;
    _persistMutation('SET_ADMIN_ACTIVE_ROLE', {'roleName': roleName});
    _notifyStoreChanged();
    return true;
  }

  void addCustomGeofenceZone({
    required String zoneName,
    required String zoneType,
    required double surchargeRate,
    required List<GeoPoint> vertices,
  }) {
    if (!hasAdminPermission('Hệ thống: Cài đặt')) return;
    if (vertices.length < 3) return;
    final newZone = GeofenceZoneRecord(
      id: 'GEO-0${geofenceZones.length + 1}',
      zoneName: zoneName,
      zoneType: zoneType,
      surchargeRate: surchargeRate,
      isActive: true,
      boundary: List<GeoPoint>.from(vertices),
    );
    geofenceZones.add(newZone);
    _sqliteDb.upsertRow('geofence_zones', {
      'id': newZone.id,
      'zone_name': newZone.zoneName,
      'zone_type': newZone.zoneType,
      'surcharge_rate': newZone.surchargeRate,
      'is_active': 1,
      'boundary_json': jsonEncode(
        newZone.boundary
            .map((pt) => {'lat': pt.latitude, 'lng': pt.longitude})
            .toList(),
      ),
    });
    _persistMutation('ADD_GEOFENCE_ZONE', {'zoneName': zoneName});
    _notifyStoreChanged();
  }

  void addCustomerAddress(
    String label,
    String address, {
    GeoPoint? customLocation,
  }) {
    final resolved =
        customLocation ??
        SmartDispatchEngine.resolveAddressToCoordinate(
          address,
          fallback: const GeoPoint(latitude: 10.7785, longitude: 106.6980),
        );
    final normUserPhone = _normalizePhone(customerPhone);
    final newAddr = SavedAddressRecord(
      id: allocateUniqueId('ADDR-', savedAddresses.map((a) => a.id)),
      userPhone: normUserPhone,
      label: label,
      fullAddress: address,
      location: resolved,
    );
    savedAddresses.add(newAddr);
    _sqliteDb.upsertRow('user_addresses', {
      'id': newAddr.id,
      'user_phone': _normalizePhone(customerPhone),
      'label': newAddr.label,
      'full_address': newAddr.fullAddress,
      'latitude': newAddr.location.latitude,
      'longitude': newAddr.location.longitude,
      'created_at': DateTime.now().toIso8601String(),
    });
    _persistMutation('ADD_ADDRESS', {'label': label, 'address': address});
    _notifyStoreChanged();
  }

  void removeCustomerAddress(String id) {
    savedAddresses.removeWhere((a) => a.id == id);
    _sqliteDb.deleteRows('user_addresses', where: 'id = ?', whereArgs: [id]);
    _persistMutation('REMOVE_ADDRESS', {'id': id});
    _notifyStoreChanged();
  }

  ActiveOrderRecord createNewOrder({
    required String pickupAddress,
    required String dropoffAddress,
    required String recipientName,
    required String recipientPhone,
    required String packageDescription,
    required double weightKg,
    required String dimensionsCm,
    required DeliveryServiceType serviceType,
    required double codAmount,
    required String paymentMethod,
    String? voucherCode,
    int? customDistanceMeters,
    int? customDurationSeconds,
    bool? isPrepaidConfirmed,
    bool? isFragileTag,
    bool? isKeepColdTag,
    String? customCustomerName,
    GeoPoint? customPickupLocation,
    GeoPoint? customDropoffLocation,
    List<Map<String, dynamic>> additionalStops = const [],
    bool preferEcoEv = false,
    double declaredValueVnd = 0.0,
    bool isRoundTrip = false,
    bool greenFundContributed = false,
  }) {
    bool isValidPoint(GeoPoint point) =>
        point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude.abs() <= 90 &&
        point.longitude.abs() <= 180;
    if (customPickupLocation != null && !isValidPoint(customPickupLocation) ||
        customDropoffLocation != null && !isValidPoint(customDropoffLocation)) {
      throw ArgumentError('Tọa độ không hợp lệ');
    }
    final pickupPt =
        customPickupLocation ??
        SmartDispatchEngine.resolveAddressToCoordinate(
          pickupAddress,
          fallback: const GeoPoint(latitude: 10.7769, longitude: 106.6953),
        );
    final verifiedDropoffPt =
        customDropoffLocation ??
        SmartDispatchEngine.tryResolveAddressToCoordinate(dropoffAddress);
    final firstDropoffPt =
        verifiedDropoffPt ??
        const GeoPoint(latitude: 10.7550, longitude: 106.6750);
    final extraStops = additionalStops
        .where((stop) => '${stop['address'] ?? ''}'.trim().isNotEmpty)
        .map((stop) => Map<String, dynamic>.from(stop))
        .toList();
    GeoPoint? explicitStopPoint(Map<String, dynamic> stop) {
      if (stop['latitude'] is! num || stop['longitude'] is! num) return null;
      final point = GeoPoint(
        latitude: (stop['latitude'] as num).toDouble(),
        longitude: (stop['longitude'] as num).toDouble(),
      );
      return isValidPoint(point) ? point : null;
    }

    final lastExtraStop = extraStops.lastOrNull;
    final verifiedLastPoint = lastExtraStop == null
        ? verifiedDropoffPt
        : explicitStopPoint(lastExtraStop) ??
              SmartDispatchEngine.tryResolveAddressToCoordinate(
                lastExtraStop['address'].toString(),
              );
    final normalizedStops = <Map<String, dynamic>>[
      {
        'stopType': 'DROPOFF',
        'address': dropoffAddress,
        'latitude': firstDropoffPt.latitude,
        'longitude': firstDropoffPt.longitude,
        'recipientName': recipientName,
        'recipientPhone': recipientPhone,
        'codAmount': codAmount,
      },
      ...extraStops,
    ];
    final extraStopCount =
        normalizedStops.length > 1 ? normalizedStops.length - 1 : 0;
    var lastDropoffPt = firstDropoffPt;
    var lastDropoffAddress = dropoffAddress;
    var routeMeters = 0.0;
    var previousPoint = pickupPt;
    for (final stop in normalizedStops) {
      final stopAddress = stop['address'].toString().trim();
      final stopPoint =
          explicitStopPoint(stop) ??
          SmartDispatchEngine.resolveAddressToCoordinate(
            stopAddress,
            fallback: lastDropoffPt,
          );
      routeMeters += GeoMath.distanceMeters(previousPoint, stopPoint) * 1.28;
      previousPoint = stopPoint;
      lastDropoffPt = stopPoint;
      lastDropoffAddress = stopAddress;
      stop['latitude'] = stopPoint.latitude;
      stop['longitude'] = stopPoint.longitude;
    }

    final isDefaultRoute =
        extraStopCount == 0 &&
        pickupAddress.contains('Phố Huế') &&
        dropoffAddress.contains('Lê Trọng Tấn');
    final rawAirMeters = routeMeters;
    final distMeters =
        customDistanceMeters ??
        (isDefaultRoute ? 14500 : rawAirMeters.round().clamp(1500, 45000));
    final durationSec =
        customDurationSeconds ??
        (isDefaultRoute
            ? 2700
            : (((distMeters / 1000.0) * 180).round() + extraStopCount * 180));

    double geofenceFee = verifiedLastPoint == null
        ? 0
        : computeGeofenceSurchargeForPoint(verifiedLastPoint);
    if (isWeatherSurchargeActive) {
      geofenceFee += badWeatherSurchargeConfig;
    }
    if (weightKg > 5.0) {
      geofenceFee += ((weightKg - 5.0) * 3000).roundToDouble();
    }
    final applyFragile =
        isFragileTag ?? packageDescription.toLowerCase().contains('dễ vỡ');
    final applyKeepCold =
        isKeepColdTag ?? packageDescription.toLowerCase().contains('giữ lạnh');
    if (applyFragile) {
      geofenceFee += 5000;
    }
    if (applyKeepCold) {
      geofenceFee += 10000;
    }

    final baseScale = (baseFareConfig / 25000.0).clamp(0.4, 5.0);
    final kmScale = (pricePerKmConfig / 5000.0).clamp(0.4, 5.0);
    final safeDeclaredValue = declaredValueVnd.isFinite && declaredValueVnd > 0
        ? declaredValueVnd.clamp(
            0.0,
            PricingEstimate.maxInsuredDeclaredValueVnd,
          )
        : 0.0;

    final preDiscountEst = PricingEstimate.calculate(
      serviceType: serviceType,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      isPeakHour: isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: 0,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
      configuredStandardPeakSurcharge: peakHourSurchargeConfig,
      declaredValueVnd: safeDeclaredValue,
      extraStopCount: extraStopCount,
      isRoundTrip: isRoundTrip,
      greenFundContribution: greenFundContributed,
      preferEcoEv: preferEcoEv,
    );

    double discount = 0;
    if (voucherCode != null && voucherCode.trim().isNotEmpty) {
      final matched = vouchers
          .where(
            (v) => v.code.toUpperCase() == voucherCode.trim().toUpperCase(),
          )
          .firstOrNull;
      if (matched != null &&
          matched.isUsable &&
          (preDiscountEst.totalAmount + codAmount) >= matched.minOrderValue) {
        if (matched.isPercentage) {
          final rawPct =
              preDiscountEst.totalAmount * (matched.discountValue / 100.0);
          discount = rawPct.clamp(0.0, matched.maxDiscount);
        } else {
          discount = matched.discountValue;
        }
        matched.usedCount += 1;
        _sqliteDb.updateRows(
          'vouchers',
          {'usage_limit': matched.usageLimit, 'used_count': matched.usedCount},
          where: 'code = ?',
          whereArgs: [matched.code],
        );
        _sqliteDb.upsertEntityRecord(
          tableName: 'voucher_meta',
          recordId: matched.code,
          payload: {
            'usageLimit': matched.usageLimit,
            'usedCount': matched.usedCount,
          },
        );
      }
    }

    final est = PricingEstimate.calculate(
      serviceType: serviceType,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      isPeakHour: isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: discount,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
      configuredStandardPeakSurcharge: peakHourSurchargeConfig,
      declaredValueVnd: safeDeclaredValue,
      extraStopCount: extraStopCount,
      isRoundTrip: isRoundTrip,
      greenFundContribution: greenFundContributed,
      preferEcoEv: preferEcoEv,
    );

    final resolvedCustomerName =
        (customCustomerName != null && customCustomerName.trim().isNotEmpty)
        ? customCustomerName.trim()
        : customerFullName;

    final now = DateTime.now();
    final todayFormatted =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final isCashMethod =
        paymentMethod.contains('Tiền mặt') ||
        paymentMethod == 'Người nhận trả phí' ||
        paymentMethod == 'Người gửi trả phí';
    final allocatedTrackingCode = allocateUniqueTrackingCode();
    final publicToken =
        'TRK-${SecurityAndBarcodeUtils.generatePaymentSignature(orderCode: allocatedTrackingCode, amount: est.totalAmount, method: recipientPhone).substring(0, 10)}';
    final physicalEvMeters = isRoundTrip
        ? (distMeters +
              (GeoMath.distanceMeters(lastDropoffPt, pickupPt) * 1.28).round())
        : distMeters;
    final estimatedCo2Grams = preferEcoEv
        ? GeoMath.estimateEvCo2SavedGrams(physicalEvMeters)
        : 0.0;

    final record = ActiveOrderRecord(
      id: allocateUniqueId(
        'ORD-',
        orders.map((o) => o.id),
        minNumber: 101,
        padDigits: 3,
      ),
      trackingCode: allocatedTrackingCode,
      customerName: resolvedCustomerName,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      pickupAddress: pickupAddress,
      dropoffAddress: lastDropoffAddress,
      pickupLocation: pickupPt,
      dropoffLocation: lastDropoffPt,
      serviceType: serviceType,
      packageDescription: packageDescription,
      weightKg: weightKg,
      dimensionsCm: dimensionsCm,
      distanceMeters: distMeters,
      durationSeconds: durationSec,
      deliveryFee: est.baseFare + est.distanceFare,
      surchargeFee: est.surchargeFee,
      discountAmount: est.discountAmount,
      codAmount: codAmount,
      totalAmount: est.totalAmount,
      paymentMethod: paymentMethod,
      paymentStatus:
          ((isCashMethod && isPrepaidConfirmed != true) ||
              isPrepaidConfirmed == false)
          ? 'UNPAID'
          : 'PAID',
      status: OrderStatus.searching,
      createdDateLabel: todayFormatted,
      createdAtMs: now.millisecondsSinceEpoch,
      preferEcoEv: preferEcoEv,
      declaredValueVnd: safeDeclaredValue,
      insuranceFee: est.insuranceFee,
      isRoundTrip: isRoundTrip,
      extraStopCount: extraStopCount,
      co2SavedGrams: estimatedCo2Grams,
      greenFundContributed: greenFundContributed,
      publicTrackingToken: publicToken,
    );

    if (serviceType == DeliveryServiceType.sameDay2h && !isRoundTrip) {
      final batchMatch = SmartDispatchEngine.findBestBatchPartner(
        record,
        orders,
      );
      if (batchMatch != null) {
        final batchId =
            (batchMatch.partnerOrder.batchGroupId != null &&
                batchMatch.partnerOrder.batchGroupId!.trim().isNotEmpty)
            ? batchMatch.partnerOrder.batchGroupId!
            : 'BATCH-2H-${record.id.replaceAll('ORD-', '')}';
        record.batchGroupId = batchId;
        batchMatch.partnerOrder.batchGroupId = batchId;
        _sqliteDb.updateRows(
          'orders',
          {'batch_group_id': batchId},
          where: 'tracking_code = ?',
          whereArgs: [batchMatch.partnerOrder.trackingCode],
        );
        _pushRealtimeNotification(
          category: 'Điều phối',
          title:
              'Đã ghép cặp thông minh gói 2H [$batchId]: ${record.trackingCode} + ${batchMatch.partnerOrder.trackingCode} (lệch góc ${batchMatch.bearingDifferenceDegrees.toStringAsFixed(1)}°).',
          targetGroup: 'Tài xế',
          recipientKey: batchId,
        );
      }
    }

    for (var sIdx = 0; sIdx < normalizedStops.length; sIdx++) {
      normalizedStops[sIdx]['otpCode'] = sIdx == 0
          ? SecurityAndBarcodeUtils.generateOrderDeliveryOtp4(
              allocatedTrackingCode,
            )
          : SecurityAndBarcodeUtils.generateOrderDeliveryOtp4(
              '${allocatedTrackingCode}_S${sIdx + 1}',
            );
    }
    final allStopsToPersist = <Map<String, dynamic>>[
      {
        'stopType': 'PICKUP',
        'address': pickupAddress,
        'latitude': pickupPt.latitude,
        'longitude': pickupPt.longitude,
        'recipientName': resolvedCustomerName,
        'recipientPhone': customerPhone,
        'status': 'PENDING',
        'note': 'Điểm lấy hàng xuất phát',
      },
      ...normalizedStops,
      if (isRoundTrip)
        {
          'stopType': 'RETURN',
          'address': pickupAddress,
          'latitude': pickupPt.latitude,
          'longitude': pickupPt.longitude,
          'recipientName': resolvedCustomerName,
          'recipientPhone': customerPhone,
          'codAmount': 0.0,
          'status': 'PENDING',
          'note': 'Giao 2 chiều: quay lại điểm lấy trả chứng từ / hàng thu hồi',
          'otpCode': SecurityAndBarcodeUtils.generateOrderDeliveryOtp4(
            '${allocatedTrackingCode}_RET',
          ),
        },
    ];

    orders.insert(0, record);
    selectedCustomerOrderCode = record.trackingCode;
    _sqliteDb.upsertRow('orders', record.toSqlRow());
    unawaited(
      saveOrderStops(
        orderId: record.id,
        stops: allStopsToPersist,
      ),
    );
    if (est.insuranceFee > 0) {
      unawaited(
        recordLedgerEntry(
          ownerType: 'PLATFORM',
          direction: 'CREDIT',
          entryType: 'PARCEL_INSURANCE_PREMIUM',
          amount: est.insuranceFee,
          orderId: record.id,
          idempotencyKey: 'INS_${record.id}',
          metadata: {
            'declaredValueVnd': safeDeclaredValue,
            'trackingCode': record.trackingCode,
          },
        ),
      );
    }
    if (greenFundContributed) {
      unawaited(
        recordLedgerEntry(
          ownerType: 'PLATFORM',
          direction: 'CREDIT',
          entryType: 'GREEN_FUND_CONTRIBUTION',
          amount: PricingEstimate.greenFundContributionUnitVnd,
          orderId: record.id,
          idempotencyKey: 'GREEN_${record.id}',
          metadata: {'trackingCode': record.trackingCode},
        ),
      );
    }
    activeRoutePolyline = SmartDispatchEngine.generateRoutePolyline(
      pickupPt,
      lastDropoffPt,
      segments: 10,
    );
    final owningMer = merchantApplicants
        .where(
          (m) =>
              m.storeName.trim().toLowerCase() ==
                  resolvedCustomerName.toLowerCase() ||
              m.representativeName.trim().toLowerCase() ==
                  resolvedCustomerName.toLowerCase(),
        )
        .firstOrNull;
    final resolvedCustomerUserId = owningMer != null
        ? (findUserByPhone(owningMer.ownerPhone)?.id ?? 'USR-03')
        : (activeAuthenticatedUser?.id ?? 'USR-01');
    _pushRealtimeNotification(
      category: 'Đơn hàng',
      title:
          'Đơn hàng ${record.trackingCode} đã được khởi tạo (${est.totalAmount.toStringAsFixed(0)}đ). Hệ thống đang tìm tài xế.',
      targetGroup: owningMer != null ? 'Cửa hàng B2B' : 'Khách hàng',
      recipientKey: owningMer?.id ?? resolvedCustomerName,
    );
    _dispatchMerchantOrderWebhookIfConfigured(
      record,
      eventName: 'ORDER_CREATED',
    );
    _persistMutation('CREATE_ORDER', {
      'table': 'orders',
      'trackingCode': record.trackingCode,
      'record': <String, Object?>{
        ...record.toSqlRow(),
        'customer_id': resolvedCustomerUserId,
        if (owningMer != null) 'merchant_id': owningMer.id,
      },
    });
    unawaited(
      recordAuditEvent(
        action: 'CREATE_ORDER',
        entityType: 'ORDER',
        entityId: record.id,
        after: record.toSqlRow(),
      ),
    );
    _notifyStoreChanged();
    return record;
  }

  void _dispatchMerchantOrderWebhookIfConfigured(
    ActiveOrderRecord ord, {
    required String eventName,
  }) {
    final custLower = ord.customerName.trim().toLowerCase();
    final owningMer = merchantApplicants
        .where(
          (m) =>
              m.storeName.trim().toLowerCase() == custLower ||
              m.representativeName.trim().toLowerCase() == custLower,
        )
        .firstOrNull;
    if (owningMer == null) return;
    final rawUrl = owningMer.webhookUrl.trim();
    if (rawUrl.isEmpty) return;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return;
    }
    final sig = SecurityAndBarcodeUtils.generatePaymentSignature(
      orderCode: ord.trackingCode,
      amount: ord.codAmount,
      method: owningMer.id,
    );
    final payload = <String, dynamic>{
      'event': eventName,
      'merchantId': owningMer.id,
      'storeName': owningMer.storeName,
      'trackingCode': ord.trackingCode,
      'status': ord.status.dbCode,
      'paymentStatus': ord.paymentStatus,
      'codAmount': ord.codAmount,
      'totalAmount': ord.totalAmount,
      'assignedDriverName': ord.assignedDriverName,
      'timestamp': DateTime.now().toIso8601String(),
      'signature': sig,
    };
    unawaited(
      queueWebhookDelivery(
        endpointUrl: rawUrl,
        eventType: eventName,
        aggregateId: ord.id,
        payload: payload,
        signature: sig,
      ),
    );
    if ((!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) ||
        isOfflineMode) {
      return;
    }
    unawaited(processDueWebhookDeliveries(maxItems: 10));
  }

  void _pushRealtimeNotification({
    required String category,
    required String title,
    String targetGroup = 'Khách hàng',
    String? recipientKey,
  }) {
    final noti = NotificationRecord(
      id: 'NOTI-${DateTime.now().millisecondsSinceEpoch}-${notifications.length + 1}',
      category: category,
      title: title,
      targetGroup: targetGroup,
      recipientKey: recipientKey,
      timeAgo: 'Vừa xong',
    );
    notifications.insert(0, noti);
    _sqliteDb.upsertRow('chat_messages_and_notifications', {
      'id': noti.id,
      'record_type': 'NOTIFICATION',
      'order_id': recipientKey,
      'recipient_key': recipientKey,
      'sender_name': 'Hệ thống',
      'is_customer': 0,
      'category': noti.category,
      'title': noti.title,
      'content': noti.title,
      'target_group': noti.targetGroup,
      'time_label': noti.timeAgo,
      'is_read': 0,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _recordWalletLedgerEntry({
    required String idPrefix,
    required String ownerId,
    required String ownerName,
    required String ownerRole,
    required double amount,
    required String bankName,
    required String accountMasked,
    required String status,
  }) {
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final entry = WithdrawalRequestRecord(
      id: '$idPrefix-${now.millisecondsSinceEpoch}-${withdrawalRequests.length + 1}',
      ownerId: ownerId,
      ownerName: ownerName,
      ownerRole: ownerRole,
      amount: amount,
      bankName: bankName,
      accountMasked: accountMasked,
      requestDate: dateStr,
      status: status,
    );
    withdrawalRequests.insert(0, entry);
    _sqliteDb.upsertRow('wallets_and_transactions', {
      'id': entry.id,
      'owner_id': entry.ownerId,
      'owner_name': entry.ownerName,
      'owner_role': entry.ownerRole,
      'amount': entry.amount,
      'bank_name': entry.bankName,
      'account_masked': entry.accountMasked,
      'request_date': entry.requestDate,
      'status': entry.status,
      'created_at_ms': now.millisecondsSinceEpoch,
    });
    if (ownerId.isNotEmpty) {
      _sqliteDb.upsertEntityRecord(
        tableName: 'withdrawal_meta',
        recordId: entry.id,
        payload: {'ownerId': ownerId},
      );
    }
  }

  void _syncMerchantCodReconciliation(MerchantApplicantRecord mer) {
    final now = DateTime.now();
    final period = 'Kỳ ${now.month.toString().padLeft(2, '0')}/${now.year}';
    final merStoreLower = mer.storeName.trim().toLowerCase();
    final merRepLower = mer.representativeName.trim().toLowerCase();
    final shopOrders = orders.where((o) {
      final custLower = o.customerName.trim().toLowerCase();
      final grabStoreLower = GrabFoodRecommendationEngine
          .extractGrabFoodStoreNameFromDescription(o.packageDescription)
          ?.trim()
          .toLowerCase();
      return (merStoreLower.isNotEmpty &&
              (custLower == merStoreLower || grabStoreLower == merStoreLower)) ||
          (merRepLower.isNotEmpty && custLower == merRepLower);
    }).toList();
    final deliveredShopOrders = shopOrders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus != 'RETURNED',
        )
        .toList();
    final returnedShopOrders = shopOrders
        .where(
          (o) =>
              o.status == OrderStatus.delivered &&
              o.paymentStatus == 'RETURNED',
        )
        .toList();

    double totalCod = 0;
    double totalFees = 0;
    for (final o in deliveredShopOrders) {
      totalCod += o.codAmount;
      final isRecipientOrPrepaid =
          o.paymentMethod == 'Người nhận trả phí' ||
          o.paymentMethod.contains('MoMo') ||
          o.paymentMethod.contains('VNPay') ||
          o.paymentMethod.contains('ZaloPay') ||
          o.paymentMethod.contains('thanh toán trước');
      final shipFee = isRecipientOrPrepaid ? 0.0 : o.totalAmount;
      final codHandling = o.codAmount > 2000000
          ? (o.codAmount * 0.005).roundToDouble()
          : 0.0;
      totalFees += shipFee + codHandling;
    }
    double totalReturnFee = 0;
    for (final rOrd in returnedShopOrders) {
      totalReturnFee += ((rOrd.deliveryFee + rOrd.surchargeFee) * 0.50)
          .roundToDouble();
    }
    final netPayout = totalCod - totalFees - totalReturnFee;
    final existingIdx = codReconciliations.indexWhere(
      (r) => r.merchantId == mer.id,
    );
    final recId = existingIdx >= 0
        ? codReconciliations[existingIdx].id
        : 'REC-${mer.id}';
    final rec = CodReconciliationRecord(
      id: recId,
      merchantId: mer.id,
      periodLabel: period,
      totalCodCollected: totalCod,
      totalServiceFee: totalFees,
      returnCancelFee: totalReturnFee,
      netPayoutAmount: netPayout,
      status: 'RECONCILED',
    );
    if (existingIdx >= 0) {
      codReconciliations[existingIdx] = rec;
    } else {
      codReconciliations.add(rec);
    }
    _sqliteDb.upsertRow('cod_reconciliations', {
      'id': rec.id,
      'merchant_id': rec.merchantId,
      'period_label': rec.periodLabel,
      'total_cod_collected': rec.totalCodCollected,
      'total_service_fee': rec.totalServiceFee,
      'return_cancel_fee': rec.returnCancelFee,
      'net_payout_amount': rec.netPayoutAmount,
      'status': rec.status,
    });
    _sqliteDb.upsertEntityRecord(
      tableName: 'cod_reconciliation_meta',
      recordId: rec.id,
      payload: {'returnCancelFee': rec.returnCancelFee},
    );
  }

  void _recordOrderStatusHistory(
    String orderId,
    OrderStatus status,
    String note,
  ) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _sqliteDb.upsertRow('local_relational_entities', {
      'table_name': 'order_status_histories',
      'record_id': 'HIST-$orderId-${status.name}-$nowMs',
      'payload_json': jsonEncode({
        'order_id': orderId,
        'status': status.name,
        'note': note,
        'updated_at': DateTime.now().toIso8601String(),
      }),
      'updated_at_ms': nowMs,
    });
  }

  /// Tra cứu vận đơn công khai theo mã vận đơn hoặc mã token chia sẻ (không cần đăng nhập)
  ActiveOrderRecord? findOrderForPublicTracking(String rawQuery) {
    final cleaned = rawQuery.trim().replaceAll('#', '').toUpperCase();
    if (cleaned.isEmpty) return null;
    return orders.where((o) {
      final codeUp = o.trackingCode.trim().replaceAll('#', '').toUpperCase();
      final tokenUp = (o.publicTrackingToken ?? '').trim().toUpperCase();
      return codeUp == cleaned ||
          (tokenUp.isNotEmpty && tokenUp == cleaned);
    }).firstOrNull;
  }

  /// Lấy danh sách đơn hàng ghép cặp cùng nhóm 2H với đơn hiện tại
  List<ActiveOrderRecord> batchPartnersFor(ActiveOrderRecord order) {
    final gid = order.batchGroupId;
    if (gid == null || gid.trim().isEmpty) return const [];
    return orders
        .where((o) => o.id != order.id && o.batchGroupId == gid)
        .toList(growable: false);
  }

  /// Tổng lượng CO2 giảm phát thải trên toàn hệ thống (tính bằng gram)
  double get totalSystemCo2SavedGrams {
    var sum = 0.0;
    for (final o in orders) {
      if (o.status != OrderStatus.cancelled) {
        sum += o.co2SavedGrams;
      }
    }
    return sum;
  }

  /// Tổng đóng góp Quỹ Xanh từ các đơn giao hàng
  double get totalGreenFundContributedVnd {
    var count = 0;
    for (final o in orders) {
      if (o.status != OrderStatus.cancelled && o.greenFundContributed) {
        count++;
      }
    }
    return count * PricingEstimate.greenFundContributionUnitVnd;
  }

  void driverAcceptOrder(
    String trackingCode, {
    String? customDriverName,
    String? customPlate,
  }) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return;
    if (!ord.status.canTransitionTo(OrderStatus.accepted)) return;
    if (!isDriverOnline) return;
    final activeDrv = activeDriverRecord;
    final linkedUser = activeDrv != null
        ? findUserByPhone(activeDrv.phone)
        : null;
    if (activeDrv == null ||
        activeDrv.approvalStatus != 'Đã duyệt' ||
        activeDrv.walletBalance < 200000 ||
        linkedUser?.status == 'LOCKED') {
      return;
    }
    if (!SmartDispatchEngine.isDriverEligibleForOrder(
      driver: activeDrv,
      pickupLocation: ord.pickupLocation,
      serviceType: ord.serviceType,
      requireElectricVehicle: ord.preferEcoEv,
      totalOrderRouteMeters:
          ord.isRoundTrip ? (ord.distanceMeters * 2) : ord.distanceMeters,
      declaredValueVnd: ord.declaredValueVnd,
      codAmount: ord.codAmount,
    )) {
      return;
    }
    ord.status = OrderStatus.accepted;
    ord.assignedDriverName = customDriverName ?? activeDrv.fullName;
    ord.assignedDriverPlate = customPlate ?? activeDrv.licensePlate;
    if (activeDrv.isElectricVehicle && ord.co2SavedGrams <= 0) {
      ord.co2SavedGrams = GeoMath.estimateEvCo2SavedGrams(
        ord.isRoundTrip ? (ord.distanceMeters * 2) : ord.distanceMeters,
      );
    }
    selectedDriverOrderCode = trackingCode;
    activeRoutePolyline = SmartDispatchEngine.generateRoutePolyline(
      ord.pickupLocation,
      ord.dropoffLocation,
      segments: 10,
    );
    activeDriverLocation = ord.pickupLocation;
    activeDrv.location = ord.pickupLocation;
    routeProgressStep = 0;
    _sqliteDb.updateRows(
      'orders',
      {
        'status': ord.status.name,
        'assigned_driver_name': ord.assignedDriverName,
        'assigned_driver_plate': ord.assignedDriverPlate,
        'co2_saved_grams': ord.co2SavedGrams,
      },
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _recordOrderStatusHistory(
      ord.id,
      ord.status,
      'Tài xế ${ord.assignedDriverName} (${ord.assignedDriverPlate}) đã nhận đơn',
    );
    final owningMer = merchantApplicants
        .where(
          (m) =>
              m.storeName.trim().toLowerCase() ==
              ord.customerName.trim().toLowerCase(),
        )
        .firstOrNull;
    _pushRealtimeNotification(
      category: 'Đơn hàng',
      title:
          'Tài xế ${ord.assignedDriverName} (${ord.assignedDriverPlate}) đã nhận đơn ${ord.trackingCode}.',
      targetGroup: owningMer != null ? 'Cửa hàng B2B' : 'Khách hàng',
      recipientKey: owningMer?.id ?? ord.customerName,
    );
    _dispatchMerchantOrderWebhookIfConfigured(ord, eventName: 'ORDER_ACCEPTED');
    _persistMutation('DRIVER_ACCEPT_ORDER', {
      'table': 'orders',
      'trackingCode': trackingCode,
      'record': ord.toSqlRow(),
    });
    _notifyStoreChanged();
  }

  bool adminAssignOrReassignDriver({
    required String trackingCode,
    required DriverApplicantRecord driver,
  }) {
    if (!hasAdminPermission('Đơn: Sửa')) return false;
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return false;
    if (ord.status == OrderStatus.delivered ||
        ord.status == OrderStatus.cancelled ||
        ord.status == OrderStatus.returning ||
        ord.paymentStatus == 'RETURNED') {
      return false;
    }
    if (driver.approvalStatus != 'Đã duyệt' ||
        !driver.isOnline ||
        driver.walletBalance < 200000) {
      return false;
    }
    final linkedUser = findUserByPhone(driver.phone);
    if (linkedUser != null && linkedUser.status == 'LOCKED') {
      return false;
    }
    if (!SmartDispatchEngine.isDriverEligibleForOrder(
      driver: driver,
      pickupLocation: ord.pickupLocation,
      serviceType: ord.serviceType,
      requireElectricVehicle: ord.preferEcoEv,
      totalOrderRouteMeters:
          ord.isRoundTrip ? (ord.distanceMeters * 2) : ord.distanceMeters,
      declaredValueVnd: ord.declaredValueVnd,
      codAmount: ord.codAmount,
    )) {
      return false;
    }
    if (ord.status == OrderStatus.failed) {
      ord.status = OrderStatus.inTransit;
      ord.cancelReason = null;
    } else if (ord.status == OrderStatus.searching ||
        ord.status == OrderStatus.draft) {
      ord.status = OrderStatus.accepted;
      ord.cancelReason = null;
    }
    ord.assignedDriverName = driver.fullName;
    ord.assignedDriverPlate = driver.licensePlate;
    if (driver.isElectricVehicle && ord.co2SavedGrams <= 0) {
      ord.co2SavedGrams = GeoMath.estimateEvCo2SavedGrams(
        ord.isRoundTrip ? (ord.distanceMeters * 2) : ord.distanceMeters,
      );
    }
    selectedDriverOrderCode = trackingCode;
    activeRoutePolyline = SmartDispatchEngine.generateRoutePolyline(
      ord.pickupLocation,
      ord.dropoffLocation,
      segments: 10,
    );
    activeDriverLocation = ord.pickupLocation;
    routeProgressStep = 0;
    _sqliteDb.updateRows(
      'orders',
      {
        'status': ord.status.name,
        'assigned_driver_name': ord.assignedDriverName,
        'assigned_driver_plate': ord.assignedDriverPlate,
        'cancel_reason': ord.cancelReason,
      },
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _recordOrderStatusHistory(
      ord.id,
      ord.status,
      'Quản trị viên gán/điều phối lại cho tài xế ${driver.fullName} (${driver.licensePlate})',
    );
    _pushRealtimeNotification(
      category: 'Đơn hàng',
      title:
          'Điều phối viên đã gán đơn ${ord.trackingCode} cho tài xế ${driver.fullName}.',
      targetGroup: 'Tài xế',
      recipientKey: driver.id,
    );
    final owningMer = merchantApplicants
        .where(
          (m) =>
              m.storeName.trim().toLowerCase() ==
              ord.customerName.trim().toLowerCase(),
        )
        .firstOrNull;
    _pushRealtimeNotification(
      category: 'Đơn hàng',
      title:
          'Đơn hàng ${ord.trackingCode} đã được điều phối cho tài xế ${driver.fullName} (${driver.licensePlate}).',
      targetGroup: owningMer != null ? 'Cửa hàng B2B' : 'Khách hàng',
      recipientKey: owningMer?.id ?? ord.customerName,
    );
    _dispatchMerchantOrderWebhookIfConfigured(
      ord,
      eventName: 'ORDER_DRIVER_ASSIGNED',
    );
    _persistMutation('ADMIN_ASSIGN_DRIVER', {
      'trackingCode': trackingCode,
      'driverId': driver.id,
      'driverName': driver.fullName,
    });
    _notifyStoreChanged();
    return true;
  }

  void driverAdvanceOrderStatus(
    String trackingCode, {
    String? podNote,
    bool allowAdminOverride = false,
  }) {
    if (allowAdminOverride && !hasAdminPermission('Đơn: Sửa')) return;
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return;
    if (!allowAdminOverride && !isDriverOnline) return;
    final activeDrv = activeDriverRecord;
    final linkedUser = activeDrv != null
        ? findUserByPhone(activeDrv.phone)
        : null;
    if (!allowAdminOverride &&
        (activeDrv == null ||
            activeDrv.approvalStatus != 'Đã duyệt' ||
            activeDrv.walletBalance < 200000 ||
            linkedUser?.status == 'LOCKED')) {
      return;
    }
    final currentDrvName = (activeDrv?.fullName ?? activeDriverName)
        .trim()
        .toLowerCase();
    if (!allowAdminOverride &&
        ord.assignedDriverName != null &&
        ord.assignedDriverName!.trim().isNotEmpty &&
        currentDrvName.isNotEmpty &&
        ord.assignedDriverName!.trim().toLowerCase() != currentDrvName) {
      return;
    }
    final assignedDrv =
        (ord.assignedDriverName != null
            ? drivers
                  .where(
                    (d) =>
                        d.fullName.trim().toLowerCase() ==
                        ord.assignedDriverName!.trim().toLowerCase(),
                  )
                  .firstOrNull
            : null) ??
        activeDrv;
    switch (ord.status) {
      case OrderStatus.searching:
      case OrderStatus.draft:
        if (!allowAdminOverride &&
            ord.serviceType == DeliveryServiceType.truck) {
          final vLower = (assignedDrv?.vehicleType ?? '').toLowerCase();
          final isTruckCapable =
              vLower.contains('tải') ||
              vLower.contains('van') ||
              vLower.contains('truck');
          if (!isTruckCapable) return;
        }
        ord.status = OrderStatus.accepted;
        ord.assignedDriverName = assignedDrv?.fullName ?? activeDriverName;
        ord.assignedDriverPlate = assignedDrv?.licensePlate ?? '';
      case OrderStatus.accepted:
        ord.status = OrderStatus.arrivingPickup;
      case OrderStatus.arrivingPickup:
        ord.status = OrderStatus.inTransit;
      case OrderStatus.inTransit:
        ord.status = OrderStatus.delivered;
        ord.deliveredAtMs = DateTime.now().millisecondsSinceEpoch;
        ord.paymentStatus = 'PAID';
        ord.podImageNote =
            podNote ?? 'Đã chụp ảnh kiện hàng kèm Watermark GPS & OTP 4 số';
        if (assignedDrv != null && assignedDrv.isElectricVehicle) {
          if (ord.co2SavedGrams <= 0) {
            ord.co2SavedGrams = GeoMath.estimateEvCo2SavedGrams(
              ord.isRoundTrip ? (ord.distanceMeters * 2) : ord.distanceMeters,
            );
          }
          final socUsed = ((ord.isRoundTrip
                          ? ord.distanceMeters * 2
                          : ord.distanceMeters) /
                      SmartDispatchEngine.evFullChargeRangeMeters *
                      100)
                  .round()
                  .clamp(1, 25);
          assignedDrv.batteryPercent =
              (assignedDrv.batteryPercent - socUsed).clamp(5, 100);
        }
        final nonDriverSurcharges =
            ord.insuranceFee +
            (ord.greenFundContributed
                ? PricingEstimate.greenFundContributionUnitVnd
                : 0.0);
        final commissionableBase =
            (ord.deliveryFee + ord.surchargeFee - nonDriverSurcharges).clamp(
              0.0,
              double.infinity,
            );
        final driverNetEarning = (commissionableBase * 0.80).roundToDouble();
        unawaited(
          _sqliteDb.updateRows(
            'order_stops',
            {
              'status': 'COMPLETED',
              'completed_at_ms': ord.deliveredAtMs,
            },
            where: 'order_id = ? AND status != ?',
            whereArgs: [ord.id, 'COMPLETED'],
          ),
        );
        if (assignedDrv != null) {
          assignedDrv.totalTrips += 1;
          assignedDrv.walletBalance += driverNetEarning;
          if (assignedDrv.id == activeDriverId ||
              assignedDrv.fullName.trim().toLowerCase() ==
                  activeDriverName.trim().toLowerCase()) {
            driverWalletBalance = assignedDrv.walletBalance;
          }
          _recordWalletLedgerEntry(
            idPrefix: 'EARN',
            ownerId: assignedDrv.id,
            ownerName: assignedDrv.fullName,
            ownerRole: 'Tài xế (Thu nhập chuyến)',
            amount: driverNetEarning,
            bankName: 'Ví tài xế (80% cước)',
            accountMasked: ord.trackingCode,
            status: 'Đã cộng ví',
          );
        } else {
          driverWalletBalance += driverNetEarning;
        }
        final ordOwnerLower = ord.customerName.trim().toLowerCase();
        final grabStoreLower = GrabFoodRecommendationEngine
            .extractGrabFoodStoreNameFromDescription(ord.packageDescription)
            ?.trim()
            .toLowerCase();
        final matchedMer = merchantApplicants
            .where((m) {
              final mStore = m.storeName.trim().toLowerCase();
              return mStore == ordOwnerLower ||
                  m.representativeName.trim().toLowerCase() == ordOwnerLower ||
                  (grabStoreLower != null && grabStoreLower == mStore);
            })
            .firstOrNull;
        if (matchedMer != null) {
          final codHandlingFee = ord.codAmount > 2000000
              ? (ord.codAmount * 0.005).roundToDouble()
              : 0.0;
          final isShipPrepaidOrRecipientPaid =
              ord.paymentMethod == 'Người nhận trả phí' ||
              ord.paymentMethod.contains('MoMo') ||
              ord.paymentMethod.contains('VNPay') ||
              ord.paymentMethod.contains('ZaloPay') ||
              ord.paymentMethod.contains('thanh toán trước');
          final shipDeduct = isShipPrepaidOrRecipientPaid
              ? 0.0
              : ord.totalAmount;
          final netMerchantDelta = ord.codAmount - shipDeduct - codHandlingFee;
          matchedMer.codBalance = (matchedMer.codBalance + netMerchantDelta)
              .clamp(0.0, double.infinity);
          if (matchedMer.id == activeMerchantRecord?.id ||
              matchedMer.storeName.trim().toLowerCase() ==
                  merchantStoreName.trim().toLowerCase()) {
            merchantCodBalance = matchedMer.codBalance;
          }
          _sqliteDb.updateRows(
            'merchants',
            {'cod_balance': matchedMer.codBalance},
            where: 'id = ?',
            whereArgs: [matchedMer.id],
          );
          _syncMerchantCodReconciliation(matchedMer);
        }
        _sqliteDb.updateRows(
          'drivers',
          {
            'wallet_balance': assignedDrv?.walletBalance ?? driverWalletBalance,
            if (assignedDrv != null) 'total_trips': assignedDrv.totalTrips,
            if (assignedDrv != null)
              'battery_percent': assignedDrv.batteryPercent,
          },
          where: 'id = ?',
          whereArgs: [assignedDrv?.id ?? activeDriverId],
        );
      case OrderStatus.failed:
        ord.status = OrderStatus.inTransit;
        ord.cancelReason = null;
      case OrderStatus.returning:
        ord.status = OrderStatus.delivered;
        ord.deliveredAtMs = DateTime.now().millisecondsSinceEpoch;
        ord.paymentStatus = 'RETURNED';
        ord.podImageNote =
            podNote ?? 'Đã hoàn trả kiện hàng về kho Cửa hàng thành công';
        final returnFee = ((ord.deliveryFee + ord.surchargeFee) * 0.50)
            .roundToDouble();
        final driverReturnComp = (returnFee * 0.80).roundToDouble();
        if (assignedDrv != null && driverReturnComp > 0) {
          assignedDrv.totalTrips += 1;
          assignedDrv.walletBalance += driverReturnComp;
          if (assignedDrv.id == activeDriverId ||
              assignedDrv.fullName.trim().toLowerCase() ==
                  activeDriverName.trim().toLowerCase()) {
            driverWalletBalance = assignedDrv.walletBalance;
          }
          _sqliteDb.updateRows(
            'drivers',
            {
              'wallet_balance': assignedDrv.walletBalance,
              'total_trips': assignedDrv.totalTrips,
            },
            where: 'id = ?',
            whereArgs: [assignedDrv.id],
          );
          _recordWalletLedgerEntry(
            idPrefix: 'RET',
            ownerId: assignedDrv.id,
            ownerName: assignedDrv.fullName,
            ownerRole: 'Tài xế (Phí hoàn hàng)',
            amount: driverReturnComp,
            bankName: 'Ví tài xế (80% cước hoàn)',
            accountMasked: ord.trackingCode,
            status: 'Đã cộng ví',
          );
        }
        final returnOwnerLower = ord.customerName.trim().toLowerCase();
        final returnMer = merchantApplicants
            .where(
              (m) =>
                  m.storeName.trim().toLowerCase() == returnOwnerLower ||
                  m.representativeName.trim().toLowerCase() == returnOwnerLower,
            )
            .firstOrNull;
        if (returnMer != null) {
          returnMer.codBalance = (returnMer.codBalance - returnFee).clamp(
            0.0,
            double.infinity,
          );
          if (returnMer.id == activeMerchantRecord?.id ||
              returnMer.storeName.trim().toLowerCase() ==
                  merchantStoreName.trim().toLowerCase()) {
            merchantCodBalance = returnMer.codBalance;
          }
          _sqliteDb.updateRows(
            'merchants',
            {'cod_balance': returnMer.codBalance},
            where: 'id = ?',
            whereArgs: [returnMer.id],
          );
          _syncMerchantCodReconciliation(returnMer);
        }
      default:
        break;
    }
    _sqliteDb.updateRows(
      'orders',
      {
        'status': ord.status.name,
        'payment_status': ord.paymentStatus,
        'assigned_driver_name': ord.assignedDriverName,
        'assigned_driver_plate': ord.assignedDriverPlate,
        'pod_image_note': ord.podImageNote,
        'delivered_at_ms': ord.deliveredAtMs,
        'co2_saved_grams': ord.co2SavedGrams,
      },
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _recordOrderStatusHistory(
      ord.id,
      ord.status,
      ord.podImageNote ??
          'Cập nhật trạng thái vận đơn sang ${ord.status.displayName}',
    );
    final owningMer = merchantApplicants
        .where(
          (m) =>
              m.storeName.trim().toLowerCase() ==
              ord.customerName.trim().toLowerCase(),
        )
        .firstOrNull;
    final isReturnedSettled =
        ord.status == OrderStatus.delivered && ord.paymentStatus == 'RETURNED';
    _pushRealtimeNotification(
      category: 'Đơn hàng',
      title: isReturnedSettled
          ? 'Đơn hàng ${ord.trackingCode}: Đã hoàn trả kiện hàng về kho thành công.'
          : 'Đơn hàng ${ord.trackingCode}: Trạng thái chuyển sang "${ord.status.displayName}".',
      targetGroup: owningMer != null ? 'Cửa hàng B2B' : 'Khách hàng',
      recipientKey: owningMer?.id ?? ord.customerName,
    );
    _dispatchMerchantOrderWebhookIfConfigured(
      ord,
      eventName: isReturnedSettled
          ? 'ORDER_RETURNED_TO_WAREHOUSE'
          : 'ORDER_STATUS_UPDATED',
    );
    _persistMutation('ADVANCE_ORDER_STATUS', {
      'trackingCode': trackingCode,
      'status': ord.status.name,
    });
    _notifyStoreChanged();
  }

  /// Tài xế ghi nhận giao hàng thất bại (Khách không nhận / Sai địa chỉ / Không liên lạc được)
  bool driverMarkDeliveryFailed(String trackingCode, String reason) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null || !ord.status.canTransitionTo(OrderStatus.failed)) {
      return false;
    }
    final cleanReason = reason.trim().isNotEmpty
        ? reason.trim()
        : 'Không liên lạc được với người nhận tại điểm giao';
    ord.status = OrderStatus.failed;
    ord.cancelReason = cleanReason;
    _sqliteDb.updateRows(
      'orders',
      {'status': ord.status.name, 'cancel_reason': ord.cancelReason},
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _recordOrderStatusHistory(
      ord.id,
      OrderStatus.failed,
      'Giao thất bại: $cleanReason',
    );
    final owningMer = merchantApplicants
        .where(
          (m) =>
              m.storeName.trim().toLowerCase() ==
              ord.customerName.trim().toLowerCase(),
        )
        .firstOrNull;
    _pushRealtimeNotification(
      category: 'Đơn hàng',
      title:
          'Đơn hàng ${ord.trackingCode} giao thất bại ($cleanReason). Vui lòng xác nhận Giao lại hoặc Hoàn hàng.',
      targetGroup: owningMer != null ? 'Cửa hàng B2B' : 'Khách hàng',
      recipientKey: owningMer?.id ?? ord.customerName,
    );
    _dispatchMerchantOrderWebhookIfConfigured(
      ord,
      eventName: 'ORDER_DELIVERY_FAILED',
    );
    _persistMutation('DRIVER_MARK_FAILED', {
      'trackingCode': trackingCode,
      'reason': cleanReason,
    });
    _notifyStoreChanged();
    return true;
  }

  bool cancelOrder(String trackingCode, String reason) {
    if (activeAuthenticatedUser?.role == SubsystemRole.admin &&
        !hasAdminPermission('Đơn: Xóa')) {
      return false;
    }
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return false;
    if (!ord.status.canTransitionTo(OrderStatus.cancelled)) {
      return false;
    }
    final previousStatus = ord.status;
    final hadDriverAccepted =
        previousStatus == OrderStatus.accepted ||
        previousStatus == OrderStatus.arrivingPickup;
    final customerInitiatedLateCancel =
        hadDriverAccepted &&
        !reason.contains('Tài xế yêu cầu hủy') &&
        !reason.startsWith('Admin:');
    const lateCancelFee = 15000.0;
    const driverCancelComp = 12000.0;

    ord.status = OrderStatus.cancelled;
    final wasPrepaid = ord.paymentStatus == 'PAID';
    if (wasPrepaid) {
      ord.paymentStatus = 'REFUNDED';
    }
    if (customerInitiatedLateCancel) {
      final netRefund = (ord.totalAmount - lateCancelFee).clamp(
        0.0,
        double.infinity,
      );
      ord.cancelReason = wasPrepaid
          ? '$reason (Khấu trừ phí hủy 15.000đ • Hoàn ví ${netRefund.toStringAsFixed(0)}đ)'
          : '$reason (Ghi nhận phí hủy sau nhận chuyến: 15.000đ)';
      final assignedDrv =
          (ord.assignedDriverName != null
              ? drivers
                    .where(
                      (d) =>
                          d.fullName.trim().toLowerCase() ==
                          ord.assignedDriverName!.trim().toLowerCase(),
                    )
                    .firstOrNull
              : null) ??
          activeDriverRecord;
      if (assignedDrv != null) {
        assignedDrv.walletBalance += driverCancelComp;
        if (assignedDrv.id == activeDriverId ||
            assignedDrv.fullName.trim().toLowerCase() ==
                activeDriverName.trim().toLowerCase()) {
          driverWalletBalance = assignedDrv.walletBalance;
        }
        _sqliteDb.updateRows(
          'drivers',
          {'wallet_balance': assignedDrv.walletBalance},
          where: 'id = ?',
          whereArgs: [assignedDrv.id],
        );
        _recordWalletLedgerEntry(
          idPrefix: 'COMP',
          ownerId: assignedDrv.id,
          ownerName: assignedDrv.fullName,
          ownerRole: 'Tài xế (Bồi hoàn hủy chuyến)',
          amount: driverCancelComp,
          bankName: 'Trích từ phí hủy 15.000đ',
          accountMasked: ord.trackingCode,
          status: 'Đã cộng ví',
        );
      } else {
        driverWalletBalance += driverCancelComp;
      }
    } else {
      ord.cancelReason = reason;
    }
    _sqliteDb.updateRows(
      'orders',
      {
        'status': ord.status.name,
        'payment_status': ord.paymentStatus,
        'cancel_reason': ord.cancelReason,
      },
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _recordOrderStatusHistory(
      ord.id,
      OrderStatus.cancelled,
      'Hủy đơn hàng: ${ord.cancelReason}',
    );
    final owningMer = merchantApplicants
        .where(
          (m) =>
              m.storeName.trim().toLowerCase() ==
              ord.customerName.trim().toLowerCase(),
        )
        .firstOrNull;
    _pushRealtimeNotification(
      category: 'Đơn hàng',
      title: 'Đơn hàng ${ord.trackingCode} đã bị hủy (${ord.cancelReason}).',
      targetGroup: owningMer != null ? 'Cửa hàng B2B' : 'Khách hàng',
      recipientKey: owningMer?.id ?? ord.customerName,
    );
    if (ord.assignedDriverName != null &&
        ord.assignedDriverName!.trim().isNotEmpty) {
      final assignedDrv = drivers
          .where(
            (d) =>
                d.fullName.trim().toLowerCase() ==
                ord.assignedDriverName!.trim().toLowerCase(),
          )
          .firstOrNull;
      _pushRealtimeNotification(
        category: 'Đơn hàng',
        title:
            'Đơn hàng ${ord.trackingCode} bạn đang nhận đã bị hủy (${ord.cancelReason}).',
        targetGroup: 'Tài xế',
        recipientKey: assignedDrv?.id ?? ord.assignedDriverName,
      );
    }
    _dispatchMerchantOrderWebhookIfConfigured(
      ord,
      eventName: 'ORDER_CANCELLED',
    );
    _persistMutation('CANCEL_ORDER', {
      'table': 'orders',
      'trackingCode': trackingCode,
      'reason': ord.cancelReason,
      'record': ord.toSqlRow(),
    });
    _notifyStoreChanged();
    return true;
  }

  void submitDriverRating(
    String trackingCode,
    int stars,
    String comment, {
    double tipVnd = 0,
  }) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord != null &&
        ord.status == OrderStatus.delivered &&
        ord.paymentStatus != 'RETURNED') {
      final wasAlreadyRated = ord.ratingStars != null;
      ord.ratingStars = stars;
      ord.ratingComment = comment;
      final targetDrv =
          (ord.assignedDriverName != null
              ? drivers
                    .where((d) => d.fullName == ord.assignedDriverName)
                    .firstOrNull
              : null) ??
          activeDriverRecord ??
          drivers.firstOrNull;
      if (!wasAlreadyRated && tipVnd > 0) {
        if (targetDrv != null) {
          targetDrv.walletBalance += tipVnd;
          if (targetDrv.id == activeDriverId ||
              targetDrv.fullName.trim().toLowerCase() ==
                  activeDriverName.trim().toLowerCase()) {
            driverWalletBalance = targetDrv.walletBalance;
          }
          _recordWalletLedgerEntry(
            idPrefix: 'TIP',
            ownerId: targetDrv.id,
            ownerName: targetDrv.fullName,
            ownerRole: 'Tài xế (Tiền tip)',
            amount: tipVnd,
            bankName: 'Thưởng khách hàng',
            accountMasked: ord.trackingCode,
            status: 'Đã cộng ví',
          );
          _pushRealtimeNotification(
            category: 'Đơn hàng',
            title:
                'Khách hàng vừa đánh giá $stars sao & thưởng +${tipVnd.toStringAsFixed(0)}đ cho đơn ${ord.trackingCode}.',
            targetGroup: 'Tài xế',
            recipientKey: targetDrv.id,
          );
        } else {
          driverWalletBalance += tipVnd;
        }
      }
      final ratedList = orders.where((o) => o.ratingStars != null).toList();
      if (targetDrv != null && ratedList.isNotEmpty) {
        final driverRatedList = ratedList
            .where((o) => o.assignedDriverName == targetDrv.fullName)
            .toList();
        final relevantOrders = driverRatedList.isNotEmpty
            ? driverRatedList
            : ratedList;
        final avg =
            relevantOrders.fold<int>(0, (s, o) => s + o.ratingStars!) /
            relevantOrders.length;
        targetDrv.rating = double.parse(avg.toStringAsFixed(1));
      }
      if (targetDrv != null) {
        _sqliteDb.updateRows(
          'drivers',
          {
            'wallet_balance': targetDrv.walletBalance,
            'rating': targetDrv.rating,
          },
          where: 'id = ?',
          whereArgs: [targetDrv.id],
        );
      }
      _sqliteDb.updateRows(
        'orders',
        {'rating_stars': stars, 'rating_comment': comment},
        where: 'tracking_code = ?',
        whereArgs: [trackingCode],
      );
      _sqliteDb.upsertRow('order_ratings', {
        'id': 'RAT-${ord.id}',
        'order_tracking_code': trackingCode,
        'customer_name': ord.customerName,
        'driver_name': ord.assignedDriverName ?? activeDriverName,
        'stars': stars,
        'comment': comment,
        'created_at': DateTime.now().toIso8601String(),
      });
      _persistMutation('SUBMIT_RATING', {
        'trackingCode': trackingCode,
        'stars': stars,
        'tipVnd': wasAlreadyRated ? 0 : tipVnd,
      });
    }
    _notifyStoreChanged();
  }

  void sendChatMessage(
    String orderId,
    String text, {
    required bool isCustomer,
  }) {
    if (text.trim().isEmpty) return;
    final msg = ChatMessageRecord(
      id: const Uuid().v4(),
      orderId: orderId,
      senderName: isCustomer ? customerFullName : activeDriverName,
      isCustomer: isCustomer,
      text: text.trim(),
      timeLabel: 'Vừa xong',
    );
    chatMessages.add(msg);
    _sqliteDb.upsertRow('chat_messages_and_notifications', {
      'id': msg.id,
      'record_type': 'CHAT',
      'order_id': msg.orderId,
      'recipient_key': null,
      'sender_name': msg.senderName,
      'is_customer': msg.isCustomer ? 1 : 0,
      'category': 'CHAT_MESSAGE',
      'title': msg.senderName,
      'content': msg.text,
      'target_group': 'INDIVIDUAL',
      'time_label': msg.timeLabel,
      'is_read': 1,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    _persistMutation('SEND_CHAT', {'orderId': orderId, 'text': text.trim()});
    _publishLiveChat(orderId, text.trim(), isCustomer, msg.id);
    _notifyStoreChanged();
  }

  bool topUpDriverWallet({
    required double amount,
    String bankName = 'Vietcombank',
    String accountMasked = '007100****889',
  }) {
    if (amount <= 0) return false;
    final activeDrv = activeDriverRecord;
    if (activeDrv == null) return false;
    activeDrv.walletBalance += amount;
    driverWalletBalance = activeDrv.walletBalance;
    _sqliteDb.updateRows(
      'drivers',
      {'wallet_balance': activeDrv.walletBalance},
      where: 'id = ?',
      whereArgs: [activeDrv.id],
    );
    _recordWalletLedgerEntry(
      idPrefix: 'TOPUP',
      ownerId: activeDrv.id,
      ownerName: activeDrv.fullName,
      ownerRole: 'Tài xế (Nạp ký quỹ)',
      amount: amount,
      bankName: bankName,
      accountMasked: accountMasked,
      status: 'Đã nạp ký quỹ',
    );
    _pushRealtimeNotification(
      category: 'Hệ thống',
      title:
          'Đã nạp ${amount.toStringAsFixed(0)}đ vào Ví ký quỹ Tài xế ${activeDrv.fullName}.',
      targetGroup: 'Tài xế',
      recipientKey: activeDrv.id,
    );
    _persistMutation('TOP_UP_DRIVER_WALLET', {
      'driverId': activeDrv.id,
      'amount': amount,
    });
    _notifyStoreChanged();
    return true;
  }

  bool requestWithdrawal({
    required String ownerName,
    required String ownerRole,
    required double amount,
    required String bankName,
    required String accountMasked,
  }) {
    if (amount <= 0) return false;
    final cleanAccount = accountMasked.trim();
    if (cleanAccount.isEmpty || cleanAccount.contains('Chưa liên kết')) {
      return false;
    }
    String resolvedOwnerId = '';
    if (ownerRole == 'Tài xế') {
      final targetDrv =
          drivers
              .where(
                (d) =>
                    d.fullName.trim().toLowerCase() ==
                    ownerName.trim().toLowerCase(),
              )
              .firstOrNull ??
          activeDriverRecord;
      final currentBal = targetDrv?.walletBalance ?? driverWalletBalance;
      if (currentBal - amount < 200000) return false;
      if (targetDrv != null) {
        targetDrv.walletBalance = currentBal - amount;
        resolvedOwnerId = targetDrv.id;
        if (targetDrv.id == activeDriverId ||
            targetDrv.fullName.trim().toLowerCase() ==
                activeDriverName.trim().toLowerCase()) {
          driverWalletBalance = targetDrv.walletBalance;
        }
        _sqliteDb.updateRows(
          'drivers',
          {'wallet_balance': targetDrv.walletBalance},
          where: 'id = ?',
          whereArgs: [targetDrv.id],
        );
      } else {
        driverWalletBalance -= amount;
      }
    } else {
      final targetMer =
          merchantApplicants
              .where(
                (m) =>
                    m.storeName.trim().toLowerCase() ==
                    ownerName.trim().toLowerCase(),
              )
              .firstOrNull ??
          activeMerchantRecord;
      final currentCod = targetMer?.codBalance ?? merchantCodBalance;
      if (currentCod < amount) return false;
      if (targetMer != null) {
        targetMer.codBalance = currentCod - amount;
        resolvedOwnerId = targetMer.id;
        if (targetMer.id == activeMerchantRecord?.id ||
            targetMer.storeName.trim().toLowerCase() ==
                merchantStoreName.trim().toLowerCase()) {
          merchantCodBalance = targetMer.codBalance;
        }
        _sqliteDb.updateRows(
          'merchants',
          {'cod_balance': targetMer.codBalance},
          where: 'id = ?',
          whereArgs: [targetMer.id],
        );
      } else {
        merchantCodBalance -= amount;
      }
    }
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final req = WithdrawalRequestRecord(
      id: 'WD-${now.millisecondsSinceEpoch}-${withdrawalRequests.length + 1}',
      ownerId: resolvedOwnerId,
      ownerName: ownerName,
      ownerRole: ownerRole,
      amount: amount,
      bankName: bankName,
      accountMasked: accountMasked,
      requestDate: dateStr,
      status: 'Chờ duyệt',
    );
    withdrawalRequests.insert(0, req);
    _sqliteDb.upsertRow('wallets_and_transactions', {
      'id': req.id,
      'owner_id': req.ownerId,
      'owner_name': req.ownerName,
      'owner_role': req.ownerRole,
      'amount': req.amount,
      'bank_name': req.bankName,
      'account_masked': req.accountMasked,
      'request_date': req.requestDate,
      'status': req.status,
      'created_at_ms': now.millisecondsSinceEpoch,
    });
    if (resolvedOwnerId.isNotEmpty) {
      _sqliteDb.upsertEntityRecord(
        tableName: 'withdrawal_meta',
        recordId: req.id,
        payload: {'ownerId': resolvedOwnerId},
      );
    }
    _persistMutation('REQUEST_WITHDRAWAL', {
      'ownerId': resolvedOwnerId,
      'ownerRole': ownerRole,
      'amount': amount,
    });
    _notifyStoreChanged();
    return true;
  }

  void updateWithdrawalStatus(String id, String status) {
    if (!hasAdminPermission('Tài chính: Thanh toán')) return;
    final req = withdrawalRequests.where((w) => w.id == id).firstOrNull;
    if (req != null && req.status == 'Chờ duyệt') {
      final previousStatus = req.status;
      req.status = status;
      String? targetRecipientKey = req.ownerId.isNotEmpty ? req.ownerId : null;
      if (previousStatus == 'Chờ duyệt' && status == 'Từ chối') {
        if (req.ownerRole == 'Tài xế') {
          final targetDrv =
              (req.ownerId.isNotEmpty
                  ? drivers.where((d) => d.id == req.ownerId).firstOrNull
                  : null) ??
              drivers
                  .where(
                    (d) =>
                        d.fullName.trim().toLowerCase() ==
                        req.ownerName.trim().toLowerCase(),
                  )
                  .firstOrNull;
          if (targetDrv != null) {
            targetRecipientKey = targetDrv.id;
            targetDrv.walletBalance += req.amount;
            if (targetDrv.id == activeDriverId ||
                targetDrv.fullName.trim().toLowerCase() ==
                    activeDriverName.trim().toLowerCase()) {
              driverWalletBalance = targetDrv.walletBalance;
            }
            _sqliteDb.updateRows(
              'drivers',
              {'wallet_balance': targetDrv.walletBalance},
              where: 'id = ?',
              whereArgs: [targetDrv.id],
            );
            _recordWalletLedgerEntry(
              idPrefix: 'REFUND',
              ownerId: targetDrv.id,
              ownerName: targetDrv.fullName,
              ownerRole: 'Tài xế (Hoàn ví rút tiền)',
              amount: req.amount,
              bankName: 'Hoàn từ lệnh rút ${req.id} bị từ chối',
              accountMasked: targetDrv.id,
              status: 'Đã cộng ví',
            );
          } else if (req.ownerName.trim().toLowerCase() ==
              activeDriverName.trim().toLowerCase()) {
            driverWalletBalance += req.amount;
          }
        } else {
          final targetMer =
              (req.ownerId.isNotEmpty
                  ? merchantApplicants
                        .where((m) => m.id == req.ownerId)
                        .firstOrNull
                  : null) ??
              merchantApplicants
                  .where(
                    (m) =>
                        m.storeName.trim().toLowerCase() ==
                        req.ownerName.trim().toLowerCase(),
                  )
                  .firstOrNull;
          if (targetMer != null) {
            targetRecipientKey = targetMer.id;
            targetMer.codBalance += req.amount;
            if (targetMer.id == activeMerchantRecord?.id ||
                targetMer.storeName.trim().toLowerCase() ==
                    merchantStoreName.trim().toLowerCase()) {
              merchantCodBalance = targetMer.codBalance;
            }
            _sqliteDb.updateRows(
              'merchants',
              {'cod_balance': targetMer.codBalance},
              where: 'id = ?',
              whereArgs: [targetMer.id],
            );
          } else if (req.ownerName.trim().toLowerCase() ==
              merchantStoreName.trim().toLowerCase()) {
            merchantCodBalance += req.amount;
          }
        }
      }
      _sqliteDb.updateRows(
        'wallets_and_transactions',
        {'status': status},
        where: 'id = ?',
        whereArgs: [id],
      );
      _pushRealtimeNotification(
        category: 'Hệ thống',
        title:
            'Lệnh rút tiền ${req.id} (${req.amount.toStringAsFixed(0)}đ • ${req.bankName}) đã chuyển sang trạng thái: $status.',
        targetGroup: req.ownerRole == 'Tài xế' ? 'Tài xế' : 'Cửa hàng B2B',
        recipientKey: targetRecipientKey,
      );
      _persistMutation('UPDATE_WITHDRAWAL', {'id': id, 'status': status});
      _notifyStoreChanged();
    }
  }

  void updateDriverApproval(String id, String status) {
    if (!hasAdminPermission('Tài xế: Phê duyệt')) return;
    final drv = drivers.where((d) => d.id == id).firstOrNull;
    if (drv != null) {
      drv.approvalStatus = status;
      drv.isOnline = status == 'Đã duyệt' && drv.walletBalance >= 200000;
      if (drv.id == activeDriverId ||
          (activeAuthenticatedUser != null &&
              _normalizePhone(activeAuthenticatedUser!.phone) ==
                  _normalizePhone(drv.phone))) {
        if (status == 'Đã duyệt') {
          activeDriverId = drv.id;
          activeDriverName = drv.fullName;
          activeDriverPhone = drv.phone;
          driverWalletBalance = drv.walletBalance;
        }
        isDriverOnline = drv.isOnline;
      }
      _sqliteDb.updateRows(
        'drivers',
        {'approval_status': status, 'is_online': drv.isOnline ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      final user = findUserByPhone(drv.phone);
      if (user != null && user.role != SubsystemRole.admin) {
        if (status == 'Đã duyệt') {
          user.role = SubsystemRole.driver;
        } else if (status == 'Từ chối' && user.role == SubsystemRole.driver) {
          final hasApprovedShop = merchantApplicants.any(
            (m) =>
                _normalizePhone(m.ownerPhone) == _normalizePhone(user.phone) &&
                m.approvalStatus == 'Đã duyệt',
          );
          user.role = hasApprovedShop
              ? SubsystemRole.merchant
              : SubsystemRole.customer;
        }
        _sqliteDb.updateRows(
          'users',
          {'role': user.roleDbCode},
          where: 'id = ?',
          whereArgs: [user.id],
        );
      }
      _pushRealtimeNotification(
        category: 'Hệ thống',
        title:
            'Hồ sơ Tài xế ${drv.fullName} (${drv.id} • ${drv.licensePlate}) đã chuyển sang trạng thái: $status.',
        targetGroup: 'Tài xế',
        recipientKey: drv.id,
      );
      _persistMutation('UPDATE_DRIVER_APPROVAL', {'id': id, 'status': status});
      _notifyStoreChanged();
    }
  }

  bool suspendOrUnsuspendDriver(String driverId) {
    if (!hasAdminPermission('Tài xế: Đình chỉ')) return false;
    final drv = drivers.where((d) => d.id == driverId).firstOrNull;
    if (drv == null) return false;
    final isSuspended = drv.approvalStatus == 'Đình chỉ';
    final nextStatus = isSuspended ? 'Đã duyệt' : 'Đình chỉ';
    drv.approvalStatus = nextStatus;
    drv.isOnline = nextStatus == 'Đã duyệt' && drv.walletBalance >= 200000;
    if (drv.id == activeDriverId) {
      isDriverOnline = drv.isOnline;
    }
    _sqliteDb.updateRows(
      'drivers',
      {'approval_status': nextStatus, 'is_online': drv.isOnline ? 1 : 0},
      where: 'id = ?',
      whereArgs: [driverId],
    );
    _pushRealtimeNotification(
      category: 'Hệ thống',
      title: nextStatus == 'Đình chỉ'
          ? 'Tài khoản đối tác Tài xế ${drv.fullName} (${drv.licensePlate}) đã bị tạm đình chỉ hoạt động.'
          : 'Tài khoản đối tác Tài xế ${drv.fullName} (${drv.licensePlate}) đã được khôi phục hoạt động.',
      targetGroup: 'Tài xế',
      recipientKey: drv.id,
    );
    _persistMutation('SUSPEND_DRIVER_TOGGLE', {
      'table': 'drivers',
      'id': driverId,
      'status': nextStatus,
      'record': <String, Object?>{
        'id': drv.id,
        'phone': drv.phone,
        'full_name': drv.fullName,
        'citizen_id': drv.citizenId,
        'license_plate': drv.licensePlate,
        'vehicle_type': drv.vehicleType,
        'is_online': drv.isOnline,
        'latitude': drv.location.latitude,
        'longitude': drv.location.longitude,
        'rating': drv.rating,
        'rejected_count': drv.rejectedCount,
        'bank_name': drv.bankName,
        'bank_account': drv.bankAccount,
        'approval_status': nextStatus,
        'wallet_balance': drv.walletBalance,
      },
    });
    _notifyStoreChanged();
    return true;
  }

  bool adminUpdateDriverVehicleInfo({
    required String driverId,
    required String vehicleType,
    required String licensePlate,
  }) {
    if (!hasAdminPermission('Tài xế: Chỉnh sửa')) return false;
    final drv = drivers.where((d) => d.id == driverId).firstOrNull;
    if (drv == null ||
        vehicleType.trim().isEmpty ||
        licensePlate.trim().isEmpty) {
      return false;
    }
    drv.vehicleType = vehicleType.trim();
    drv.licensePlate = licensePlate.trim();
    _sqliteDb.updateRows(
      'drivers',
      {'vehicle_type': drv.vehicleType, 'license_plate': drv.licensePlate},
      where: 'id = ?',
      whereArgs: [driverId],
    );
    final drvNameLower = drv.fullName.trim().toLowerCase();
    for (final ord in orders) {
      if (ord.status != OrderStatus.delivered &&
          ord.status != OrderStatus.cancelled &&
          ord.paymentStatus != 'RETURNED' &&
          ord.assignedDriverName != null &&
          ord.assignedDriverName!.trim().toLowerCase() == drvNameLower) {
        ord.assignedDriverPlate = drv.licensePlate;
        _sqliteDb.updateRows(
          'orders',
          {'assigned_driver_plate': drv.licensePlate},
          where: 'id = ?',
          whereArgs: [ord.id],
        );
      }
    }
    _persistMutation('ADMIN_UPDATE_DRIVER_VEHICLE', {
      'id': driverId,
      'vehicleType': drv.vehicleType,
      'licensePlate': drv.licensePlate,
    });
    _notifyStoreChanged();
    return true;
  }

  void updateMerchantApproval(String id, String status) {
    if (!hasAdminPermission('Tài xế: Phê duyệt')) return;
    final mer = merchantApplicants.where((m) => m.id == id).firstOrNull;
    if (mer != null) {
      mer.approvalStatus = status;
      _sqliteDb.updateRows(
        'merchants',
        {'approval_status': status},
        where: 'id = ?',
        whereArgs: [id],
      );
      final user = findUserByPhone(mer.ownerPhone);
      if (user != null && user.role != SubsystemRole.admin) {
        if (status == 'Đã duyệt') {
          user.role = SubsystemRole.merchant;
          if (activeAuthenticatedUser == null ||
              _normalizePhone(activeAuthenticatedUser!.phone) ==
                  _normalizePhone(mer.ownerPhone)) {
            merchantStoreName = mer.storeName;
            merchantBusinessType = mer.businessType;
            merchantTaxCode = mer.taxCode;
            merchantRepresentative = mer.representativeName;
            merchantOpenHours = mer.openHours;
            merchantBankName = mer.bankName;
            merchantBankAccount = mer.bankAccount;
            merchantCodBalance = mer.codBalance;
          }
        } else if (status == 'Từ chối' && user.role == SubsystemRole.merchant) {
          final hasApprovedDrv = drivers.any(
            (d) =>
                _normalizePhone(d.phone) == _normalizePhone(user.phone) &&
                d.approvalStatus == 'Đã duyệt',
          );
          user.role = hasApprovedDrv
              ? SubsystemRole.driver
              : SubsystemRole.customer;
        }
        _sqliteDb.updateRows(
          'users',
          {'role': user.roleDbCode},
          where: 'id = ?',
          whereArgs: [user.id],
        );
      }
      _pushRealtimeNotification(
        category: 'Hệ thống',
        title:
            'Hồ sơ Cửa hàng B2B ${mer.storeName} (${mer.id}) đã chuyển sang trạng thái: $status.',
        targetGroup: 'Cửa hàng B2B',
        recipientKey: mer.id,
      );
      _persistMutation('UPDATE_MERCHANT_APPROVAL', {
        'id': id,
        'status': status,
      });
      _notifyStoreChanged();
    }
  }

  void addIncidentOrComplaint({
    required String orderId,
    required String reporterName,
    required String issueType,
    required String description,
    List<String> evidenceFiles = const [],
  }) {
    final ord = orders.where((o) => o.trackingCode == orderId).firstOrNull;
    final resolvedDriverName =
        ord?.assignedDriverName ??
        (reporterName.startsWith('Tài xế')
            ? activeDriverName
            : 'Chưa gán tài xế');
    final item = ComplaintTicketRecord(
      ticketCode: 'KN-00${complaints.length + 1}',
      orderId: orderId,
      customerName: reporterName,
      driverName: resolvedDriverName,
      issueType: issueType,
      description: description,
      status: 'Mới',
      replies: ['$reporterName: $description'],
      evidenceFiles: List<String>.from(evidenceFiles),
    );
    complaints.insert(0, item);
    _sqliteDb.upsertRow('incidents_and_complaints', {
      'ticket_code': item.ticketCode,
      'order_id': item.orderId,
      'customer_name': item.customerName,
      'driver_name': item.driverName,
      'issue_type': item.issueType,
      'description': item.description,
      'status': item.status,
      'replies_json': jsonEncode(item.replies),
      'evidence_files_json': jsonEncode(item.evidenceFiles),
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    if (item.evidenceFiles.isNotEmpty) {
      _sqliteDb.upsertEntityRecord(
        tableName: 'complaint_meta',
        recordId: item.ticketCode,
        payload: {'evidenceFiles': item.evidenceFiles},
      );
    }
    if (reporterName.startsWith('Tài xế') &&
        (issueType == 'Hàng bị hỏng' ||
            issueType == 'Khách không nhận hàng' ||
            issueType == 'Sai địa chỉ giao' ||
            issueType == 'Tai nạn / Xe hỏng')) {
      final ord = orders.where((o) => o.trackingCode == orderId).firstOrNull;
      if (ord != null && ord.status.canTransitionTo(OrderStatus.failed)) {
        ord.status = OrderStatus.failed;
        ord.cancelReason = '$issueType: $description';
        _sqliteDb.updateRows(
          'orders',
          {'status': ord.status.name, 'cancel_reason': ord.cancelReason},
          where: 'tracking_code = ?',
          whereArgs: [orderId],
        );
        _dispatchMerchantOrderWebhookIfConfigured(
          ord,
          eventName: 'ORDER_DELIVERY_FAILED',
        );
      }
    }
    _persistMutation('ADD_COMPLAINT', {'orderId': orderId});
    _notifyStoreChanged();
  }

  void replyComplaint(String ticketCode, String replyText, String nextStatus) {
    if (!hasAdminPermission('Khiếu nại: Xử lý')) return;
    final item = complaints
        .where((c) => c.ticketCode == ticketCode)
        .firstOrNull;
    if (item != null) {
      final wasResolved = item.status == 'Đã giải quyết';
      if (wasResolved && nextStatus != 'Đã giải quyết') {
        return;
      }
      item.status = nextStatus;
      if (replyText.trim().isNotEmpty) {
        item.replies.add('Admin: ${replyText.trim()}');
      }
      String targetNotiGroup = 'Khách hàng';
      String? targetNotiRecipient = item.customerName;
      if (item.customerName.startsWith('Tài xế')) {
        targetNotiGroup = 'Tài xế';
        final drv = drivers
            .where((d) => item.customerName.contains(d.fullName))
            .firstOrNull;
        targetNotiRecipient = drv?.id;
      }

      final alreadyCompensated = item.replies.any(
        (r) =>
            r.startsWith('Hệ thống: Đã cộng ') ||
            r.startsWith('Hệ thống: Đã cấp mã bồi thường '),
      );
      if (!wasResolved &&
          !alreadyCompensated &&
          nextStatus == 'Đã giải quyết') {
        final lowerIssue = item.issueType.toLowerCase();
        final isCompensableIssue =
            lowerIssue.contains('hỏng') ||
            lowerIssue.contains('mất') ||
            lowerIssue.contains('thiếu') ||
            lowerIssue.contains('cod') ||
            lowerIssue.contains('sai phí') ||
            lowerIssue.contains('sai cước');
        if (isCompensableIssue) {
          final relatedOrder = orders
              .where((o) => o.trackingCode == item.orderId)
              .firstOrNull;
          final compensation =
              relatedOrder != null && relatedOrder.codAmount > 0
              ? (relatedOrder.codAmount * 0.20).clamp(50000.0, 500000.0)
              : 100000.0;
          final reporterHint = item.customerName.trim().toLowerCase();
          final fallbackOrderHint =
              (relatedOrder?.customerName ?? '').trim().toLowerCase();
          MerchantApplicantRecord? findMerchantByHint(String hint) {
            if (hint.isEmpty) return null;
            return merchantApplicants
                .where(
                  (m) =>
                      m.storeName.trim().toLowerCase() == hint ||
                      m.representativeName.trim().toLowerCase() == hint,
                )
                .firstOrNull;
          }

          final matchedMer = findMerchantByHint(reporterHint) ??
              (item.issueType.startsWith('Shop KN') || reporterHint.isEmpty
                  ? findMerchantByHint(fallbackOrderHint)
                  : null);
          final isMerchantComplaint =
              matchedMer != null || item.issueType.startsWith('Shop KN');
          if (isMerchantComplaint) {
            final targetMer = matchedMer ?? activeMerchantRecord;
            targetNotiGroup = 'Cửa hàng B2B';
            targetNotiRecipient = targetMer?.id;
            if (targetMer != null) {
              targetMer.codBalance += compensation;
              if (targetMer.id == activeMerchantRecord?.id ||
                  targetMer.storeName.trim().toLowerCase() ==
                      merchantStoreName.trim().toLowerCase()) {
                merchantCodBalance = targetMer.codBalance;
              }
              _sqliteDb.updateRows(
                'merchants',
                {'cod_balance': targetMer.codBalance},
                where: 'id = ?',
                whereArgs: [targetMer.id],
              );
            }
            item.replies.add(
              'Hệ thống: Đã cộng ${compensation.toStringAsFixed(0)}đ tiền bồi thường vào ví đối soát.',
            );
          } else {
            final cleanTicketSuffix = item.ticketCode.toUpperCase().replaceAll(
              RegExp(r'[^A-Z0-9]'),
              '',
            );
            final compVoucherCode = 'COMP$cleanTicketSuffix';
            _upsertVoucherInternal(
              code: compVoucherCode,
              title: 'Voucher bồi thường sự cố đơn ${item.orderId}',
              discountValue: 50000,
              isPercentage: false,
              minOrderValue: 0,
              usageLimit: 1,
              expiryDate: '31/12/2027',
            );
            item.replies.add(
              'Hệ thống: Đã cấp mã bồi thường $compVoucherCode (50.000đ) cho khách hàng ${item.customerName}.',
            );
          }
        } else {
          item.replies.add(
            'Hệ thống: Đã xác nhận xử lý và đóng hồ sơ sự cố/khiếu nại.',
          );
        }
      }
      _sqliteDb.updateRows(
        'incidents_and_complaints',
        {'status': item.status, 'replies_json': jsonEncode(item.replies)},
        where: 'ticket_code = ?',
        whereArgs: [ticketCode],
      );
      _persistMutation('REPLY_COMPLAINT', {'ticketCode': ticketCode});
      _pushRealtimeNotification(
        category: 'Hệ thống',
        title:
            'Khiếu nại ${item.ticketCode} (Đơn ${item.orderId}) đã chuyển sang trạng thái: ${item.status}.',
        targetGroup: targetNotiGroup,
        recipientKey: targetNotiRecipient,
      );
      _notifyStoreChanged();
    }
  }

  void broadcastSystemNotification({
    required String title,
    required String targetGroup,
  }) {
    if (!hasAdminPermission('Hệ thống: Cài đặt')) return;
    if (title.trim().isEmpty) return;
    final noti = NotificationRecord(
      id: 'NOTI-${DateTime.now().millisecondsSinceEpoch}-${notifications.length + 1}',
      category: 'Hệ thống',
      title: title.trim(),
      targetGroup: targetGroup,
      timeAgo: 'Vừa xong',
    );
    notifications.insert(0, noti);
    _sqliteDb.upsertRow('chat_messages_and_notifications', {
      'id': noti.id,
      'record_type': 'NOTIFICATION',
      'order_id': null,
      'recipient_key': null,
      'sender_name': 'Hệ thống',
      'is_customer': 0,
      'category': noti.category,
      'title': noti.title,
      'content': noti.title,
      'target_group': noti.targetGroup,
      'time_label': noti.timeAgo,
      'is_read': 0,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    _persistMutation('BROADCAST_NOTIFICATION', {'title': title});
    _notifyStoreChanged();
  }

  void toggleRbacPermission(String roleName, String permKey, bool value) {
    if (!hasAdminPermission('Hệ thống: Bảo mật')) return;
    if (roleName == 'Super Admin' && permKey == 'Hệ thống: Bảo mật' && !value) {
      return;
    }
    final role = rbacRoles.where((r) => r.roleName == roleName).firstOrNull;
    if (role != null) {
      role.permissions[permKey] = value;
      _sqliteDb.updateRows(
        'admin_roles_permissions',
        {
          'permissions_json': jsonEncode(role.permissions),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'role_name = ?',
        whereArgs: [roleName],
      );
      _persistMutation('TOGGLE_RBAC', {
        'roleName': roleName,
        'permKey': permKey,
      });
      _notifyStoreChanged();
    }
  }

  void toggleGeofenceZone(String id, bool active) {
    if (!hasAdminPermission('Hệ thống: Cài đặt')) return;
    final z = geofenceZones.where((g) => g.id == id).firstOrNull;
    if (z != null) {
      z.isActive = active;
      _sqliteDb.updateRows(
        'geofence_zones',
        {'is_active': active ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      _persistMutation('TOGGLE_GEOFENCE', {'id': id, 'active': active});
      _notifyStoreChanged();
    }
  }

  void toggleCustomerSocialLink({
    required String provider,
    required bool linked,
  }) {
    if (provider.toUpperCase() == 'GOOGLE') {
      isCustomerGoogleLinked = linked;
    } else {
      isCustomerTwoFactorEnabled = linked;
    }
    final normPhone = _normalizePhone(
      activeAuthenticatedUser?.phone ?? customerPhone,
    );
    if (normPhone.isNotEmpty) {
      final prefs = Map<String, dynamic>.from(
        userPreferencesByPhone[normPhone] ?? const <String, dynamic>{},
      );
      prefs['gender'] = prefs['gender'] ?? customerGender;
      prefs['avatarBadgeIndex'] =
          prefs['avatarBadgeIndex'] ?? customerAvatarBadgeIndex;
      prefs['googleLinked'] = isCustomerGoogleLinked;
      prefs['twoFactorEnabled'] = isCustomerTwoFactorEnabled;
      userPreferencesByPhone[normPhone] = prefs;
      _sqliteDb.upsertEntityRecord(
        tableName: 'user_preferences',
        recordId: normPhone,
        payload: prefs,
      );
    }
    _persistMutation('TOGGLE_SOCIAL_LINK', {
      'provider': provider,
      'linked': linked,
    });
    _notifyStoreChanged();
  }

  void markAllNotificationsAsRead({String? targetGroupScope}) {
    final List<NotificationRecord> scoped;
    if (targetGroupScope == 'Khách hàng') {
      scoped = customerNotifications;
    } else if (targetGroupScope == 'Tài xế') {
      scoped = driverNotifications;
    } else if (targetGroupScope == 'Cửa hàng B2B') {
      scoped = merchantNotifications;
    } else {
      scoped = notifications;
    }
    int updatedCount = 0;
    for (final n in scoped) {
      if (!n.isRead) {
        n.isRead = true;
        updatedCount++;
        _sqliteDb.updateRows(
          'chat_messages_and_notifications',
          {'is_read': 1},
          where: 'id = ?',
          whereArgs: [n.id],
        );
      }
    }
    if (updatedCount > 0) {
      _persistMutation('MARK_ALL_NOTIFICATIONS_READ', {
        'scope': targetGroupScope ?? 'ALL',
        'count': updatedCount,
      });
      _notifyStoreChanged();
    }
  }

  void markNotificationAsRead(String id) {
    final target = notifications.where((n) => n.id == id).firstOrNull;
    if (target == null || target.isRead) return;
    target.isRead = true;
    _sqliteDb.updateRows(
      'chat_messages_and_notifications',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    _persistMutation('MARK_NOTIFICATION_READ', {'id': id});
    _notifyStoreChanged();
  }

  PickupWarehouseRecord addMerchantWarehouse({
    required String name,
    required String address,
    String? contactName,
    String? contactPhone,
    String? openHours,
    bool? isPrimary,
    GeoPoint? customLocation,
  }) {
    final targetMer =
        activeMerchantRecord ??
        (activeAuthenticatedUser == null
            ? merchantApplicants.firstOrNull
            : null);
    final targetMerId = targetMer?.id ?? 'MER-01';
    final pt =
        customLocation ??
        SmartDispatchEngine.resolveAddressToCoordinate(
          address,
          fallback: const GeoPoint(latitude: 10.7765, longitude: 106.6920),
        );
    final hasExistingForMer = merchantWarehouses.any(
      (w) => w.merchantId == targetMerId,
    );
    final effectivePrimary = !hasExistingForMer ? true : (isPrimary ?? false);
    if (effectivePrimary) {
      for (var i = 0; i < merchantWarehouses.length; i++) {
        final prev = merchantWarehouses[i];
        if (prev.merchantId == targetMerId && prev.isPrimary) {
          merchantWarehouses[i] = PickupWarehouseRecord(
            id: prev.id,
            merchantId: prev.merchantId,
            name: prev.name,
            address: prev.address,
            location: prev.location,
            contactName: prev.contactName,
            contactPhone: prev.contactPhone,
            openHours: prev.openHours,
            isPrimary: false,
            webhookUrl: prev.webhookUrl,
          );
          _sqliteDb.updateRows(
            'merchant_pickup_points',
            {'is_primary': 0},
            where: 'id = ?',
            whereArgs: [prev.id],
          );
          _sqliteDb.upsertEntityRecord(
            tableName: 'warehouse_meta',
            recordId: prev.id,
            payload: {
              'isPrimary': false,
              'webhookUrl': prev.webhookUrl,
              'contactName': prev.contactName,
              'contactPhone': prev.contactPhone,
              'openHours': prev.openHours,
            },
          );
        }
      }
    }
    final wh = PickupWarehouseRecord(
      id: allocateUniqueId('WH-', merchantWarehouses.map((w) => w.id)),
      merchantId: targetMerId,
      name: name.trim(),
      address: address.trim(),
      location: pt,
      contactName: (contactName != null && contactName.trim().isNotEmpty)
          ? contactName.trim()
          : (targetMer?.representativeName ?? merchantRepresentative),
      contactPhone: (contactPhone != null && contactPhone.trim().isNotEmpty)
          ? contactPhone.trim()
          : (targetMer?.ownerPhone ?? '0909112233'),
      openHours: (openHours != null && openHours.trim().isNotEmpty)
          ? openHours.trim()
          : (targetMer?.openHours ?? '08:00 - 21:00'),
      isPrimary: effectivePrimary,
      webhookUrl: targetMer?.webhookUrl ?? '',
    );
    merchantWarehouses.add(wh);
    _sqliteDb.upsertRow('merchant_pickup_points', {
      'id': wh.id,
      'merchant_id': targetMerId,
      'warehouse_name': wh.name,
      'full_address': wh.address,
      'latitude': wh.location.latitude,
      'longitude': wh.location.longitude,
      'contact_phone': wh.contactPhone,
      'open_hours': wh.openHours,
      'is_primary': wh.isPrimary ? 1 : 0,
      'webhook_url': wh.webhookUrl,
      'created_at': DateTime.now().toIso8601String(),
    });
    _sqliteDb.upsertEntityRecord(
      tableName: 'warehouse_meta',
      recordId: wh.id,
      payload: {
        'isPrimary': wh.isPrimary,
        'webhookUrl': wh.webhookUrl,
        'contactName': wh.contactName,
        'contactPhone': wh.contactPhone,
        'openHours': wh.openHours,
      },
    );
    _persistMutation('ADD_MERCHANT_WAREHOUSE', {
      'id': wh.id,
      'merchantId': targetMerId,
      'name': wh.name,
      'address': wh.address,
    });
    _notifyStoreChanged();
    return wh;
  }

  bool deleteMerchantWarehouse(String warehouseId) {
    final personalList = merchantPersonalWarehouses;
    if (personalList.length <= 1) return false;
    final targetMerId = activeMerchantRecord?.id;
    final targetWh = merchantWarehouses
        .where((w) => w.id == warehouseId)
        .firstOrNull;
    if (targetWh == null) return false;
    if (targetMerId != null && targetWh.merchantId != targetMerId) {
      return false;
    }
    merchantWarehouses.removeWhere((w) => w.id == warehouseId);
    if (targetWh.isPrimary) {
      final nextWh = merchantWarehouses
          .where((w) => targetMerId == null || w.merchantId == targetMerId)
          .firstOrNull;
      if (nextWh != null) {
        final idx = merchantWarehouses.indexOf(nextWh);
        if (idx >= 0) {
          merchantWarehouses[idx] = PickupWarehouseRecord(
            id: nextWh.id,
            merchantId: nextWh.merchantId,
            name: nextWh.name,
            address: nextWh.address,
            location: nextWh.location,
            contactPhone: nextWh.contactPhone,
            openHours: nextWh.openHours,
            isPrimary: true,
            webhookUrl: nextWh.webhookUrl,
          );
          _sqliteDb.updateRows(
            'merchant_pickup_points',
            {'is_primary': 1},
            where: 'id = ?',
            whereArgs: [nextWh.id],
          );
          _sqliteDb.upsertEntityRecord(
            tableName: 'warehouse_meta',
            recordId: nextWh.id,
            payload: {
              'isPrimary': true,
              'webhookUrl': nextWh.webhookUrl,
              'contactPhone': nextWh.contactPhone,
              'openHours': nextWh.openHours,
            },
          );
        }
      }
    }
    _sqliteDb.deleteRows(
      'merchant_pickup_points',
      where: 'id = ?',
      whereArgs: [warehouseId],
    );
    _sqliteDb.deleteRows(
      'local_relational_entities',
      where: 'table_name = ? AND record_id = ?',
      whereArgs: ['warehouse_meta', warehouseId],
    );
    _persistMutation('DELETE_MERCHANT_WAREHOUSE', {'id': warehouseId});
    _notifyStoreChanged();
    return true;
  }

  void setDefaultCustomerAddress(String addressText) {
    final cleanAddr = addressText.trim();
    if (cleanAddr.isEmpty) return;
    customerDefaultAddress = cleanAddr;
    final resolvedLoc = SmartDispatchEngine.resolveAddressToCoordinate(
      cleanAddr,
      fallback: activeDriverLocation,
    );
    final activeUser = activeAuthenticatedUser;
    if (activeUser != null) {
      activeUser.defaultAddress = cleanAddr;
      activeUser.defaultLocation = resolvedLoc;
      _sqliteDb.updateRows(
        'users',
        {
          'default_address': cleanAddr,
          'default_lat': resolvedLoc.latitude,
          'default_lng': resolvedLoc.longitude,
        },
        where: 'id = ?',
        whereArgs: [activeUser.id],
      );
    }
    _persistMutation('SET_DEFAULT_CUSTOMER_ADDRESS', {'address': cleanAddr});
    _notifyStoreChanged();
  }

  bool updateExistingOrderDetails({
    required String trackingCode,
    required String recipientName,
    required String recipientPhone,
    required String dropoffAddress,
    required double codAmount,
  }) {
    if (activeAuthenticatedUser?.role == SubsystemRole.admin &&
        !hasAdminPermission('Đơn: Sửa')) {
      return false;
    }
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return false;
    if (ord.status == OrderStatus.delivered ||
        ord.status == OrderStatus.cancelled ||
        ord.status == OrderStatus.returning ||
        ord.paymentStatus == 'RETURNED') {
      return false;
    }
    final candidateDropoffPt = SmartDispatchEngine.resolveAddressToCoordinate(
      dropoffAddress.trim(),
      fallback: ord.dropoffLocation,
    );
    if (findActiveRestrictedZoneForRoute(
          ord.pickupLocation,
          candidateDropoffPt,
        ) !=
        null) {
      return false;
    }
    ord.recipientName = recipientName.trim();
    ord.recipientPhone = recipientPhone.trim();
    ord.dropoffAddress = dropoffAddress.trim();
    ord.dropoffLocation = candidateDropoffPt;
    final newAirMeters = GeoMath.distanceMeters(
      ord.pickupLocation,
      ord.dropoffLocation,
    );
    ord.distanceMeters = (newAirMeters * 1.28).round().clamp(1200, 45000);
    ord.durationSeconds = ((ord.distanceMeters / 1000.0) * 180).round();
    ord.codAmount = codAmount;

    double geofenceFee = computeGeofenceSurchargeForPoint(ord.dropoffLocation);
    if (isWeatherSurchargeActive) {
      geofenceFee += badWeatherSurchargeConfig;
    }
    if (ord.weightKg > 5.0) {
      geofenceFee += ((ord.weightKg - 5.0) * 3000).roundToDouble();
    }
    if (ord.packageDescription.toLowerCase().contains('dễ vỡ')) {
      geofenceFee += 5000;
    }
    if (ord.packageDescription.toLowerCase().contains('giữ lạnh')) {
      geofenceFee += 10000;
    }
    final baseScale = (baseFareConfig / 25000.0).clamp(0.4, 5.0);
    final kmScale = (pricePerKmConfig / 5000.0).clamp(0.4, 5.0);
    final newEst = PricingEstimate.calculate(
      serviceType: ord.serviceType,
      distanceMeters: ord.distanceMeters,
      durationSeconds: ord.durationSeconds,
      isPeakHour: isPeakSurchargeActive,
      geofenceSurcharge: geofenceFee,
      voucherDiscount: ord.discountAmount,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
      configuredStandardPeakSurcharge: peakHourSurchargeConfig,
    );
    ord.deliveryFee = newEst.baseFare + newEst.distanceFare;
    ord.surchargeFee = newEst.surchargeFee;
    ord.totalAmount = newEst.totalAmount;

    _sqliteDb.updateRows(
      'orders',
      {
        'recipient_name': ord.recipientName,
        'recipient_phone': ord.recipientPhone,
        'dropoff_address': ord.dropoffAddress,
        'dropoff_lat': ord.dropoffLocation.latitude,
        'dropoff_lng': ord.dropoffLocation.longitude,
        'distance_meters': ord.distanceMeters,
        'duration_seconds': ord.durationSeconds,
        'delivery_fee': ord.deliveryFee,
        'surcharge_fee': ord.surchargeFee,
        'cod_amount': ord.codAmount,
        'total_amount': ord.totalAmount,
      },
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    if (ord.assignedDriverName != null &&
        ord.assignedDriverName!.trim().isNotEmpty) {
      final assignedDrv = drivers
          .where(
            (d) =>
                d.fullName.trim().toLowerCase() ==
                ord.assignedDriverName!.trim().toLowerCase(),
          )
          .firstOrNull;
      _pushRealtimeNotification(
        category: 'Đơn hàng',
        title:
            'Đơn ${ord.trackingCode} vừa cập nhật người nhận/địa chỉ giao: ${ord.recipientName} • ${ord.dropoffAddress}.',
        targetGroup: 'Tài xế',
        recipientKey: assignedDrv?.id ?? ord.assignedDriverName,
      );
    }
    _dispatchMerchantOrderWebhookIfConfigured(ord, eventName: 'ORDER_UPDATED');
    _persistMutation('UPDATE_ORDER_DETAILS', {
      'trackingCode': trackingCode,
      'recipientName': ord.recipientName,
      'codAmount': ord.codAmount,
    });
    _notifyStoreChanged();
    return true;
  }

  VoucherRecord? createNewVoucher({
    required String code,
    required String title,
    required double discountValue,
    required bool isPercentage,
    required double minOrderValue,
    double? maxDiscount,
    int usageLimit = 500,
    String expiryDate = '31/12/2027',
  }) {
    if (!hasAdminPermission('Hệ thống: Cài đặt')) return null;
    final record = _upsertVoucherInternal(
      code: code,
      title: title,
      discountValue: discountValue,
      isPercentage: isPercentage,
      minOrderValue: minOrderValue,
      maxDiscount: maxDiscount,
      usageLimit: usageLimit,
      expiryDate: expiryDate,
    );
    _notifyStoreChanged();
    return record;
  }

  VoucherRecord _upsertVoucherInternal({
    required String code,
    required String title,
    required double discountValue,
    required bool isPercentage,
    required double minOrderValue,
    double? maxDiscount,
    int usageLimit = 500,
    String expiryDate = '31/12/2027',
  }) {
    final cleanCode = code.trim().toUpperCase();
    final label = isPercentage
        ? 'Giảm ${discountValue.toStringAsFixed(0)}%'
        : 'Giảm ${(discountValue / 1000).toStringAsFixed(0)}k';
    final resolvedMax = maxDiscount != null && maxDiscount > 0
        ? maxDiscount
        : (isPercentage ? 30000.0 : discountValue);
    final record = VoucherRecord(
      code: cleanCode,
      title: title.trim(),
      discountLabel: label,
      discountValue: discountValue,
      isPercentage: isPercentage,
      maxDiscount: resolvedMax,
      minOrderValue: minOrderValue,
      expiryDate: expiryDate,
      status: 'Đang hoạt động',
      usageLimit: usageLimit,
      usedCount: 0,
    );
    vouchers.removeWhere((v) => v.code == cleanCode);
    vouchers.insert(0, record);
    _sqliteDb.upsertRow('vouchers', {
      'code': record.code,
      'title': record.title,
      'discount_label': record.discountLabel,
      'discount_value': record.discountValue,
      'is_percentage': record.isPercentage ? 1 : 0,
      'max_discount': record.maxDiscount,
      'min_order_value': record.minOrderValue,
      'expiry_date': record.expiryDate,
      'status': record.status,
      'usage_limit': record.usageLimit,
      'used_count': record.usedCount,
    });
    _sqliteDb.upsertEntityRecord(
      tableName: 'voucher_meta',
      recordId: record.code,
      payload: {'usageLimit': record.usageLimit, 'usedCount': record.usedCount},
    );
    _persistMutation('CREATE_VOUCHER', {'code': record.code});
    _pushRealtimeNotification(
      category: 'Khuyến mãi',
      title:
          'Mã ưu đãi mới ${record.code} (${record.discountLabel}): ${record.title} • HSD: ${record.expiryDate}.',
      targetGroup: 'Tất cả người dùng',
    );
    return record;
  }

  bool requeueOrReturnOrder(String trackingCode, {required bool isReturn}) {
    if (activeAuthenticatedUser?.role == SubsystemRole.admin &&
        !hasAdminPermission('Đơn: Sửa')) {
      return false;
    }
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return false;
    if (ord.status == OrderStatus.delivered ||
        ord.status == OrderStatus.cancelled ||
        ord.paymentStatus == 'RETURNED') {
      return false;
    }
    if (isReturn) {
      if (ord.status != OrderStatus.failed &&
          ord.status != OrderStatus.inTransit) {
        return false;
      }
      ord.status = OrderStatus.returning;
      ord.cancelReason = 'Hoàn hàng về điểm lấy theo yêu cầu Cửa hàng';
    } else {
      if (ord.status != OrderStatus.failed &&
          ord.status != OrderStatus.returning) {
        return false;
      }
      ord.status = ord.assignedDriverName != null
          ? OrderStatus.inTransit
          : OrderStatus.searching;
      ord.cancelReason = null;
    }
    _sqliteDb.updateRows(
      'orders',
      {'status': ord.status.name, 'cancel_reason': ord.cancelReason},
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _recordOrderStatusHistory(
      ord.id,
      ord.status,
      isReturn
          ? 'Yêu cầu hoàn hàng về kho cửa hàng'
          : 'Yêu cầu giao lại kiện hàng (${ord.status.displayName})',
    );
    if (ord.assignedDriverName != null &&
        ord.assignedDriverName!.trim().isNotEmpty) {
      final assignedDrv = drivers
          .where(
            (d) =>
                d.fullName.trim().toLowerCase() ==
                ord.assignedDriverName!.trim().toLowerCase(),
          )
          .firstOrNull;
      _pushRealtimeNotification(
        category: 'Đơn hàng',
        title: isReturn
            ? 'Đơn ${ord.trackingCode} chuyển sang Hoàn kho. Vui lòng hoàn trả về điểm lấy.'
            : 'Đơn ${ord.trackingCode} được yêu cầu Giao lại cho khách nhận.',
        targetGroup: 'Tài xế',
        recipientKey: assignedDrv?.id ?? ord.assignedDriverName,
      );
    }
    _dispatchMerchantOrderWebhookIfConfigured(
      ord,
      eventName: isReturn ? 'ORDER_RETURNING' : 'ORDER_REQUEUED',
    );
    _persistMutation(
      isReturn ? 'RETURN_ORDER_TO_WAREHOUSE' : 'REQUEUE_ORDER_DELIVERY',
      {'trackingCode': trackingCode, 'status': ord.status.name},
    );
    _notifyStoreChanged();
    return true;
  }

  bool toggleUserAccountStatus(String userId) {
    if (!hasAdminPermission('User: Khóa/Mở')) return false;
    final u = users.where((x) => x.id == userId).firstOrNull;
    if (u == null) return false;
    if (u.id == activeAuthenticatedUser?.id || u.id == 'USR-04') {
      return false;
    }
    if (u.role == SubsystemRole.admin &&
        !hasAdminPermission('Hệ thống: Bảo mật')) {
      return false;
    }
    u.status = u.status == 'ACTIVE' ? 'LOCKED' : 'ACTIVE';
    if (u.status == 'LOCKED') {
      final normUserPhone = _normalizePhone(u.phone);
      for (final d in drivers) {
        if (_normalizePhone(d.phone) == normUserPhone && d.isOnline) {
          d.isOnline = false;
          _sqliteDb.updateRows(
            'drivers',
            {'is_online': 0},
            where: 'id = ?',
            whereArgs: [d.id],
          );
          if (d.id == activeDriverId) {
            isDriverOnline = false;
          }
        }
      }
    }
    _sqliteDb.updateRows(
      'users',
      {'status': u.status},
      where: 'id = ?',
      whereArgs: [u.id],
    );
    _persistMutation('TOGGLE_USER_STATUS', {'id': u.id, 'status': u.status});
    _notifyStoreChanged();
    return true;
  }

  void toggleVoucherStatus(String code) {
    if (!hasAdminPermission('Hệ thống: Cài đặt')) return;
    final v = vouchers.where((x) => x.code == code).firstOrNull;
    if (v == null) return;
    v.status = v.status == 'Đang hoạt động' ? 'Tạm dừng' : 'Đang hoạt động';
    _sqliteDb.updateRows(
      'vouchers',
      {'status': v.status},
      where: 'code = ?',
      whereArgs: [v.code],
    );
    _persistMutation('TOGGLE_VOUCHER_STATUS', {
      'code': v.code,
      'status': v.status,
    });
    _notifyStoreChanged();
  }

  String exportReportFileToDisk({
    required String fileName,
    required String content,
    String mimeType = 'text/csv;charset=utf-8',
  }) {
    if (kIsWeb) {
      triggerBrowserFileDownload(
        fileName: fileName,
        content: content,
        mimeType: mimeType,
      );
      final virtualPath = 'localStorage://exports/$fileName';
      _sqliteDb.upsertEntityRecord(
        tableName: 'exported_reports',
        recordId: fileName,
        payload: {
          'fileName': fileName,
          'content': content,
          'exportedAt': DateTime.now().toIso8601String(),
        },
      );
      _persistMutation('EXPORT_REPORT_FILE', {
        'fileName': fileName,
        'path': virtualPath,
      });
      return virtualPath;
    }
    final sep = Platform.pathSeparator;
    String targetPath;
    try {
      final exportDir = Directory(
        '${Directory.current.path}${sep}database${sep}exports',
      );
      if (!exportDir.existsSync()) {
        exportDir.createSync(recursive: true);
      }
      targetPath = '${exportDir.path}$sep$fileName';
      File(targetPath).writeAsStringSync(content, flush: true);
    } catch (_) {
      targetPath = '${Directory.systemTemp.path}$sep$fileName';
      try {
        File(targetPath).writeAsStringSync(content, flush: true);
      } catch (_) {}
    }
    _persistMutation('EXPORT_REPORT_FILE', {
      'fileName': fileName,
      'path': targetPath,
    });
    return targetPath;
  }
}
