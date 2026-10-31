part of 'app_state_store.dart';

extension AppStateAuthAndGpsOps on AppStateStore {
  /// Đăng ký tài khoản mới hoặc cập nhật vào bảng `users` trong CSDL SQLite + PostGIS
  UserAccountRecord? registerUserAccountWithRole({
    required String phone,
    required String fullName,
    required String password,
    required SubsystemRole role,
    String? email,
    String? defaultAddress,
    bool activateSession = true,
  }) {
    final normPhone = _normalizePhone(phone);
    if (normPhone.length < 9 || fullName.trim().isEmpty) {
      return null;
    }
    if (findUserByPhone(normPhone) != null) {
      return null;
    }
    final cleanEmail = email?.trim() ?? '';
    if (cleanEmail.isNotEmpty && findUserByPhoneOrEmail(cleanEmail) != null) {
      return null;
    }
    if (password.trim().length < 6) return null;
    final pwd = password.trim();
    final passwordHash = SecurityAndBarcodeUtils.hashPasswordWithSalt(
      pwd,
      normPhone,
    );
    registeredUserPasswordHashes[normPhone] = passwordHash;

    final record = UserAccountRecord(
      id: allocateUniqueId('USR-', users.map((u) => u.id)),
      phone: normPhone,
      email: cleanEmail,
      passwordHash: passwordHash,
      fullName: fullName.trim(),
      role: role,
      defaultAddress: defaultAddress?.trim().isNotEmpty == true
          ? defaultAddress!.trim()
          : (liveDeviceAddress.trim().isNotEmpty
                ? liveDeviceAddress.trim()
                : ''),
      defaultLocation:
          liveDeviceLocation ??
          const GeoPoint(latitude: 10.7769, longitude: 106.6953),
      createdAt: DateTime.now().toIso8601String(),
    );
    users.add(record);

    _sqliteDb.upsertRow('users', {
      'id': record.id,
      'phone': _normalizePhone(record.phone),
      'email': record.email,
      'password_hash': record.passwordHash,
      'full_name': record.fullName,
      'role': record.roleDbCode,
      'default_address': record.defaultAddress,
      'default_lat': record.defaultLocation.latitude,
      'default_lng': record.defaultLocation.longitude,
      'status': record.status,
      'created_at': record.createdAt,
    });

    if (role == SubsystemRole.driver &&
        drivers.where((d) => _normalizePhone(d.phone) == normPhone).isEmpty) {
      registerOrUpdateDriverKyc(
        fullName: record.fullName,
        phone: normPhone,
        citizenId: '',
        vehicleType: 'Xe máy',
        licensePlate: '',
        activateDriverContext: activateSession,
      );
    } else if (role == SubsystemRole.merchant &&
        merchantApplicants
            .where((m) => _normalizePhone(m.ownerPhone) == normPhone)
            .isEmpty) {
      registerOrUpdateMerchantKyc(
        ownerPhone: normPhone,
        storeName: record.fullName,
        businessType: 'Bán lẻ tổng hợp',
        taxCode: '',
        representativeName: record.fullName,
        bankName: '',
        bankAccount: '',
      );
    }

    if (activateSession) {
      applyAuthenticatedUserSession(record);
    }
    _persistMutation('USER_REGISTER_SQL', {
      'table': 'users',
      'phone': normPhone,
      'role': record.roleDbCode,
    });
    _notifyStoreChanged();
    return record;
  }

  /// Áp dụng phiên đăng nhập thực tế từ bản ghi `users` trong CSDL
  void applyAuthenticatedUserSession(
    UserAccountRecord user, {
    SubsystemRole? activeWorkspaceRole,
  }) {
    activeAuthenticatedUser = user;
    customerFullName = user.fullName;
    customerPhone = user.phone;
    customerEmail = user.email;
    customerDefaultAddress = user.defaultAddress;
    final normUserPhone = _normalizePhone(user.phone);
    final prefs = userPreferencesByPhone[normUserPhone];
    customerGender = prefs?['gender']?.toString() ?? 'Chưa cập nhật';
    customerAvatarBadgeIndex =
        (prefs?['avatarBadgeIndex'] as num?)?.toInt() ?? 0;
    isCustomerGoogleLinked = prefs != null && prefs.containsKey('googleLinked')
        ? prefs['googleLinked'] == true
        : false;
    isCustomerTwoFactorEnabled = prefs?['twoFactorEnabled'] == true;
    selectedCustomerOrderCode = null;
    selectedDriverOrderCode = null;

    final effectiveRole = activeWorkspaceRole ?? user.role;
    final matchedDrv = drivers
        .where((d) => _normalizePhone(d.phone) == normUserPhone)
        .firstOrNull;
    final matchedMer = merchantApplicants
        .where((m) => _normalizePhone(m.ownerPhone) == normUserPhone)
        .firstOrNull;

    if (effectiveRole == SubsystemRole.driver || matchedDrv != null) {
      if (matchedDrv != null) {
        activeDriverId = matchedDrv.id;
        activeDriverName = matchedDrv.fullName;
        activeDriverPhone = matchedDrv.phone;
        isDriverOnline =
            matchedDrv.approvalStatus == 'Đã duyệt' &&
            matchedDrv.isOnline &&
            matchedDrv.walletBalance >= 200000 &&
            user.status == 'ACTIVE';
        activeDriverLocation = matchedDrv.location;
        driverWalletBalance = matchedDrv.walletBalance;
      } else if (effectiveRole == SubsystemRole.driver) {
        activeDriverName = user.fullName;
        activeDriverPhone = user.phone;
        activeDriverId = '';
        isDriverOnline = false;
        driverWalletBalance = 0;
      }
    } else {
      final fallbackDrv =
          drivers
              .where(
                (d) =>
                    d.approvalStatus == 'Đã duyệt' &&
                    d.isOnline &&
                    d.walletBalance >= 200000,
              )
              .firstOrNull ??
          drivers.firstOrNull;
      if (fallbackDrv != null) {
        activeDriverId = fallbackDrv.id;
        activeDriverName = fallbackDrv.fullName;
        activeDriverPhone = fallbackDrv.phone;
        isDriverOnline = fallbackDrv.isOnline;
        activeDriverLocation = fallbackDrv.location;
        driverWalletBalance = fallbackDrv.walletBalance;
      }
    }

    if (effectiveRole == SubsystemRole.merchant || matchedMer != null) {
      if (matchedMer != null) {
        merchantStoreName = matchedMer.storeName;
        merchantBusinessType = matchedMer.businessType;
        merchantTaxCode = matchedMer.taxCode;
        merchantRepresentative = matchedMer.representativeName;
        merchantOpenHours = matchedMer.openHours;
        merchantBankName = matchedMer.bankName;
        merchantBankAccount = matchedMer.bankAccount;
        merchantCodBalance = matchedMer.codBalance;
      } else if (effectiveRole == SubsystemRole.merchant) {
        merchantStoreName = user.fullName;
        merchantBusinessType = 'Bán lẻ tổng hợp';
        merchantTaxCode = '';
        merchantRepresentative = user.fullName;
        merchantOpenHours = '08:00 - 21:00';
        merchantBankName = 'Ngân hàng VPBank (VPB)';
        merchantBankAccount = '';
        merchantCodBalance = 0;
      }
    }

    if (effectiveRole == SubsystemRole.driver && liveDeviceLocation != null) {
      activeDriverLocation = liveDeviceLocation!;
      if (matchedDrv != null) {
        matchedDrv.location = liveDeviceLocation!;
      }
    }

    if (effectiveRole == SubsystemRole.admin) {
      currentAdminRoleName = 'Super Admin';
    }
    if (!_isFlutterTestRuntime) {
      unawaited(
        startRealTimeDeviceGpsTracking(
          syncDriverLocation: effectiveRole == SubsystemRole.driver,
          forcePromptPermission: false,
        ),
      );
    }
    _notifyStoreChanged();
  }

  /// Làm sạch phiên đăng nhập hiện tại khi người dùng nhấn Đăng xuất
  void clearAuthenticatedSession() {
    unawaited(disconnectLiveRooms());
    unawaited(
      PushNotificationService.instance
          .disable()
          .whenComplete(() => LiveDeliveryService.instance.signOut())
          .catchError((_) {}),
    );
    activeAuthenticatedUser = null;
    selectedCustomerOrderCode = null;
    selectedDriverOrderCode = null;
    final fallbackDrv =
        drivers
            .where(
              (d) =>
                  d.approvalStatus == 'Đã duyệt' &&
                  d.isOnline &&
                  d.walletBalance >= 200000,
            )
            .firstOrNull ??
        drivers.firstOrNull;
    if (fallbackDrv != null) {
      activeDriverId = fallbackDrv.id;
      activeDriverName = fallbackDrv.fullName;
      activeDriverPhone = fallbackDrv.phone;
      isDriverOnline = fallbackDrv.isOnline;
      driverWalletBalance = fallbackDrv.walletBalance;
    }
    _notifyStoreChanged();
  }

  /// Đăng ký hoặc xác thực mật khẩu đã băm SHA-256 mở rộng kèm Salt
  bool authenticateOrRegisterAccount({
    required String phone,
    required String password,
    bool isRegister = false,
    String? fullName,
    SubsystemRole role = SubsystemRole.customer,
  }) {
    final normPhone = _normalizePhone(phone);
    if (normPhone.length < 9 || password.trim().length < 6) {
      return false;
    }
    final passwordHash = SecurityAndBarcodeUtils.hashPasswordWithSalt(
      password.trim(),
      normPhone,
    );
    if (isRegister) {
      final created = registerUserAccountWithRole(
        phone: normPhone,
        fullName: (fullName != null && fullName.trim().isNotEmpty)
            ? fullName.trim()
            : customerFullName,
        password: password.trim(),
        role: role,
      );
      return created != null;
    }
    final existingUser = findUserByPhone(normPhone);
    if (existingUser != null && existingUser.status == 'LOCKED') {
      return false;
    }
    final existingHash =
        existingUser?.passwordHash ?? registeredUserPasswordHashes[normPhone];
    if (existingHash == null) {
      return false;
    }
    final matched = existingHash == passwordHash;
    if (matched) {
      if (existingUser != null) {
        applyAuthenticatedUserSession(existingUser);
      } else {
        customerPhone = phone.trim();
        _notifyStoreChanged();
      }
    }
    return matched;
  }

  /// Xác thực đăng nhập bằng Số điện thoại hoặc Email kèm Mật khẩu đã đăng ký
  UserAccountRecord? authenticateWithPassword({
    required String phoneOrEmail,
    required String password,
    bool activateSession = true,
  }) {
    final user = findUserByPhoneOrEmail(phoneOrEmail);
    if (user == null || user.status == 'LOCKED' || password.trim().isEmpty) {
      return null;
    }
    final normPhone = _normalizePhone(user.phone);
    final candidateHash = SecurityAndBarcodeUtils.hashPasswordWithSalt(
      password.trim(),
      normPhone,
    );
    if (user.passwordHash != candidateHash) {
      return null;
    }
    if (activateSession) {
      applyAuthenticatedUserSession(user);
    }
    _persistMutation('PASSWORD_LOGIN_VERIFIED', {'phone': normPhone});
    return user;
  }

  /// Xác minh mật khẩu tài khoản Quản trị tối cao (Super Admin) trước khi nâng quyền phiên RBAC
  bool verifySuperAdminPassword(String password) {
    final cleanPwd = password.trim();
    if (cleanPwd.isEmpty) return false;
    final adminAccounts = users.where((u) => u.role == SubsystemRole.admin);
    for (final admin in adminAccounts) {
      final normPhone = _normalizePhone(admin.phone);
      final candidateHash = SecurityAndBarcodeUtils.hashPasswordWithSalt(
        cleanPwd,
        normPhone,
      );
      if (admin.passwordHash == candidateHash) {
        return true;
      }
    }
    return false;
  }

  String _resolveOtpKey(String phoneOrEmail) {
    final trimmed = phoneOrEmail.trim();
    if (trimmed.contains('@')) {
      final matched = findUserByPhoneOrEmail(trimmed);
      if (matched != null) {
        return _normalizePhone(matched.phone);
      }
      return trimmed.toLowerCase();
    }
    return _normalizePhone(trimmed);
  }

  String generateOtpForPhone(String phone, {bool notify = false}) {
    final normKey = _resolveOtpKey(phone);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final hashHex = SecurityAndBarcodeUtils.hashPasswordWithSalt(
      '$nowMs',
      normKey,
    ).replaceAll('BCRYPT-HASH-', '');
    final numericVal = int.parse(hashHex.substring(0, 8), radix: 16);
    final otp6 = (100000 + (numericVal % 900000)).toString();
    final expiryMs = nowMs + 120000;
    activeOtpCodesByPhone[normKey] = otp6;
    otpExpiryEpochMsByPhone[normKey] = expiryMs;
    if (notify) {
      _notifyStoreChanged();
    }
    return otp6;
  }

  int getRemainingOtpSeconds(String phone) {
    final normKey = _resolveOtpKey(phone);
    final expiry = otpExpiryEpochMsByPhone[normKey];
    if (expiry == null) return 0;
    final remainMs = expiry - DateTime.now().millisecondsSinceEpoch;
    return remainMs > 0 ? (remainMs / 1000).ceil() : 0;
  }

  bool verifyOtpCode(String phone, String inputOtp) {
    final normKey = _resolveOtpKey(phone);
    final user = findUserByPhoneOrEmail(phone);
    if (user != null && user.status == 'LOCKED') {
      return false;
    }
    final expected = activeOtpCodesByPhone[normKey];
    final expiry = otpExpiryEpochMsByPhone[normKey];
    if (expected == null || expiry == null) return false;
    if (DateTime.now().millisecondsSinceEpoch > expiry) return false;
    final ok = expected == inputOtp.trim();
    if (ok) {
      activeOtpCodesByPhone.remove(normKey);
      otpExpiryEpochMsByPhone.remove(normKey);
      if (user != null) {
        applyAuthenticatedUserSession(user);
      }
      _persistMutation('OTP_VERIFIED', {'phone': normKey});
      _notifyStoreChanged();
    }
    return ok;
  }

  /// Đặt lại mật khẩu mới cho tài khoản bằng mã xác thực OTP Số điện thoại hoặc Email
  UserAccountRecord? resetPasswordWithOtp({
    required String phoneOrEmail,
    required String otpCode,
    required String newPassword,
  }) {
    final pwd = newPassword.trim();
    if (pwd.length < 6) return null;
    final user = findUserByPhoneOrEmail(phoneOrEmail);
    if (user == null || user.status == 'LOCKED') return null;
    final verified = verifyOtpCode(phoneOrEmail, otpCode);
    if (!verified) return null;

    final normPhone = _normalizePhone(user.phone);
    final newHash = SecurityAndBarcodeUtils.hashPasswordWithSalt(
      pwd,
      normPhone,
    );
    user.passwordHash = newHash;
    registeredUserPasswordHashes[normPhone] = newHash;

    _sqliteDb.updateRows(
      'users',
      {'password_hash': newHash},
      where: 'id = ?',
      whereArgs: [user.id],
    );
    applyAuthenticatedUserSession(user);
    _persistMutation('PASSWORD_RESET_BY_OTP', {
      'userId': user.id,
      'phone': normPhone,
    });
    _notifyStoreChanged();
    return user;
  }

  bool updateCustomerProfile({
    required String fullName,
    required String phone,
    required String email,
    required String defaultAddress,
    String? gender,
    int? avatarBadgeIndex,
  }) {
    final oldNameLower = customerFullName.trim().toLowerCase();
    final oldPhoneNorm = _normalizePhone(customerPhone);
    final candidatePhoneNorm = phone.trim().isNotEmpty
        ? _normalizePhone(phone)
        : oldPhoneNorm;
    final candidateEmailLower = email.trim().toLowerCase();

    final u =
        activeAuthenticatedUser ??
        findUserByPhone(oldPhoneNorm) ??
        findUserByPhone(candidatePhoneNorm) ??
        findUserByPhoneOrEmail(customerEmail) ??
        users.where((x) => x.role == SubsystemRole.customer).firstOrNull;

    if (candidatePhoneNorm.isNotEmpty && candidatePhoneNorm != oldPhoneNorm) {
      final phoneClash = users.any(
        (other) =>
            other.id != u?.id &&
            _normalizePhone(other.phone) == candidatePhoneNorm,
      );
      if (phoneClash) return false;
    }
    if (candidateEmailLower.isNotEmpty) {
      final emailClash = users.any(
        (other) =>
            other.id != u?.id &&
            other.email.trim().toLowerCase() == candidateEmailLower,
      );
      if (emailClash) return false;
    }

    if (fullName.trim().isNotEmpty) {
      customerFullName = fullName.trim();
    }
    if (phone.trim().isNotEmpty) {
      customerPhone = phone.trim();
    }
    customerEmail = email.trim();
    customerDefaultAddress = defaultAddress.trim();
    if (gender != null && gender.trim().isNotEmpty) {
      customerGender = gender.trim();
    }
    if (avatarBadgeIndex != null) {
      customerAvatarBadgeIndex = avatarBadgeIndex;
    }

    final normPhone = _normalizePhone(customerPhone);
    if (customerFullName.trim().toLowerCase() != oldNameLower) {
      for (final ord in orders) {
        if (ord.customerName.trim().toLowerCase() == oldNameLower) {
          ord.customerName = customerFullName;
          _sqliteDb.updateRows(
            'orders',
            {'customer_name': customerFullName},
            where: 'tracking_code = ?',
            whereArgs: [ord.trackingCode],
          );
        }
      }
    }
    if (normPhone.isNotEmpty && normPhone != oldPhoneNorm) {
      if (userPreferencesByPhone.containsKey(oldPhoneNorm)) {
        userPreferencesByPhone[normPhone] = userPreferencesByPhone.remove(
          oldPhoneNorm,
        )!;
      }
      for (var i = 0; i < savedAddresses.length; i++) {
        final addr = savedAddresses[i];
        if (_normalizePhone(addr.userPhone) == oldPhoneNorm) {
          final updatedAddr = SavedAddressRecord(
            id: addr.id,
            userPhone: normPhone,
            label: addr.label,
            fullAddress: addr.fullAddress,
            location: addr.location,
          );
          savedAddresses[i] = updatedAddr;
          _sqliteDb.updateRows(
            'user_addresses',
            {'user_phone': normPhone},
            where: 'id = ?',
            whereArgs: [addr.id],
          );
        }
      }
    }

    if (normPhone.isNotEmpty) {
      final prefs = Map<String, dynamic>.from(
        userPreferencesByPhone[normPhone] ?? const <String, dynamic>{},
      );
      prefs['gender'] = customerGender;
      prefs['avatarBadgeIndex'] = customerAvatarBadgeIndex;
      prefs['googleLinked'] = isCustomerGoogleLinked;
      prefs['twoFactorEnabled'] = isCustomerTwoFactorEnabled;
      userPreferencesByPhone[normPhone] = prefs;
      _sqliteDb.upsertEntityRecord(
        tableName: 'user_preferences',
        recordId: normPhone,
        payload: prefs,
      );
    }

    if (u != null) {
      u.fullName = customerFullName;
      if (normPhone.isNotEmpty) {
        u.phone = normPhone;
      }
      u.email = customerEmail;
      u.defaultAddress = customerDefaultAddress;
      _sqliteDb.upsertRow('users', {
        'id': u.id,
        'phone': u.phone,
        'email': u.email,
        'password_hash': u.passwordHash,
        'full_name': u.fullName,
        'role': u.roleDbCode,
        'default_address': u.defaultAddress,
        'default_lat': u.defaultLocation.latitude,
        'default_lng': u.defaultLocation.longitude,
        'status': u.status,
        'created_at': u.createdAt,
      });
    }
    _persistMutation('UPDATE_CUSTOMER_PROFILE', {'phone': normPhone});
    _notifyStoreChanged();
    return true;
  }

  DriverApplicantRecord registerOrUpdateDriverKyc({
    required String fullName,
    required String phone,
    required String citizenId,
    required String vehicleType,
    required String licensePlate,
    String vehicleColor = 'Xanh đen',
    String? bankName,
    String? bankAccount,
    List<String>? attachedDocs,
    bool activateDriverContext = true,
  }) {
    final normPhone = _normalizePhone(phone);
    final existing = drivers
        .where((d) => _normalizePhone(d.phone) == normPhone)
        .firstOrNull;
    final DriverApplicantRecord record;
    if (existing != null) {
      final coreLegalChanged =
          existing.citizenId.trim() != citizenId.trim() ||
          existing.licensePlate.trim().toLowerCase() !=
              licensePlate.trim().toLowerCase() ||
          existing.vehicleType.trim() != vehicleType.trim();
      existing.fullName = fullName.trim();
      existing.phone = normPhone;
      existing.citizenId = citizenId.trim();
      existing.vehicleType = vehicleType.trim();
      existing.isElectricVehicle = DriverApplicantRecord.inferElectricVehicle(
        vehicleType.trim(),
      );
      existing.licensePlate = licensePlate.trim();
      if (vehicleColor.trim().isNotEmpty) {
        existing.vehicleColor = vehicleColor.trim();
      }
      if (bankName != null && bankName.trim().isNotEmpty) {
        existing.bankName = bankName.trim();
      }
      if (bankAccount != null && bankAccount.trim().isNotEmpty) {
        existing.bankAccount = bankAccount.trim();
      }
      if (attachedDocs != null) {
        existing.attachedKycDocs = List<String>.from(attachedDocs);
      }
      final ownerUser = findUserByPhone(normPhone);
      final isCustomerApplying =
          ownerUser != null && ownerUser.role == SubsystemRole.customer;
      if (existing.approvalStatus != 'Đã duyệt' ||
          coreLegalChanged ||
          isCustomerApplying) {
        existing.approvalStatus = 'Chờ duyệt';
        existing.isOnline = false;
      }
      record = existing;
    } else {
      record = DriverApplicantRecord(
        id: allocateUniqueId(
          'DV109',
          drivers.map((d) => d.id),
          minNumber: 28,
          padDigits: 2,
        ),
        fullName: fullName.trim(),
        phone: normPhone,
        citizenId: citizenId.trim(),
        licensePlate: licensePlate.trim(),
        vehicleType: vehicleType.trim(),
        vehicleColor: vehicleColor,
        approvalStatus: 'Chờ duyệt',
        isOnline: false,
        location: const GeoPoint(latitude: 10.7769, longitude: 106.6953),
        rating: 0.0,
        totalTrips: 0,
        walletBalance: 0.0,
        bankName: bankName?.trim().isNotEmpty == true ? bankName!.trim() : '',
        bankAccount: bankAccount?.trim().isNotEmpty == true
            ? bankAccount!.trim()
            : '',
        attachedKycDocs: attachedDocs != null
            ? List<String>.from(attachedDocs)
            : <String>[],
      );
      drivers.insert(0, record);
    }

    if (activateDriverContext &&
        (activeAuthenticatedUser == null ||
            activeAuthenticatedUser!.role == SubsystemRole.driver)) {
      activeDriverId = record.id;
      activeDriverName = record.fullName;
      activeDriverPhone = record.phone;
      isDriverOnline = record.isOnline;
      driverWalletBalance = record.walletBalance;
    }

    _sqliteDb.upsertRow('drivers', {
      'id': record.id,
      'phone': _normalizePhone(record.phone),
      'full_name': record.fullName,
      'citizen_id': record.citizenId,
      'license_plate': record.licensePlate,
      'vehicle_type': record.vehicleType,
      'vehicle_color': record.vehicleColor,
      'approval_status': record.approvalStatus,
      'is_online': record.isOnline ? 1 : 0,
      'latitude': record.location.latitude,
      'longitude': record.location.longitude,
      'rating': record.rating,
      'total_trips': record.totalTrips,
      'rejected_count': record.rejectedCount,
      'wallet_balance': record.walletBalance,
      'bank_name': record.bankName,
      'bank_account': record.bankAccount,
      'is_electric_vehicle': record.isElectricVehicle ? 1 : 0,
      'battery_percent': record.batteryPercent,
      'attached_kyc_docs_json': jsonEncode(record.attachedKycDocs),
      'created_at': DateTime.now().toIso8601String(),
    });
    _sqliteDb.upsertEntityRecord(
      tableName: 'driver_meta',
      recordId: record.id,
      payload: {
        'rejectedCount': record.rejectedCount,
        'bankName': record.bankName,
        'bankAccount': record.bankAccount,
        'isElectricVehicle': record.isElectricVehicle,
        'batteryPercent': record.batteryPercent,
        'attachedKycDocs': record.attachedKycDocs,
      },
    );
    _persistMutation('REGISTER_DRIVER_KYC', {'driverId': record.id});
    _notifyStoreChanged();
    return record;
  }

  void recordDriverDispatchRejection(String trackingCode) {
    final drv = activeDriverRecord;
    if (drv != null) {
      drv.rejectedCount += 1;
      _sqliteDb.updateRows(
        'drivers',
        {'rejected_count': drv.rejectedCount},
        where: 'id = ?',
        whereArgs: [drv.id],
      );
      _sqliteDb.upsertEntityRecord(
        tableName: 'driver_meta',
        recordId: drv.id,
        payload: {
          'rejectedCount': drv.rejectedCount,
          'bankName': drv.bankName,
          'bankAccount': drv.bankAccount,
          'attachedKycDocs': drv.attachedKycDocs,
        },
      );
      _persistMutation('DRIVER_REJECT_OFFER', {
        'driverId': drv.id,
        'trackingCode': trackingCode,
        'rejectedCount': drv.rejectedCount,
      });
      _notifyStoreChanged();
    }
  }

  MerchantApplicantRecord registerOrUpdateMerchantKyc({
    required String ownerPhone,
    required String storeName,
    required String businessType,
    required String taxCode,
    required String representativeName,
    required String bankName,
    required String bankAccount,
    String openHours = '08:00 - 21:00',
    List<String>? attachedDocs,
  }) {
    final normPhone = _normalizePhone(ownerPhone);
    final existing = merchantApplicants
        .where((m) => _normalizePhone(m.ownerPhone) == normPhone)
        .firstOrNull;
    final MerchantApplicantRecord record;
    if (existing != null) {
      final coreTaxChanged =
          existing.taxCode.trim().toLowerCase() != taxCode.trim().toLowerCase();
      existing.storeName = storeName.trim();
      existing.businessType = businessType.trim();
      existing.taxCode = taxCode.trim();
      existing.representativeName = representativeName.trim();
      existing.openHours = openHours.trim();
      existing.bankName = bankName.trim();
      existing.bankAccount = bankAccount.trim();
      if (attachedDocs != null) {
        existing.attachedKycDocs = List<String>.from(attachedDocs);
      }
      final ownerUser = findUserByPhone(normPhone);
      final isCustomerApplying =
          ownerUser != null && ownerUser.role == SubsystemRole.customer;
      if (existing.approvalStatus != 'Đã duyệt' ||
          coreTaxChanged ||
          isCustomerApplying) {
        existing.approvalStatus = 'Chờ duyệt';
      }
      record = existing;
    } else {
      record = MerchantApplicantRecord(
        id: allocateUniqueId('MER-', merchantApplicants.map((m) => m.id)),
        ownerPhone: normPhone,
        storeName: storeName.trim(),
        businessType: businessType.trim(),
        taxCode: taxCode.trim(),
        representativeName: representativeName.trim(),
        openHours: openHours.trim(),
        bankName: bankName.trim(),
        bankAccount: bankAccount.trim(),
        approvalStatus: 'Chờ duyệt',
        codBalance: 0.0,
        attachedKycDocs: attachedDocs != null
            ? List<String>.from(attachedDocs)
            : null,
      );
      merchantApplicants.insert(0, record);
    }

    _sqliteDb.upsertRow('merchants', {
      'id': record.id,
      'owner_phone': normPhone,
      'store_name': record.storeName,
      'business_type': record.businessType,
      'tax_code': record.taxCode,
      'representative_name': record.representativeName,
      'open_hours': record.openHours,
      'bank_name': record.bankName,
      'bank_account': record.bankAccount,
      'cod_balance': record.codBalance,
      'approval_status': record.approvalStatus,
      'webhook_url': record.webhookUrl,
      'attached_kyc_docs_json': jsonEncode(record.attachedKycDocs),
      'created_at': DateTime.now().toIso8601String(),
    });
    _sqliteDb.upsertEntityRecord(
      tableName: 'merchant_meta',
      recordId: record.id,
      payload: {
        'webhookUrl': record.webhookUrl,
        'attachedKycDocs': record.attachedKycDocs,
      },
    );
    _persistMutation('REGISTER_MERCHANT_KYC', {'merchantId': record.id});
    _notifyStoreChanged();
    return record;
  }

  void setDriverOnlineStatus(bool online) {
    final drv = activeDriverRecord;
    final linkedUser = drv != null ? findUserByPhone(drv.phone) : null;
    if (online &&
        (drv == null ||
            drv.approvalStatus != 'Đã duyệt' ||
            drv.walletBalance < 200000 ||
            linkedUser?.status == 'LOCKED')) {
      isDriverOnline = false;
      currentSpeedKmh = 0.0;
      if (drv != null) {
        drv.isOnline = false;
      }
      _notifyStoreChanged();
      return;
    }
    isDriverOnline = online;
    currentSpeedKmh = online
        ? (activeDriverPersonalOrderRecord != null ? 26.0 : 0.0)
        : 0.0;
    if (drv != null) {
      drv.isOnline = online;
      _sqliteDb.updateRows(
        'drivers',
        {'is_online': online ? 1 : 0},
        where: 'id = ?',
        whereArgs: [drv.id],
      );
    }
    _persistMutation('SET_DRIVER_ONLINE', {'isOnline': online});
    _notifyStoreChanged();
  }

  /// Cập nhật % dung lượng pin xe điện (SoC) cho tài xế đang hoạt động để điều phối thông minh
  void updateActiveDriverBatteryPercent(int batteryPercent) {
    final drv = activeDriverRecord;
    if (drv == null) return;
    final clamped = batteryPercent.clamp(0, 100);
    drv.batteryPercent = clamped;
    _sqliteDb.updateRows(
      'drivers',
      {
        'battery_percent': clamped,
        'is_electric_vehicle': drv.isElectricVehicle ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [drv.id],
    );
    _sqliteDb.upsertEntityRecord(
      tableName: 'driver_meta',
      recordId: drv.id,
      payload: {
        'rejectedCount': drv.rejectedCount,
        'bankName': drv.bankName,
        'bankAccount': drv.bankAccount,
        'isElectricVehicle': drv.isElectricVehicle,
        'batteryPercent': drv.batteryPercent,
        'attachedKycDocs': drv.attachedKycDocs,
      },
    );
    _notifyStoreChanged();
  }

  void updateMerchantProfile({
    required String storeName,
    required String taxCode,
    required String businessType,
    required String representativeName,
    required String phone,
    String? email,
    required String bankName,
    required String bankAccount,
    String? warehouseAddress,
    int warehouseIndex = 0,
    List<String>? attachedDocs,
  }) {
    final oldStoreLower = (activeMerchantRecord?.storeName ?? merchantStoreName)
        .trim()
        .toLowerCase();
    merchantStoreName = storeName.trim();
    merchantTaxCode = taxCode.trim();
    merchantBusinessType = businessType.trim();
    merchantRepresentative = representativeName.trim();
    merchantBankName = bankName.trim();
    merchantBankAccount = bankAccount.trim();
    if (email != null && email.trim().isNotEmpty && email.contains('@')) {
      final cleanEmail = email.trim();
      customerEmail = cleanEmail;
      final activeUser = activeAuthenticatedUser;
      if (activeUser != null) {
        activeUser.email = cleanEmail;
        _sqliteDb.updateRows(
          'users',
          {'email': cleanEmail},
          where: 'id = ?',
          whereArgs: [activeUser.id],
        );
      }
    }

    if (oldStoreLower.isNotEmpty &&
        merchantStoreName.trim().toLowerCase() != oldStoreLower) {
      for (final ord in orders) {
        if (ord.customerName.trim().toLowerCase() == oldStoreLower) {
          ord.customerName = merchantStoreName;
          _sqliteDb.updateRows(
            'orders',
            {'customer_name': merchantStoreName},
            where: 'tracking_code = ?',
            whereArgs: [ord.trackingCode],
          );
        }
      }
    }

    MerchantApplicantRecord? targetMer = activeMerchantRecord;
    if (targetMer == null && activeAuthenticatedUser == null) {
      targetMer = merchantApplicants.firstOrNull;
    }
    if (targetMer == null) {
      final resolvedOwnerPhone = phone.trim().isNotEmpty
          ? _normalizePhone(phone)
          : _normalizePhone(activeAuthenticatedUser?.phone ?? customerPhone);
      registerOrUpdateMerchantKyc(
        ownerPhone: resolvedOwnerPhone,
        storeName: merchantStoreName,
        businessType: merchantBusinessType,
        taxCode: merchantTaxCode,
        representativeName: merchantRepresentative,
        bankName: merchantBankName,
        bankAccount: merchantBankAccount,
        openHours: merchantOpenHours,
        attachedDocs: attachedDocs,
      );
      targetMer = activeMerchantRecord;
    } else {
      final coreTaxChanged =
          targetMer.taxCode.trim().toLowerCase() !=
          merchantTaxCode.trim().toLowerCase();
      targetMer.storeName = merchantStoreName;
      targetMer.taxCode = merchantTaxCode;
      targetMer.businessType = merchantBusinessType;
      targetMer.representativeName = merchantRepresentative;
      if (phone.trim().isNotEmpty) {
        targetMer.ownerPhone = _normalizePhone(phone);
      }
      targetMer.bankName = merchantBankName;
      targetMer.bankAccount = merchantBankAccount;
      if (attachedDocs != null) {
        targetMer.attachedKycDocs = List<String>.from(attachedDocs);
      }
      if (targetMer.approvalStatus != 'Đã duyệt' || coreTaxChanged) {
        targetMer.approvalStatus = 'Chờ duyệt';
      }
      merchantCodBalance = targetMer.codBalance;
      _sqliteDb.upsertEntityRecord(
        tableName: 'merchant_meta',
        recordId: targetMer.id,
        payload: {
          'webhookUrl': targetMer.webhookUrl,
          'attachedKycDocs': targetMer.attachedKycDocs,
        },
      );
    }
    final targetMerId = targetMer?.id ?? 'MER-01';
    final persistedOwnerPhone =
        targetMer?.ownerPhone ??
        (phone.trim().isNotEmpty
            ? _normalizePhone(phone)
            : _normalizePhone(activeAuthenticatedUser?.phone ?? customerPhone));

    if (warehouseAddress != null && warehouseAddress.trim().isNotEmpty) {
      final personalWhs = merchantPersonalWarehouses;
      if (personalWhs.isNotEmpty) {
        final safeIdx = warehouseIndex.clamp(0, personalWhs.length - 1);
        final currentWh = personalWhs[safeIdx];
        updateMerchantWarehouseDetails(
          warehouseId: currentWh.id,
          name: currentWh.name,
          address: warehouseAddress.trim(),
          setPrimary: currentWh.isPrimary,
        );
      }
    }

    _sqliteDb.upsertRow('merchants', {
      'id': targetMerId,
      'owner_phone': persistedOwnerPhone,
      'store_name': merchantStoreName,
      'business_type': merchantBusinessType,
      'tax_code': merchantTaxCode,
      'representative_name': merchantRepresentative,
      'open_hours': merchantOpenHours,
      'bank_name': merchantBankName,
      'bank_account': merchantBankAccount,
      'cod_balance': targetMer?.codBalance ?? merchantCodBalance,
      'approval_status': targetMer?.approvalStatus ?? 'Đã duyệt',
      'webhook_url': targetMer?.webhookUrl ?? '',
      'attached_kyc_docs_json': jsonEncode(targetMer?.attachedKycDocs),
      'created_at': DateTime.now().toIso8601String(),
    });
    _persistMutation('UPDATE_MERCHANT_PROFILE', {
      'storeName': merchantStoreName,
    });
    _notifyStoreChanged();
  }

  void updateMerchantWarehouseDetails({
    required String warehouseId,
    required String name,
    required String address,
    String? contactName,
    String? contactPhone,
    String? openHours,
    bool? setPrimary,
    GeoPoint? customLocation,
  }) {
    final targetMer =
        activeMerchantRecord ??
        (activeAuthenticatedUser == null
            ? merchantApplicants.firstOrNull
            : null);
    final targetMerId = targetMer?.id ?? 'MER-01';
    final cleanName = name.trim().isNotEmpty ? name.trim() : 'Kho lấy hàng';
    final cleanAddr = address.trim();
    if (cleanAddr.isEmpty) return;

    final existingIdx = merchantWarehouses.indexWhere(
      (w) => w.id == warehouseId,
    );
    final currentWh = existingIdx >= 0 ? merchantWarehouses[existingIdx] : null;
    final resolvedPt =
        customLocation ??
        SmartDispatchEngine.resolveAddressToCoordinate(
          cleanAddr,
          fallback:
              currentWh?.location ??
              const GeoPoint(latitude: 10.7769, longitude: 106.6953),
        );
    final makePrimary = setPrimary ?? (currentWh?.isPrimary ?? true);

    if (makePrimary) {
      for (var i = 0; i < merchantWarehouses.length; i++) {
        final w = merchantWarehouses[i];
        if (w.merchantId == targetMerId && w.id != warehouseId && w.isPrimary) {
          merchantWarehouses[i] = PickupWarehouseRecord(
            id: w.id,
            merchantId: w.merchantId,
            name: w.name,
            address: w.address,
            location: w.location,
            contactName: w.contactName,
            contactPhone: w.contactPhone,
            openHours: w.openHours,
            isPrimary: false,
            webhookUrl: w.webhookUrl,
          );
          _sqliteDb.updateRows(
            'merchant_pickup_points',
            {'is_primary': 0},
            where: 'id = ?',
            whereArgs: [w.id],
          );
          _sqliteDb.upsertEntityRecord(
            tableName: 'warehouse_meta',
            recordId: w.id,
            payload: {
              'isPrimary': false,
              'webhookUrl': w.webhookUrl,
              'contactName': w.contactName,
              'contactPhone': w.contactPhone,
              'openHours': w.openHours,
            },
          );
        }
      }
    }

    final resolvedId = warehouseId.endsWith('-DEFAULT')
        ? allocateUniqueId('WH-', merchantWarehouses.map((w) => w.id))
        : warehouseId;
    final resolvedContactName =
        (contactName != null && contactName.trim().isNotEmpty)
        ? contactName.trim()
        : (currentWh?.contactName.isNotEmpty == true
              ? currentWh!.contactName
              : (targetMer?.representativeName ?? merchantRepresentative));
    final resolvedPhone =
        (contactPhone != null && contactPhone.trim().isNotEmpty)
        ? contactPhone.trim()
        : (currentWh?.contactPhone ?? targetMer?.ownerPhone ?? '0909112233');
    final resolvedHours = (openHours != null && openHours.trim().isNotEmpty)
        ? openHours.trim()
        : (currentWh?.openHours ?? targetMer?.openHours ?? '08:00 - 21:00');
    final updatedWh = PickupWarehouseRecord(
      id: resolvedId,
      merchantId: targetMerId,
      name: cleanName,
      address: cleanAddr,
      location: resolvedPt,
      contactName: resolvedContactName,
      contactPhone: resolvedPhone,
      openHours: resolvedHours,
      isPrimary: makePrimary,
      webhookUrl: currentWh?.webhookUrl ?? targetMer?.webhookUrl ?? '',
    );
    if (existingIdx >= 0) {
      merchantWarehouses[existingIdx] = updatedWh;
    } else {
      merchantWarehouses.add(updatedWh);
    }

    _sqliteDb.upsertRow('merchant_pickup_points', {
      'id': updatedWh.id,
      'merchant_id': targetMerId,
      'warehouse_name': updatedWh.name,
      'full_address': updatedWh.address,
      'latitude': updatedWh.location.latitude,
      'longitude': updatedWh.location.longitude,
      'contact_phone': updatedWh.contactPhone,
      'open_hours': updatedWh.openHours,
      'is_primary': updatedWh.isPrimary ? 1 : 0,
      'webhook_url': updatedWh.webhookUrl,
      'created_at': DateTime.now().toIso8601String(),
    });
    _sqliteDb.upsertEntityRecord(
      tableName: 'warehouse_meta',
      recordId: updatedWh.id,
      payload: {
        'isPrimary': updatedWh.isPrimary,
        'webhookUrl': updatedWh.webhookUrl,
        'contactName': updatedWh.contactName,
        'contactPhone': updatedWh.contactPhone,
        'openHours': updatedWh.openHours,
      },
    );
    _persistMutation('UPDATE_MERCHANT_WAREHOUSE', {
      'id': updatedWh.id,
      'name': updatedWh.name,
      'address': updatedWh.address,
      'isPrimary': updatedWh.isPrimary,
    });
    _notifyStoreChanged();
  }

  Future<String> saveAndTestMerchantWebhook({
    required String webhookUrl,
  }) async {
    final trimmed = webhookUrl.trim();
    final targetMer = activeMerchantRecord ?? merchantApplicants.firstOrNull;
    if (targetMer != null) {
      targetMer.webhookUrl = trimmed;
      await _sqliteDb.updateRows(
        'merchants',
        {'webhook_url': trimmed},
        where: 'id = ?',
        whereArgs: [targetMer.id],
      );
      await _sqliteDb.upsertEntityRecord(
        tableName: 'merchant_meta',
        recordId: targetMer.id,
        payload: {
          'webhookUrl': trimmed,
          'attachedKycDocs': targetMer.attachedKycDocs,
        },
      );
    }
    _persistMutation('SAVE_MERCHANT_WEBHOOK', {
      'merchantId': targetMer?.id ?? 'MER-01',
      'webhookUrl': trimmed,
    });
    _notifyStoreChanged();

    if (trimmed.isEmpty) {
      return 'Đã xóa URL Webhook của cửa hàng.';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'URL Webhook không hợp lệ (cần bắt đầu bằng http:// hoặc https://).';
    }

    final sampleOrder =
        merchantPersonalOrders.firstOrNull ?? orders.firstOrNull;
    final eventBody = <String, dynamic>{
      'event': 'ORDER_STATUS_UPDATED',
      'merchantId': targetMer?.id ?? 'MER-01',
      'storeName': targetMer?.storeName ?? merchantStoreName,
      'trackingCode': sampleOrder?.trackingCode ?? '#DH301201',
      'status': sampleOrder?.status.dbCode ?? 'DELIVERED',
      'codAmount': sampleOrder?.codAmount ?? 0,
      'timestamp': DateTime.now().toIso8601String(),
    };
    final sig = SecurityAndBarcodeUtils.generatePaymentSignature(
      orderCode: eventBody['trackingCode'].toString(),
      amount: (eventBody['codAmount'] as num).toDouble(),
      method: targetMer?.id ?? 'MER-01',
    );
    eventBody['signature'] = sig;

    try {
      final resp = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'X-GoMau-Signature': sig,
            },
            body: jsonEncode(eventBody),
          )
          .timeout(const Duration(seconds: 4));
      return 'Đã lưu & POST Webhook tới ${uri.host} -> HTTP ${resp.statusCode} (Chữ ký: $sig)';
    } catch (e) {
      return 'Đã lưu URL Webhook vào CSDL. Thử kết nối HTTP POST tới ${uri.host}: $e';
    }
  }

  void savePricingConfiguration({
    required double baseFare,
    required double pricePerKm,
    required bool isPeakEnabled,
    required bool isWeatherEnabled,
  }) {
    if (!hasAdminPermission('Hệ thống: Cài đặt')) return;
    baseFareConfig = baseFare;
    pricePerKmConfig = pricePerKm;
    isPeakSurchargeActive = isPeakEnabled;
    isWeatherSurchargeActive = isWeatherEnabled;

    _sqliteDb.upsertRow('pricing_configs', {
      'id': 'PRC-01',
      'service_type': 'STANDARD_V2',
      'base_fare': baseFareConfig,
      'price_per_km': pricePerKmConfig,
      'peak_hour_surcharge': peakHourSurchargeConfig,
      'bad_weather_surcharge': badWeatherSurchargeConfig,
      'is_peak_enabled': isPeakSurchargeActive ? 1 : 0,
      'is_weather_enabled': isWeatherSurchargeActive ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    });
    _persistMutation('SAVE_PRICING_CONFIG', {
      'baseFare': baseFareConfig,
      'pricePerKm': pricePerKmConfig,
    });
    _notifyStoreChanged();
  }

  bool processOrderPayment({
    required String trackingCode,
    required String gateway,
    required String transactionId,
  }) {
    final ord = orders.where((o) => o.trackingCode == trackingCode).firstOrNull;
    if (ord == null) return false;
    if (ord.status == OrderStatus.cancelled ||
        ord.paymentStatus == 'PAID' ||
        ord.paymentStatus == 'REFUNDED' ||
        ord.paymentStatus == 'RETURNED') {
      return false;
    }
    final signature =
        SecurityAndBarcodeUtils.generatePaymentIdempotencySignature(
          orderId: trackingCode,
          amount: ord.totalAmount,
          gateway: gateway,
          transactionId: transactionId,
        );
    if (processedPaymentSignatures.contains(signature)) {
      return false;
    }
    processedPaymentSignatures.add(signature);
    ord.paymentMethod = gateway;
    ord.paymentStatus = 'PAID';
    _sqliteDb.updateRows(
      'orders',
      {'payment_method': gateway, 'payment_status': 'PAID'},
      where: 'tracking_code = ?',
      whereArgs: [trackingCode],
    );
    _persistMutation('ORDER_PAYMENT_PAID', {
      'trackingCode': trackingCode,
      'gateway': gateway,
      'signature': signature,
    });
    unawaited(
      recordLedgerEntry(
        ownerType: 'CUSTOMER',
        ownerId: activeAuthenticatedUser?.id,
        orderId: ord.id,
        direction: 'DEBIT',
        entryType: 'ORDER_PAYMENT',
        amount: ord.totalAmount,
        idempotencyKey: signature,
        metadata: {'gateway': gateway, 'trackingCode': trackingCode},
      ),
    );
    unawaited(
      recordAuditEvent(
        action: 'ORDER_PAYMENT_PAID',
        entityType: 'ORDER',
        entityId: ord.id,
        after: {'trackingCode': trackingCode, 'gateway': gateway},
      ),
    );
    _notifyStoreChanged();
    return true;
  }

  CsvBatchParseResult parseAndCreateBulkOrdersFromCsv(
    String csvContentOrFilePath, {
    bool commitOrders = false,
    String? customPickupAddress,
    String feePayerMethod = 'Người gửi trả phí',
  }) {
    String rawContent = csvContentOrFilePath.trim();
    try {
      if (!kIsWeb && rawContent.toLowerCase().endsWith('.csv')) {
        final f = File(rawContent);
        if (f.existsSync()) {
          rawContent = f.readAsStringSync();
        }
      }
    } catch (_) {}

    final lines = Csv(dynamicTyping: false)
        .decode(rawContent)
        .map((row) => row.map((field) => field.toString().trim()).toList())
        .where((row) => row.any((field) => field.isNotEmpty))
        .toList();

    final parsedRows = <CsvBatchRowResult>[];
    final createdCodes = <String>[];
    int validCount = 0;
    int invalidCount = 0;
    final phoneRegex = RegExp(r'^(?:\+84|0)[0-9]{9}$');
    double? money(String raw) {
      var value = raw.replaceAll('đ', '').replaceAll(' ', '').trim();
      if (RegExp(r'^-?[0-9]{1,3}(\.[0-9]{3})+$').hasMatch(value)) {
        value = value.replaceAll('.', '');
      }
      return value.isEmpty ? 0 : double.tryParse(value);
    }

    GeoPoint? point(List<String> columns, int index) {
      if (columns.length <= index + 1) return null;
      final lat = double.tryParse(columns[index]);
      final lng = double.tryParse(columns[index + 1]);
      if (lat == null ||
          lng == null ||
          !lat.isFinite ||
          !lng.isFinite ||
          lat.abs() > 90 ||
          lng.abs() > 180) {
        return null;
      }
      return GeoPoint(latitude: lat, longitude: lng);
    }

    for (var i = 0; i < lines.length; i++) {
      final cols = lines[i];
      if (i == 0 &&
          cols.length >= 2 &&
          const {
            'ten_nguoi_nhan',
            'nguoi_nhan',
            'recipient',
            'recipient_name',
          }.contains(cols[0].toLowerCase()) &&
          const {
            'sdt_nguoi_nhan',
            'sdt',
            'phone',
            'recipient_phone',
          }.contains(cols[1].toLowerCase())) {
        continue;
      }
      final name = cols.isNotEmpty ? cols[0] : '';
      final phone = cols.length > 1 ? cols[1].replaceAll(' ', '') : '';
      final address = cols.length > 2 ? cols[2] : '';

      final isFourColCodFormat = cols.length == 4;

      final desc = isFourColCodFormat
          ? 'Kiện hàng thương mại điện tử'
          : (cols.length > 3 && cols[3].isNotEmpty
                ? cols[3]
                : 'Kiện hàng thương mại điện tử');
      final weight = isFourColCodFormat
          ? 1.5
          : (cols.length > 4 ? (double.tryParse(cols[4]) ?? double.nan) : 1.5);
      final cod = isFourColCodFormat
          ? (money(cols[3]) ?? double.nan)
          : (cols.length > 5 ? (money(cols[5]) ?? double.nan) : 0.0);
      final svcStr = !isFourColCodFormat && cols.length > 6
          ? cols[6].toUpperCase()
          : 'STANDARD';
      final svc = svcStr.contains('EXPRESS')
          ? DeliveryServiceType.express30m
          : svcStr.contains('2H') ||
                svcStr.contains('SAME_DAY') ||
                svcStr.contains('GHEP')
          ? DeliveryServiceType.sameDay2h
          : svcStr.contains('TRUCK') ||
                svcStr.contains('LARGE') ||
                svcStr.contains('TAI')
          ? DeliveryServiceType.truck
          : svcStr.contains('ECONOMY') || svcStr.contains('SAVING')
          ? DeliveryServiceType.saving
          : DeliveryServiceType.standard;
      final rowCustomPickup = !isFourColCodFormat && cols.length > 7
          ? cols[7].trim()
          : '';

      final resolvedPickup = rowCustomPickup.isNotEmpty
          ? rowCustomPickup
          : (customPickupAddress?.trim().isNotEmpty == true
                ? customPickupAddress!.trim()
                : (merchantPersonalWarehouses.isNotEmpty
                      ? merchantPersonalWarehouses.first.address
                      : ''));
      final pickupCoordinatesProvided =
          cols.length > 8 && cols.skip(8).take(2).any((c) => c.isNotEmpty);
      final dropoffCoordinatesProvided =
          cols.length > 10 && cols.skip(10).take(2).any((c) => c.isNotEmpty);
      final warehouse = merchantPersonalWarehouses
          .where(
            (w) =>
                w.address.trim().toLowerCase() ==
                resolvedPickup.trim().toLowerCase(),
          )
          .firstOrNull;
      final pickupPt = pickupCoordinatesProvided
          ? point(cols, 8)
          : SmartDispatchEngine.tryResolveAddressToCoordinate(resolvedPickup) ??
                warehouse?.location;
      final dropoffPt = dropoffCoordinatesProvided
          ? point(cols, 10)
          : SmartDispatchEngine.tryResolveAddressToCoordinate(address);
      final restrictedZone = pickupPt != null && dropoffPt != null
          ? findActiveRestrictedZoneForRoute(pickupPt, dropoffPt)
          : null;
      final errors = <String>[];
      if (![4, 7, 8, 12].contains(cols.length)) {
        errors.add('Số cột không hợp lệ (cần 4, 7, 8 hoặc 12 cột)');
      }
      if (name.isEmpty) errors.add('Thiếu tên người nhận');
      if (!phoneRegex.hasMatch(phone)) errors.add('SĐT không hợp lệ');
      if (resolvedPickup.trim().length < 5) {
        errors.add('Thiếu địa chỉ lấy hàng');
      }
      if (pickupCoordinatesProvided && pickupPt == null ||
          dropoffCoordinatesProvided && dropoffPt == null) {
        errors.add('Tọa độ không hợp lệ');
      }
      if (address.trim().length < 10) {
        errors.add('Thiếu địa chỉ giao');
      } else if (pickupPt == null || dropoffPt == null) {
        errors.add(
          'Chưa xác định được tọa độ thật của điểm lấy hoặc điểm giao',
        );
      } else if (address.trim().toLowerCase() ==
          resolvedPickup.trim().toLowerCase()) {
        errors.add('Địa chỉ giao trùng với kho lấy hàng');
      } else if (restrictedZone != null) {
        errors.add('Thuộc vùng cấm giao (${restrictedZone.zoneName})');
      }
      if (!weight.isFinite || weight <= 0 || weight > 500) {
        errors.add('Khối lượng không hợp lệ');
      }
      if (!cod.isFinite ||
          cod < 0 ||
          cod > 20000000 ||
          cod != cod.truncateToDouble()) {
        errors.add('Tiền COD không hợp lệ');
      }

      final isValid = errors.isEmpty;
      if (isValid) {
        validCount++;
        if (commitOrders && pickupPt != null && dropoffPt != null) {
          final created = createNewOrder(
            pickupAddress: resolvedPickup,
            dropoffAddress: address,
            recipientName: name,
            recipientPhone: phone,
            packageDescription: desc,
            weightKg: weight,
            dimensionsCm: '30 x 20 x 15 cm',
            serviceType: svc,
            codAmount: cod,
            paymentMethod: feePayerMethod,
            customCustomerName:
                activeMerchantRecord?.storeName ?? merchantStoreName,
            customPickupLocation: pickupPt,
            customDropoffLocation: dropoffPt,
          );
          createdCodes.add(created.trackingCode);
        }
      } else {
        invalidCount++;
      }

      parsedRows.add(
        CsvBatchRowResult(
          rowNumber: parsedRows.length + 1,
          recipientName: name.isEmpty ? '(Trống)' : name,
          recipientPhone: phone.isEmpty ? '(Trống)' : phone,
          dropoffAddress: address.isEmpty ? '(Trống)' : address,
          packageDescription: desc,
          weightKg: weight,
          codAmount: cod,
          serviceType: svc,
          isValid: isValid,
          statusNote: isValid ? 'Hợp lệ' : errors.join(', '),
          pickupAddress: resolvedPickup,
          pickupLocation: pickupPt,
          dropoffLocation: dropoffPt,
        ),
      );
    }

    return CsvBatchParseResult(
      rows: parsedRows,
      validCount: validCount,
      invalidCount: invalidCount,
      createdTrackingCodes: createdCodes,
    );
  }

  void toggleOfflineSimulation(bool offline) {
    final wasOffline = isOfflineMode;
    isOfflineMode = offline;
    if (offline) {
      lastSyncStatusMessage =
          'Đang ở chế độ ngoại tuyến • Các thao tác được lưu tạm chờ kết nối lại ($offlineQueueCount mục)';
    } else {
      if (wasOffline && offlineQueueCount > 0) {
        lastSyncStatusMessage =
            'Đang chờ máy chủ xác nhận $offlineQueueCount thao tác ngoại tuyến';
      } else if (wasOffline) {
        lastSyncStatusMessage = 'Đã khôi phục kết nối trực tuyến';
      }
      drainOfflineSyncQueue();
    }
    _persistMutation('TOGGLE_OFFLINE', {'isOffline': offline});
    _notifyStoreChanged();
  }

  void toggleMap3d() {
    isMap3dEnabled = !isMap3dEnabled;
    currentCameraPitch = isMap3dEnabled ? 55.0 : 0.0;
    _notifyStoreChanged();
  }

  void stepDriverAlongRoute({bool snapToDropoff = false}) {
    if (activeAuthenticatedUser?.role == SubsystemRole.driver &&
        activeDriverPersonalOrderRecord == null) {
      return;
    }
    final fallbackOrd =
        activeDriverPersonalOrderRecord ??
        activeOrderRecord ??
        orders.firstOrNull;
    if (fallbackOrd == null) return;
    final polyline = activeRoutePolyline.length >= 2
        ? activeRoutePolyline
        : SmartDispatchEngine.generateRoutePolyline(
            fallbackOrd.pickupLocation,
            fallbackOrd.dropoffLocation,
            segments: 10,
          );
    if (snapToDropoff) {
      routeProgressStep = polyline.length - 1;
    } else {
      routeProgressStep = (routeProgressStep + 1) % polyline.length;
    }
    final rawTarget = polyline[routeProgressStep];
    final previous = activeDriverLocation;
    activeDriverLocation = _kalmanFilter.filter(
      rawPoint: rawTarget,
      accuracyMeters: 4.5,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (snapToDropoff) {
      activeDriverLocation = fallbackOrd.dropoffLocation;
      currentSpeedKmh = 0.0;
    } else {
      final legMeters = GeoMath.distanceMeters(previous, activeDriverLocation);
      currentSpeedKmh = legMeters > 5.0
          ? (22.0 + (routeProgressStep % 4) * 3.0)
          : 26.0;
    }
    activeDriverBearing = GeoMath.bearingDegrees(
      previous,
      activeDriverLocation,
    );
    final activeDrv = activeDriverRecord;
    if (activeDrv != null) {
      activeDrv.location = activeDriverLocation;
      _sqliteDb.updateRows(
        'drivers',
        {
          'latitude': activeDriverLocation.latitude,
          'longitude': activeDriverLocation.longitude,
        },
        where: 'id = ?',
        whereArgs: [activeDrv.id],
      );
    }
    final recordedAtIso = DateTime.now().toIso8601String();
    final trackingRow = <String, dynamic>{
      'order_id': fallbackOrd.id,
      'driver_id': activeDrv?.id ?? activeDriverId,
      'latitude': activeDriverLocation.latitude,
      'longitude': activeDriverLocation.longitude,
      'speed': currentSpeedKmh,
      'bearing': activeDriverBearing,
      'is_mock_location': 0,
      'recorded_at': recordedAtIso,
    };
    _sqliteDb.upsertRow('order_tracking_logs', trackingRow);
    if (isOfflineMode) {
      offlineQueueCount++;
      _sqliteDb.enqueueAction(
        actionType: 'GPS_PING',
        payload: {'table': 'order_tracking_logs', 'record': trackingRow},
      );
    }
    _notifyStoreChanged();
  }

  double distanceFromDriverToPickupMeters() {
    final ord =
        activeDriverPersonalOrderRecord ??
        activeOrderRecord ??
        orders.firstOrNull;
    if (ord == null) return 0.0;
    return GeoMath.distanceMeters(activeDriverLocation, ord.pickupLocation);
  }

  double distanceFromDriverToDropoffMeters() {
    final ord =
        activeDriverPersonalOrderRecord ??
        activeOrderRecord ??
        orders.firstOrNull;
    if (ord == null) return 0.0;
    return GeoMath.distanceMeters(activeDriverLocation, ord.dropoffLocation);
  }

  double distanceFromDriverToOrderDropoffMeters(ActiveOrderRecord ord) {
    if (ord.status == OrderStatus.delivered &&
        ord.paymentStatus != 'RETURNED') {
      return 0.0;
    }
    if (activeOrderRecord?.trackingCode == ord.trackingCode &&
        (ord.status == OrderStatus.inTransit ||
            ord.status == OrderStatus.arrivingPickup ||
            ord.status == OrderStatus.accepted)) {
      final liveDist = GeoMath.distanceMeters(
        activeDriverLocation,
        ord.dropoffLocation,
      );
      if (liveDist <= 50000) {
        return liveDist;
      }
    }
    return GeoMath.distanceMeters(ord.pickupLocation, ord.dropoffLocation);
  }

  bool get _isFlutterTestRuntime =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// Ghi nhận tọa độ GPS xác thực của thiết bị vào Store, giải mã địa chỉ đường phố thật và đồng bộ cho Tài xế khi cần
  void applyVerifiedDeviceGpsFix({
    required GeoPoint rawPoint,
    double accuracyMeters = 10.0,
    double speedKmh = 0.0,
    double? headingDeg,
    bool isMocked = false,
    bool syncToActiveDriver = false,
  }) {
    if (isMocked ||
        !rawPoint.latitude.isFinite ||
        !rawPoint.longitude.isFinite ||
        rawPoint.latitude < -90.0 ||
        rawPoint.latitude > 90.0 ||
        rawPoint.longitude < -180.0 ||
        rawPoint.longitude > 180.0) {
      return;
    }

    if (liveDeviceLocation != null &&
        liveDeviceAccuracyMeters != null &&
        liveDeviceAccuracyMeters! <= 1500.0 &&
        accuracyMeters.isFinite &&
        accuracyMeters > 5000.0) {
      return;
    }

    liveDeviceLocation = rawPoint;
    liveDeviceAccuracyMeters = (accuracyMeters.isFinite && accuracyMeters > 0)
        ? accuracyMeters
        : null;
    lastLiveGpsFixAt = DateTime.now();
    final accText = liveDeviceAccuracyMeters != null
        ? (liveDeviceAccuracyMeters! >= 2000.0
              ? ' ±${(liveDeviceAccuracyMeters! / 1000.0).round()}km'
              : ' ±${liveDeviceAccuracyMeters!.toStringAsFixed(0)}m')
        : '';
    liveGpsStatusMessage =
        'GPS Thật: (${rawPoint.latitude.toStringAsFixed(5)}, ${rawPoint.longitude.toStringAsFixed(5)})$accText';

    final shouldSyncDriver =
        syncToActiveDriver ||
        (activeAuthenticatedUser?.role == SubsystemRole.driver &&
            isDriverOnline);
    if (shouldSyncDriver && !isMocked) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      try {
        GpsIntegrityValidator.validateSample(
          currentPoint: rawPoint,
          currentTimestampMs: nowMs,
          isMockFlaggedByOs: isMocked,
          reportedSpeedKmh: speedKmh > 0 ? speedKmh : 0.0,
        );
      } catch (_) {}

      if (!_hasHardwareKalmanLock ||
          GeoMath.distanceMeters(activeDriverLocation, rawPoint) > 1500.0) {
        _kalmanFilter.reset();
        _hasHardwareKalmanLock = true;
      }
      final previous = activeDriverLocation;
      activeDriverLocation = _kalmanFilter.filter(
        rawPoint: rawPoint,
        accuracyMeters: liveDeviceAccuracyMeters != null
            ? liveDeviceAccuracyMeters!
            : 8.0,
        timestampMs: nowMs,
      );
      currentSpeedKmh = speedKmh.isFinite && speedKmh >= 0 ? speedKmh : 0.0;
      if (headingDeg != null && headingDeg.isFinite && headingDeg >= 0) {
        activeDriverBearing = headingDeg % 360.0;
      } else if (GeoMath.distanceMeters(previous, activeDriverLocation) > 2.0) {
        activeDriverBearing = GeoMath.bearingDegrees(
          previous,
          activeDriverLocation,
        );
      }
      final activeDrv = activeDriverRecord;
      if (activeDrv != null) {
        activeDrv.location = activeDriverLocation;
        verifiedDriverLocations[activeDrv.id] = activeDriverLocation;
        _sqliteDb.upsertEntityRecord(
          tableName: 'verified_driver_locations',
          recordId: activeDrv.id,
          payload: {
            'id': activeDrv.id,
            'latitude': activeDriverLocation.latitude,
            'longitude': activeDriverLocation.longitude,
          },
        );
        _sqliteDb.updateRows(
          'drivers',
          {
            'latitude': activeDriverLocation.latitude,
            'longitude': activeDriverLocation.longitude,
          },
          where: 'id = ?',
          whereArgs: [activeDrv.id],
        );
      }
      lastSyncStatusMessage = liveGpsStatusMessage;
      final activeOrd = activeDriverPersonalOrderRecord ?? activeOrderRecord;
      if (activeOrd != null) {
        _sqliteDb.upsertRow('order_tracking_logs', {
          'order_id': activeOrd.id,
          'driver_id': activeDrv?.id ?? activeDriverId,
          'latitude': activeDriverLocation.latitude,
          'longitude': activeDriverLocation.longitude,
          'speed': currentSpeedKmh,
          'bearing': activeDriverBearing,
          'is_mock_location': isMocked ? 1 : 0,
          'recorded_at': DateTime.now().toIso8601String(),
        });
      }
    }

    final shouldReverseGeocode =
        !_isFlutterTestRuntime &&
        !isOfflineMode &&
        (_lastReverseGeocodedDevicePoint == null ||
            GeoMath.distanceMeters(
                  _lastReverseGeocodedDevicePoint!,
                  rawPoint,
                ) >=
                35.0 ||
            liveDeviceAddress.trim().isEmpty);
    if (shouldReverseGeocode) {
      _lastReverseGeocodedDevicePoint = rawPoint;
      unawaited(
        SmartDispatchEngine.reverseGeocodeCoordinate(rawPoint)
            .then((resolvedAddr) {
              if (resolvedAddr.trim().isNotEmpty) {
                liveDeviceAddress = resolvedAddr.trim();
                _notifyStoreChanged();
              }
            })
            .catchError((_) {}),
      );
    }

    _notifyStoreChanged();
  }

  /// Khởi động luồng định vị GPS phần cứng thời gian thực (Windows Geolocation / Web / Android / iOS)
  Future<GeoPoint?> startRealTimeDeviceGpsTracking({
    bool syncDriverLocation = false,
    bool forcePromptPermission = true,
  }) async {
    if (_isFlutterTestRuntime) {
      return liveDeviceLocation;
    }
    if (_acquiringLiveGpsFuture != null) {
      return _acquiringLiveGpsFuture!;
    }
    final future = _performRealTimeDeviceGpsAcquisition(
      syncDriverLocation: syncDriverLocation,
      forcePromptPermission: forcePromptPermission,
    );
    _acquiringLiveGpsFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_acquiringLiveGpsFuture, future)) {
        _acquiringLiveGpsFuture = null;
      }
    }
  }

  Future<GeoPoint?> _performRealTimeDeviceGpsAcquisition({
    required bool syncDriverLocation,
    required bool forcePromptPermission,
  }) async {
    isAcquiringLiveGps = true;
    liveGpsStatusMessage = 'Đang kết nối cảm biến định vị GPS thiết bị...';
    _notifyStoreChanged();
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        isLiveGpsStreaming = false;
        isAcquiringLiveGps = false;
        liveGpsStatusMessage =
            'Dịch vụ Vị trí (Location) của hệ điều hành đang tắt';
        _notifyStoreChanged();
        return liveDeviceLocation;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && forcePromptPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        isLiveGpsStreaming = false;
        isAcquiringLiveGps = false;
        liveGpsStatusMessage =
            'Chưa cấp quyền Vị trí cho ứng dụng trong Cài đặt hệ điều hành';
        _notifyStoreChanged();
        return liveDeviceLocation;
      }

      if (!kIsWeb && liveDeviceLocation == null) {
        try {
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            applyVerifiedDeviceGpsFix(
              rawPoint: GeoPoint(
                latitude: lastKnown.latitude,
                longitude: lastKnown.longitude,
              ),
              accuracyMeters: lastKnown.accuracy,
              speedKmh: lastKnown.speed > 0 ? lastKnown.speed * 3.6 : 0.0,
              headingDeg: lastKnown.heading >= 0 ? lastKnown.heading : null,
              isMocked: lastKnown.isMocked,
              syncToActiveDriver: syncDriverLocation,
            );
          }
        } catch (_) {}
      }

      if (_liveGpsStreamSub == null) {
        try {
          _liveGpsStreamSub =
              Geolocator.getPositionStream(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.best,
                  distanceFilter: 8,
                ),
              ).listen(
                (Position streamPos) {
                  isLiveGpsStreaming = true;
                  applyVerifiedDeviceGpsFix(
                    rawPoint: GeoPoint(
                      latitude: streamPos.latitude,
                      longitude: streamPos.longitude,
                    ),
                    accuracyMeters: streamPos.accuracy,
                    speedKmh: streamPos.speed > 0 ? streamPos.speed * 3.6 : 0.0,
                    headingDeg: streamPos.heading >= 0
                        ? streamPos.heading
                        : null,
                    isMocked: streamPos.isMocked,
                  );
                },
                onError: (_) {
                  isLiveGpsStreaming = false;
                  _liveGpsStreamSub?.cancel();
                  _liveGpsStreamSub = null;
                  _notifyStoreChanged();
                },
              );
          isLiveGpsStreaming = true;
        } catch (_) {}
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 12),
        ),
      );
      isAcquiringLiveGps = false;
      applyVerifiedDeviceGpsFix(
        rawPoint: GeoPoint(latitude: pos.latitude, longitude: pos.longitude),
        accuracyMeters: pos.accuracy,
        speedKmh: pos.speed > 0 ? pos.speed * 3.6 : 0.0,
        headingDeg: pos.heading >= 0 ? pos.heading : null,
        isMocked: pos.isMocked,
        syncToActiveDriver: syncDriverLocation,
      );
      return liveDeviceLocation;
    } catch (e) {
      isAcquiringLiveGps = false;
      if (liveDeviceLocation == null) {
        liveGpsStatusMessage = 'Chưa nhận được tín hiệu vị trí từ thiết bị. Hãy kiểm tra Wi-Fi/GPS.';
      }
      _notifyStoreChanged();
      return liveDeviceLocation;
    }
  }

  void stopRealTimeDeviceGpsTracking() {
    _liveGpsStreamSub?.cancel();
    _liveGpsStreamSub = null;
    isLiveGpsStreaming = false;
    isAcquiringLiveGps = false;
    _notifyStoreChanged();
  }

  /// Mở trực tiếp trang Cài đặt Quyền Vị trí (Location Privacy Settings) của Hệ điều hành
  Future<bool> openDeviceLocationSettings() async {
    if (_isFlutterTestRuntime || kIsWeb) return false;
    try {
      final opened = await Geolocator.openLocationSettings();
      if (opened) return true;
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  /// Đọc tọa độ GPS phần cứng độc lập cho Khách hàng / Cửa hàng (đồng thời kích hoạt stream GPS trực tiếp)
  Future<GeoPoint?> acquireCustomerDeviceGps() async {
    return startRealTimeDeviceGpsTracking(
      syncDriverLocation: false,
      forcePromptPermission: true,
    );
  }

  Future<String> acquireRealHardwareGps() async {
    final pos = await startRealTimeDeviceGpsTracking(
      syncDriverLocation: true,
      forcePromptPermission: true,
    );
    if (pos == null) {
      return '$liveGpsStatusMessage. Bạn có thể bật Dịch vụ Vị trí trong Cài đặt hệ điều hành.';
    }
    _persistMutation('HARDWARE_GPS_FIX', {
      'lat': activeDriverLocation.latitude,
      'lng': activeDriverLocation.longitude,
    });
    return liveGpsStatusMessage;
  }

  Future<String> syncLiveOsrmRouteForActiveOrder() async {
    final ord =
        activeDriverPersonalOrderRecord ??
        activeOrderRecord ??
        orders.firstOrNull;
    if (ord == null) {
      return 'Hiện chưa có vận đơn nào để đồng bộ lộ trình OSRM.';
    }
    final res = await SmartDispatchEngine.fetchLiveOsrmRoute(
      ord.pickupLocation,
      ord.dropoffLocation,
    );
    ord.distanceMeters = res.distanceMeters;
    ord.durationSeconds = res.durationSeconds;
    if (res.polylinePoints.length >= 2) {
      activeRoutePolyline = res.polylinePoints;
      routeProgressStep = 0;
    }
    await _sqliteDb.updateRows(
      'orders',
      {
        'distance_meters': ord.distanceMeters,
        'duration_seconds': ord.durationSeconds,
      },
      where: 'id = ?',
      whereArgs: [ord.id],
    );
    final km = (res.distanceMeters / 1000.0).toStringAsFixed(1);
    final mins = (res.durationSeconds / 60).round().clamp(5, 240);
    lastSyncStatusMessage = res.isLiveOsrm
        ? 'OSRM Thực tế: $km km ($mins phút) - ${res.polylinePoints.length} điểm tọa độ'
        : 'Nội suy Haversine Offline: $km km ($mins phút)';
    _persistMutation('OSRM_ROUTE_SYNC', {
      'trackingCode': ord.trackingCode,
      'distanceMeters': ord.distanceMeters,
      'points': activeRoutePolyline.length,
    });
    _notifyStoreChanged();
    return lastSyncStatusMessage;
  }

  Future<String> configureAndSyncSupabaseCloud({
    required String url,
    required String anonKey,
  }) async {
    if (!hasAdminPermission('Hệ thống: Bảo mật')) {
      return 'Từ chối: Chỉ vai trò có quyền "Hệ thống: Bảo mật" mới được cấu hình Cloud.';
    }
    final uri = Uri.tryParse(url.trim());
    final publicKey = anonKey.trim();
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        publicKey.isEmpty ||
        publicKey.startsWith('sb_secret_')) {
      return 'Cần Project URL và publishable/anon key hợp lệ. Không dùng service-role key trong app.';
    }
    if (publicKey.split('.').length == 3) {
      try {
        final claims = jsonDecode(
          utf8.decode(
            base64Url.decode(base64Url.normalize(publicKey.split('.')[1])),
          ),
        );
        if (claims['role'] == 'service_role') {
          return 'Không được lưu service-role key trong app.';
        }
      } catch (_) {
        return 'Public API key không hợp lệ.';
      }
    }
    await disconnectLiveRooms();
    EnvConfig.configureSupabaseRuntime(url: url, anonKey: anonKey);
    if (!EnvConfig.isSupabaseConfigured) {
      return 'Vui lòng nhập SUPABASE_URL hợp lệ và SUPABASE_ANON_KEY không rỗng.';
    }
    try {
      try {
        try {
          await Supabase.instance.dispose();
        } catch (_) {}
        await Supabase.initialize(
          url: EnvConfig.supabaseUrl,
          publishableKey: EnvConfig.supabaseAnonKey,
        );
      } catch (_) {
        return 'Không khởi tạo được kết nối Supabase.';
      }
      await saveLocalIntegrationConfig({
        'supabaseUrl': url.trim(),
        'supabaseAnonKey': anonKey.trim(),
      });
      SupabasePostgisDatasource.bindRuntimeClient(
        EnvConfig.supabaseUrl,
        EnvConfig.supabaseAnonKey,
        client: Supabase.instance.client,
      );
      final remoteDs = SupabasePostgisDatasource();
      final rows = await remoteDs.fetchTableRecords('orders', limit: 20);
      isOfflineMode = false;
      offlineQueueCount = await _sqliteDb.getPendingQueueCount();
      lastSyncStatusMessage =
          'Đã kết nối Cloud Supabase PostGIS thành công (${rows.length} bản ghi orders trên mây)';
      _notifyStoreChanged();
      return lastSyncStatusMessage;
    } catch (e) {
      lastSyncStatusMessage = 'Đã lưu cấu hình Supabase; chưa truy cập được bảng orders. Dữ liệu vẫn lưu trên thiết bị.';
      _notifyStoreChanged();
      return lastSyncStatusMessage;
    }
  }

  /// Đăng nhập hoặc tự động khởi tạo tài khoản trong bảng `users` SQLite từ phiên Google OAuth 2.0
  UserAccountRecord? signInOrRegisterOAuthUser({
    required String email,
    required String fullName,
    String? phone,
    SubsystemRole role = SubsystemRole.customer,
  }) {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = fullName.trim().isNotEmpty
        ? fullName.trim()
        : cleanEmail.split('@').first;
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return null;
    }

    final existingByEmail = findUserByPhoneOrEmail(cleanEmail);
    if (existingByEmail != null) {
      if (existingByEmail.status == 'LOCKED') {
        return existingByEmail;
      }
      if (existingByEmail.id != 'USR-01' &&
          existingByEmail.defaultAddress ==
              '123 Đường Lê Lợi, Quận 1, TP. HCM') {
        existingByEmail.defaultAddress = '';
        _sqliteDb.updateRows(
          'users',
          {'default_address': ''},
          where: 'id = ?',
          whereArgs: [existingByEmail.id],
        );
      }
      applyAuthenticatedUserSession(existingByEmail);
      _persistMutation('OAUTH_GOOGLE_SIGN_IN', {
        'email': cleanEmail,
        'userId': existingByEmail.id,
      });
      return existingByEmail;
    }

    final rawPhoneDigits = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    int seedSuffix = 10000000 + (cleanEmail.hashCode.abs() % 89999999);
    String resolvedPhone =
        rawPhoneDigits.length >= 9 && findUserByPhone(rawPhoneDigits) == null
        ? rawPhoneDigits
        : '09$seedSuffix';
    while (findUserByPhone(resolvedPhone) != null) {
      seedSuffix = 10000000 + ((seedSuffix + 1) % 89999999);
      resolvedPhone = '09$seedSuffix';
    }

    final safeRole = role == SubsystemRole.admin
        ? SubsystemRole.customer
        : role;

    return registerUserAccountWithRole(
      phone: resolvedPhone,
      email: cleanEmail,
      fullName: cleanName,
      password: 'OAUTH-GOOGLE-${cleanEmail.hashCode.abs()}',
      role: safeRole,
    );
  }

  Future<void> saveAuthProviderConfigsToDatabase({
    required String smtpHost,
    required int smtpPort,
    required String smtpSenderEmail,
    required String smtpAppPassword,
    required String smsWebhookUrl,
    required String googleClientId,
    required String googleClientSecret,
    String? smsProvider,
    String? smsApiKey,
    String? smsApiSecret,
    String? smsBrandname,
    String? otpEmailWebhookUrl,
    String? otpEmailWebhookToken,
  }) async {
    if (activeAuthenticatedUser?.role != SubsystemRole.admin ||
        !hasAdminPermission('Hệ thống: Bảo mật')) {
      throw StateError('Không có quyền thay đổi cấu hình đăng nhập.');
    }
    final config = <String, dynamic>{
      ..._authProviderConfigSnapshot(),
      'smtpHost': smtpHost.trim(),
      'smtpPort': smtpPort,
      'smtpSenderEmail': smtpSenderEmail.trim(),
      'smtpAppPassword': smtpAppPassword.replaceAll(' ', '').trim(),
      'smsWebhookUrl': smsWebhookUrl.trim(),
      'smsProvider': smsProvider ?? EnvConfig.smsProvider,
      'smsApiKey': smsApiKey ?? EnvConfig.smsApiKey,
      'smsApiSecret': smsApiSecret ?? EnvConfig.smsApiSecret,
      'smsBrandname': smsBrandname ?? EnvConfig.smsBrandname,
      'googleClientId': googleClientId.trim(),
      'googleClientSecret': googleClientSecret.trim(),
      'otpEmailWebhookUrl': otpEmailWebhookUrl ?? EnvConfig.otpEmailWebhookUrl,
      'otpEmailWebhookToken':
          otpEmailWebhookToken ?? EnvConfig.otpEmailWebhookToken,
    };
    await _sqliteDb.upsertEntityRecord(
      tableName: 'auth_provider_configs',
      recordId: 'DEFAULT',
      payload: config,
    );
    EnvConfig.configureAuthProvidersRuntime(
      smtpHost: smtpHost,
      smtpPort: smtpPort,
      smtpSenderEmail: smtpSenderEmail,
      smtpAppPassword: smtpAppPassword,
      smsWebhookUrl: smsWebhookUrl,
      smsProvider: smsProvider,
      smsApiKey: smsApiKey,
      smsApiSecret: smsApiSecret,
      smsBrandname: smsBrandname,
      googleClientId: googleClientId,
      googleClientSecret: googleClientSecret,
      otpEmailWebhookUrl: otpEmailWebhookUrl,
      otpEmailWebhookToken: otpEmailWebhookToken,
    );
    _notifyStoreChanged();
  }

  Map<String, dynamic> _authProviderConfigSnapshot() => {
    'smtpHost': EnvConfig.smtpHost,
    'smtpPort': EnvConfig.smtpPort,
    'smtpSenderEmail': EnvConfig.smtpSenderEmail,
    'smtpAppPassword': EnvConfig.smtpAppPassword,
    'smsWebhookUrl': EnvConfig.smsWebhookUrl,
    'smsProvider': EnvConfig.smsProvider,
    'smsApiKey': EnvConfig.smsApiKey,
    'smsApiSecret': EnvConfig.smsApiSecret,
    'smsBrandname': EnvConfig.smsBrandname,
    'googleClientId': EnvConfig.googleClientId,
    'googleClientSecret': EnvConfig.googleClientSecret,
    'otpEmailWebhookUrl': EnvConfig.otpEmailWebhookUrl,
    'otpEmailWebhookToken': EnvConfig.otpEmailWebhookToken,
  };

  Future<void> loadAuthProviderConfigsFromDatabase() async {
    try {
      final rows = await _sqliteDb.queryRows(
        'local_relational_entities',
        where: 'table_name = ? AND record_id = ?',
        whereArgs: ['auth_provider_configs', 'DEFAULT'],
        limit: 1,
      );
      if (rows.isEmpty) {
        // Preserve native provider settings when the next build omits dart-define.
        if (!kIsWeb &&
            (EnvConfig.isGoogleOAuthConfigured ||
                EnvConfig.isSmtpConfigured ||
                EnvConfig.isOtpEmailWebhookConfigured ||
                EnvConfig.isExternalSmsGatewayConfigured)) {
          await _sqliteDb.upsertEntityRecord(
            tableName: 'auth_provider_configs',
            recordId: 'DEFAULT',
            payload: _authProviderConfigSnapshot(),
          );
        }
        return;
      }
      final savedConfig = jsonDecode(
        rows.single['payload_json'] as String,
      ) as Map<String, dynamic>;
      // Empty legacy snapshots must not erase restored native credentials.
      final cfg = <String, dynamic>{
        ..._authProviderConfigSnapshot(),
        for (final entry in savedConfig.entries)
          if (entry.value != null &&
              (entry.value is! String ||
                  (entry.value as String).trim().isNotEmpty))
            entry.key: entry.value,
      };
      EnvConfig.configureAuthProvidersRuntime(
        smtpHost: cfg['smtpHost']?.toString(),
        smtpPort: int.tryParse(cfg['smtpPort']?.toString() ?? '465'),
        smtpSenderEmail: cfg['smtpSenderEmail']?.toString(),
        smtpAppPassword: cfg['smtpAppPassword']?.toString(),
        smsWebhookUrl: cfg['smsWebhookUrl']?.toString(),
        smsProvider: cfg['smsProvider']?.toString(),
        smsApiKey: cfg['smsApiKey']?.toString(),
        smsApiSecret: cfg['smsApiSecret']?.toString(),
        smsBrandname: cfg['smsBrandname']?.toString(),
        googleClientId: cfg['googleClientId']?.toString(),
        googleClientSecret: cfg['googleClientSecret']?.toString(),
        otpEmailWebhookUrl: cfg['otpEmailWebhookUrl']?.toString(),
        otpEmailWebhookToken: cfg['otpEmailWebhookToken']?.toString(),
      );
      if (!kIsWeb &&
          cfg.entries.any((entry) => savedConfig[entry.key] != entry.value)) {
        await _sqliteDb.upsertEntityRecord(
          tableName: 'auth_provider_configs',
          recordId: 'DEFAULT',
          payload: _authProviderConfigSnapshot(),
        );
      }
    } catch (_) {}
  }
}
