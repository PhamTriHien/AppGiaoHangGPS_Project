part of 'customer_subsystem_views.dart';

extension _CustomerGrabFoodViews on _CustomerSubsystemEntryState {
  GeoPoint _resolveGrabFoodCustomerPoint() {
    if (_store.liveDeviceLocation != null) {
      return _store.liveDeviceLocation!;
    }
    if (_pinnedDropoffLocation != null) {
      return _pinnedDropoffLocation!;
    }
    final rawDropoff = _foodDropoffCtrl.text.trim().isNotEmpty
        ? _foodDropoffCtrl.text.trim()
        : (_store.customerDefaultAddress.trim().isNotEmpty
              ? _store.customerDefaultAddress.trim()
              : _dropoffCtrl.text.trim());
    if (rawDropoff.isNotEmpty) {
      return SmartDispatchEngine.resolveAddressToCoordinate(
        rawDropoff,
        fallback: const GeoPoint(latitude: 10.7769, longitude: 106.6953),
      );
    }
    final firstSaved = _store.customerSavedAddresses.firstOrNull;
    if (firstSaved != null) return firstSaved.location;
    return const GeoPoint(latitude: 10.7769, longitude: 106.6953);
  }

  String _resolveGrabFoodDropoffText() {
    if (_foodDropoffCtrl.text.trim().isNotEmpty) {
      return _foodDropoffCtrl.text.trim();
    }
    if (_store.liveDeviceAddress.trim().isNotEmpty) {
      return _store.liveDeviceAddress.trim();
    }
    if (_store.customerDefaultAddress.trim().isNotEmpty) {
      return _store.customerDefaultAddress.trim();
    }
    final firstSaved = _store.customerSavedAddresses.firstOrNull;
    if (firstSaved != null && firstSaved.fullAddress.trim().isNotEmpty) {
      return firstSaved.fullAddress.trim();
    }
    return '';
  }

  int _cartQuantityFor(String itemId) {
    final entry = _grabFoodCart.where((e) => e.item.id == itemId).firstOrNull;
    return entry?.quantity ?? 0;
  }

  void _addGrabFoodItemToCart(
    BuildContext context,
    FoodMenuItemRecord item, {
    bool openDedicatedScreen = false,
  }) {
    String? switchedStoreMessage;
    _rebuildCustomerUi(() {
      if (_grabFoodCart.isNotEmpty) {
        final currentStore = _grabFoodCart.first.item.storeName
            .trim()
            .toLowerCase();
        if (currentStore != item.storeName.trim().toLowerCase()) {
          _grabFoodCart.clear();
          switchedStoreMessage =
              'Đã chuyển giỏ hàng sang quán "${item.storeName}".';
        }
      }
      final idx = _grabFoodCart.indexWhere((e) => e.item.id == item.id);
      if (idx >= 0) {
        final prev = _grabFoodCart[idx];
        _grabFoodCart[idx] = prev.copyWith(quantity: prev.quantity + 1);
      } else {
        _grabFoodCart.add(GrabFoodCartEntry(item: item, quantity: 1));
      }
      if (_foodDropoffCtrl.text.trim().isEmpty) {
        final fallbackAddr = _resolveGrabFoodDropoffText();
        if (fallbackAddr.isNotEmpty) {
          _foodDropoffCtrl.text = fallbackAddr;
        }
      }
      if (openDedicatedScreen) {
        _selectedScreenIndex = 13;
      }
    });
    if (switchedStoreMessage != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(switchedStoreMessage!)));
    }
  }

  void _decrementGrabFoodItemInCart(String itemId) {
    _rebuildCustomerUi(() {
      final idx = _grabFoodCart.indexWhere((e) => e.item.id == itemId);
      if (idx < 0) return;
      final prev = _grabFoodCart[idx];
      if (prev.quantity <= 1) {
        _grabFoodCart.removeAt(idx);
      } else {
        _grabFoodCart[idx] = prev.copyWith(quantity: prev.quantity - 1);
      }
    });
  }

  void _prefillCreateOrderFromFoodRecommendation(
    BuildContext context, {
    required String storeName,
    required String storeAddress,
    required GeoPoint storeLocation,
    required String dishName,
    required double priceVnd,
    bool isColdItem = false,
  }) {
    _rebuildCustomerUi(() {
      _userEditedPickupManually = true;
      _pickupCtrl.text = storeAddress;
      _pinnedPickupLocation = storeLocation;
      if (_dropoffCtrl.text.trim().isEmpty) {
        final defaultDrop = _resolveGrabFoodDropoffText();
        if (defaultDrop.isNotEmpty) {
          _dropoffCtrl.text = defaultDrop;
        }
      }
      _pkgCategory = 'Thực phẩm & Đồ uống';
      _pkgDescCtrl.text =
          '[GrabFood • $storeName] 1x $dishName${isColdItem ? " [GIỮ LẠNH]" : ""}';
      _codCtrl.text = priceVnd.round().toString();
      _weightCtrl.text = '0.8';
      _osrmPreviewPoints = null;
      _osrmDistMeters = null;
      _osrmDurationSec = null;
      _selectedScreenIndex = 2;
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã điền điểm lấy "$storeName" và món "$dishName" vào biểu mẫu Tạo đơn!',
          ),
        ),
      );
    }
  }

  /// Dải khám phá Gợi ý Ăn uống thông minh ngay trên Trang chủ Khách hàng (Screen 0)
  Widget _buildHomeGrabFoodDiscoveryStrip(BuildContext context) {
    final customerPt = _resolveGrabFoodCustomerPoint();
    final baseScale = (_store.baseFareConfig / 25000.0).clamp(0.4, 5.0);
    final kmScale = (_store.pricePerKmConfig / 5000.0).clamp(0.4, 5.0);
    final effectiveSlot = _selectedFoodMealSlot.effectiveSlotForNow();
    final recommendations = GrabFoodRecommendationEngine.rankRecommendedVenues(
      customerLocation: customerPt,
      partnerMenuItems: _store.merchantMenuItems,
      customerOrders: _store.customerOrders,
      selectedSlot: _selectedFoodMealSlot,
      quickFilter: GrabFoodQuickFilter.all,
      serviceType: DeliveryServiceType.express30m,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
      isPeakHour: _store.isPeakSurchargeActive,
    );
    final topVenues = recommendations.take(4).toList();
    final cartTotalItems = _grabFoodCart.fold<int>(
      0,
      (sum, e) => sum + e.quantity,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.5),
        boxShadow: const [
          BoxShadow(color: AppColors.ink, offset: Offset(0, 4), blurRadius: 14),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B14F),
                      border: Border.all(color: AppColors.ink, width: 1.2),
                    ),
                    child: const GhstButtonIcon(
                      Icons.restaurant_menu_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gợi ý Ăn uống quanh bạn (GrabFood)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          'Khung giờ: ${effectiveSlot.displayName} • Xếp hạng theo GPS & Sao',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: const Color(0xFF00B14F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                ),
                onPressed: () =>
                    _rebuildCustomerUi(() => _selectedScreenIndex = 13),
                icon: const GhstButtonIcon(Icons.shopping_bag_outlined, size: 15),
                label: Text(
                  cartTotalItems > 0
                      ? 'Thực đơn & Giỏ ($cartTotalItems)'
                      : 'Khám phá Thực đơn →',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: MealTimeSlot.values.map((slot) {
                final selected = _selectedFoodMealSlot == slot;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(slot.displayName, size: 15, color: AppColors.ink), visualDensity: VisualDensity.compact, selected: selected, selectedColor: AppColors.acid, backgroundColor: AppColors.paper, label: Text(
                      slot.displayName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ), onSelected: (_) =>
                        _rebuildCustomerUi(() => _selectedFoodMealSlot = slot),),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          if (topVenues.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              color: AppColors.paper,
              child: const Text(
                'Chưa có món phù hợp khung giờ này. Nhấn "Khám phá Thực đơn" để xem toàn bộ quán!',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isTwoCol = constraints.maxWidth >= 500;
                final cardWidth = isTwoCol
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: topVenues.map((venue) {
                    final heroDish = venue.matchedItems.first;
                    return SizedBox(
                      width: cardWidth,
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: AppColors.paper,
                          border: Border.all(color: AppColors.ink, width: 1.2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (venue.isPartnerMerchant)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    color: AppColors.violet,
                                    child: const Text(
                                      'ĐỐI TÁC B2B',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                if (venue.hasPromo)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    color: AppColors.pink,
                                    child: const Text(
                                      'ƯU ĐÃI',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                if (venue.hasEcoPackaging)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    color: const Color(0xFFDCFCE7),
                                    child: const Text(
                                      'QUÁN XANH',
                                      style: TextStyle(
                                        color: Color(0xFF166534),
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                Text(
                                  '★ ${venue.rating.toStringAsFixed(1)} • ${venue.roadDistanceKm.toStringAsFixed(1)} km • ~${venue.estimatedTotalEtaMinutes}p',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'Consolas',
                                    color: AppColors.ink,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              venue.storeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${heroDish.name} • ${CurrencyFormatter.formatVnd(heroDish.priceVnd)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF00853B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: AppColors.ink,
                                    foregroundColor: AppColors.acid,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 5,
                                    ),
                                    minimumSize: Size.zero,
                                  ),
                                  onPressed: () => _addGrabFoodItemToCart(
                                    context,
                                    heroDish,
                                    openDedicatedScreen: true,
                                  ),
                                  icon: const GhstButtonIcon(Icons.add, size: 14),
                                  label: const Text(
                                    'Chọn món',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    minimumSize: Size.zero,
                                  ),
                                  onPressed: () =>
                                      _prefillCreateOrderFromFoodRecommendation(
                                        context,
                                        storeName: venue.storeName,
                                        storeAddress: venue.storeAddress,
                                        storeLocation: venue.storeLocation,
                                        dishName: heroDish.name,
                                        priceVnd: heroDish.priceVnd,
                                        isColdItem: heroDish.isColdItem,
                                      ),
                                  icon: const GhstButtonIcon(
                                    Icons.edit_location_alt_outlined,
                                    size: 13,
                                  ),
                                  label: const Text(
                                    'Điền Tạo đơn',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  /// Màn hình chuyên biệt Ăn uống & Gợi ý Thông minh (GrabFood) - Screen Index 13
  Widget _buildGrabFoodDiscoveryAndCartView(BuildContext context) {
    if (_foodDropoffCtrl.text.trim().isEmpty) {
      final initialDrop = _resolveGrabFoodDropoffText();
      if (initialDrop.isNotEmpty) {
        _foodDropoffCtrl.text = initialDrop;
      }
    }
    final customerPt = _resolveGrabFoodCustomerPoint();
    final baseScale = (_store.baseFareConfig / 25000.0).clamp(0.4, 5.0);
    final kmScale = (_store.pricePerKmConfig / 5000.0).clamp(0.4, 5.0);
    final effectiveSlot = _selectedFoodMealSlot.effectiveSlotForNow();

    final recommendations = GrabFoodRecommendationEngine.rankRecommendedVenues(
      customerLocation: customerPt,
      partnerMenuItems: _store.merchantMenuItems,
      customerOrders: _store.customerOrders,
      selectedSlot: _selectedFoodMealSlot,
      quickFilter: _selectedFoodQuickFilter,
      searchQuery: _foodSearchCtrl.text,
      serviceType: _foodDeliveryService,
      baseFareScale: baseScale,
      pricePerKmScale: kmScale,
      isPeakHour: _store.isPeakSurchargeActive,
    );

    final reorderFavorites =
        GrabFoodRecommendationEngine.extractReorderFavorites(
          customerOrders: _store.customerOrders,
          partnerMenuItems: _store.merchantMenuItems,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.techBg,
            border: Border.all(color: AppColors.ink, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFF00B14F),
                offset: Offset(0, 4), blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    color: const Color(0xFF00B14F),
                    child: const Text(
                      'GRABFOOD SMART DINING',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    color: AppColors.acid,
                    child: Text(
                      'ĐANG GỢI Ý: ${effectiveSlot.displayName.toUpperCase()}',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Đặt món ngon quanh vị trí GPS • Tự động tính cước & giữ lạnh',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${effectiveSlot.subtitle} • Tìm thấy ${recommendations.length} quán phù hợp quanh (${customerPt.latitude.toStringAsFixed(4)}, ${customerPt.longitude.toStringAsFixed(4)})',
                style: const TextStyle(
                  color: AppColors.techMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                color: Colors.white,
                child: TextField(
                  controller: _foodDropoffCtrl,
                  onChanged: (_) => _rebuildCustomerUi(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Địa chỉ nhận đồ ăn của bạn',
                    hintText: 'Nhập số nhà, tòa nhà hoặc bấm định vị GPS...',
                    prefixIcon: const GhstButtonIcon(
                      Icons.place_rounded,
                      color: AppColors.pink,
                      size: 19,
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Lấy vị trí GPS thiết bị hiện tại',
                      onPressed: () async {
                        final pos = await _store.acquireCustomerDeviceGps();
                        if (!mounted || !context.mounted) return;
                        if (pos == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppColors.danger,
                              content: Text(_store.liveGpsStatusMessage),
                            ),
                          );
                          return;
                        }
                        final addr =
                            _store.liveDeviceAddress.trim().isNotEmpty
                            ? _store.liveDeviceAddress.trim()
                            : await SmartDispatchEngine
                                  .reverseGeocodeCoordinate(pos);
                        if (!mounted) return;
                        _rebuildCustomerUi(() {
                          _pinnedDropoffLocation = pos;
                          _foodDropoffCtrl.text = addr;
                        });
                      },
                      icon: const GhstButtonIcon(
                        Icons.my_location_rounded,
                        color: Color(0xFF0284C7),
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              if (_store.customerSavedAddresses.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _store.customerSavedAddresses.map((addr) {
                    return ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.white,
                      avatar: const GhstButtonIcon(
                        Icons.bookmark_rounded,
                        size: 13,
                        color: AppColors.violet,
                      ),
                      label: Text(
                        'Giao về: ${addr.label}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      onPressed: () => _rebuildCustomerUi(() {
                        _foodDropoffCtrl.text = addr.fullAddress;
                        _pinnedDropoffLocation = addr.location;
                      }),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.ink, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _foodSearchCtrl,
                onChanged: (_) => _rebuildCustomerUi(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText:
                      'Tìm quán ăn, phở, cơm tấm, bánh mì, trà sữa, healthy...',
                  prefixIcon: const GhstButtonIcon(Icons.search_rounded, size: 20),
                  suffixIcon: _foodSearchCtrl.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'Xóa từ khóa',
                          onPressed: () => _rebuildCustomerUi(() {
                            _foodSearchCtrl.clear();
                          }),
                          icon: const GhstButtonIcon(Icons.clear_rounded, size: 18),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Khung giờ bữa ăn thông minh:',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: MealTimeSlot.values.map((slot) {
                  final selected = _selectedFoodMealSlot == slot;
                  return ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(slot.displayName, size: 15, color: AppColors.ink), visualDensity: VisualDensity.compact, selected: selected, selectedColor: AppColors.acid, backgroundColor: AppColors.paper, label: Text(
                      slot.displayName,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ), onSelected: (_) =>
                        _rebuildCustomerUi(() => _selectedFoodMealSlot = slot),);
                }).toList(),
              ),
              const SizedBox(height: 10),
              const Text(
                'Bộ lọc nhanh GrabFood:',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: GrabFoodQuickFilter.values.map((flt) {
                  final selected = _selectedFoodQuickFilter == flt;
                  return FilterChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(flt.label, size: 15, color: (selected) ? const Color(0xFF166534) : AppColors.ink), visualDensity: VisualDensity.compact, selected: selected, selectedColor: const Color(0xFFDCFCE7), backgroundColor: AppColors.paper, label: Text(
                      flt.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ), onSelected: (_) =>
                        _rebuildCustomerUi(() => _selectedFoodQuickFilter = flt),);
                }).toList(),
              ),
            ],
          ),
        ),
        if (reorderFavorites.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              border: Border.all(color: AppColors.ink, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    GhstButtonIcon(
                      Icons.history_edu_rounded,
                      size: 18,
                      color: Color(0xFFB45309),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Đặt lại món quen của bạn',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: reorderFavorites.map((fav) {
                    return Container(
                      constraints: const BoxConstraints(maxWidth: 360),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.ink, width: 1.1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${fav.storeName} (${fav.orderCount} lần đặt)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            fav.dishSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (fav.matchedCatalogItems.isNotEmpty)
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: const Color(0xFF00B14F),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                  ),
                                  onPressed: () {
                                    _rebuildCustomerUi(() {
                                      _grabFoodCart
                                        ..clear()
                                        ..addAll(
                                          fav.matchedCatalogItems.map(
                                            (it) => GrabFoodCartEntry(
                                              item: it,
                                              quantity: 1,
                                            ),
                                          ),
                                        );
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Đã nạp lại món quen từ "${fav.storeName}" vào giỏ hàng!',
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const GhstButtonIcon(Icons.replay_rounded, size: 13),
                                  label: const Text(
                                    'Đặt lại vào giỏ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                ),
                                onPressed: () =>
                                    _prefillCreateOrderFromFoodRecommendation(
                                      context,
                                      storeName: fav.storeName,
                                      storeAddress: fav.storeAddress,
                                      storeLocation: fav.storeLocation,
                                      dishName: fav.dishSummary,
                                      priceVnd: fav.lastFoodSubtotalVnd,
                                    ),
                                icon: const GhstButtonIcon.glyph(GhstActionKind.edit, size: 16),

                                label: const Text(
                                  'Điền Tạo đơn',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final isSplitDesktop = constraints.maxWidth >= 960;
            final venuesColumn = _buildRecommendedVenuesList(
              context,
              recommendations,
            );
            final cartColumn = _buildGrabFoodCartPanel(context, customerPt);

            if (isSplitDesktop) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 62, child: venuesColumn),
                  const SizedBox(width: 16),
                  Expanded(flex: 38, child: cartColumn),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_grabFoodCart.isNotEmpty) ...[
                  cartColumn,
                  const SizedBox(height: 14),
                ],
                venuesColumn,
                if (_grabFoodCart.isEmpty) ...[
                  const SizedBox(height: 14),
                  cartColumn,
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecommendedVenuesList(
    BuildContext context,
    List<GrabFoodVenueRecommendation> recommendations,
  ) {
    if (recommendations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.ink, width: 1.5),
        ),
        child: Column(
          children: [
            const GhstButtonIcon(
              Icons.no_meals_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            const Text(
              'Không tìm thấy quán ăn phù hợp với bộ lọc hiện tại',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14.5,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Hãy thử đổi khung giờ bữa ăn sang "Tự động theo giờ" hoặc xóa bộ lọc nhanh.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _rebuildCustomerUi(() {
                _foodSearchCtrl.clear();
                _selectedFoodMealSlot = MealTimeSlot.auto;
                _selectedFoodQuickFilter = GrabFoodQuickFilter.all;
              }),
              icon: const GhstButtonIcon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Đặt lại bộ lọc'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: recommendations.map((venue) {
        final firstDish = venue.matchedItems.first;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: venue.isPartnerMerchant
                  ? AppColors.violet
                  : AppColors.ink,
              width: venue.isPartnerMerchant ? 1.8 : 1.4,
            ),
            boxShadow: const [
              BoxShadow(
                color: AppColors.ink,
                offset: Offset(0, 4), blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (venue.isPartnerMerchant)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          color: AppColors.violet,
                          child: const Text(
                            'ĐỐI TÁC B2B',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      if (venue.isFavoriteVenue)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          color: const Color(0xFFFEF3C7),
                          child: const Text(
                            'QUÁN QUEN',
                            style: TextStyle(
                              color: Color(0xFF92400E),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      if (venue.hasEcoPackaging)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          color: const Color(0xFFDCFCE7),
                          child: const Text(
                            'QUÁN XANH • ÍT NHỰA',
                            style: TextStyle(
                              color: Color(0xFF166534),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      if (venue.hasPromo)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          color: AppColors.pink,
                          child: const Text(
                            'ƯU ĐÃI MÓN NGON',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () => _prefillCreateOrderFromFoodRecommendation(
                      context,
                      storeName: venue.storeName,
                      storeAddress: venue.storeAddress,
                      storeLocation: venue.storeLocation,
                      dishName: firstDish.name,
                      priceVnd: firstDish.priceVnd,
                      isColdItem: firstDish.isColdItem,
                    ),
                    icon: const GhstButtonIcon(
                      Icons.edit_location_alt_outlined,
                      size: 14,
                    ),
                    label: const Text(
                      'Điền Tạo đơn',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                venue.storeName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                venue.storeAddress,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    '★ ${venue.rating.toStringAsFixed(1)} đánh giá',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFB45309),
                    ),
                  ),
                  Text(
                    '📍 Cách ${venue.roadDistanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    '⏱ Giao ~${venue.estimatedTotalEtaMinutes} phút (chế biến ${venue.prepMinutes}p)',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    '🛵 Ship dự kiến ${CurrencyFormatter.formatVnd(venue.estimatedDeliveryFeeVnd)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF00853B),
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),
              ...venue.matchedItems.map((dish) {
                final qtyInCart = _cartQuantityFor(dish.id);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: qtyInCart > 0
                        ? const Color(0xFFF0FDF4)
                        : AppColors.paper,
                    border: Border.all(
                      color: qtyInCart > 0
                          ? const Color(0xFF00B14F)
                          : AppColors.ink,
                      width: qtyInCart > 0 ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dish.name,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.ink,
                                  ),
                                ),
                                if (dish.description.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    dish.description,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 5),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      CurrencyFormatter.formatVnd(
                                        dish.priceVnd,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        fontFamily: 'Consolas',
                                        color: Color(0xFF00853B),
                                      ),
                                    ),
                                    Text(
                                      'Đã bán ${dish.soldCount}+',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if (dish.isColdItem)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1.5,
                                        ),
                                        color: const Color(0xFFE0F2FE),
                                        child: const Text(
                                          '❄ ĐỒ LẠNH',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF0369A1),
                                          ),
                                        ),
                                      ),
                                    if (dish.isEcoPackaging)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1.5,
                                        ),
                                        color: const Color(0xFFDCFCE7),
                                        child: const Text(
                                          '🌱 HỘP BÃ MÍA',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF166534),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (qtyInCart <= 0)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: const Color(0xFF00B14F),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                              ),
                              onPressed: () =>
                                  _addGrabFoodItemToCart(context, dish),
                              icon: const GhstButtonIcon(Icons.add, size: 15),
                              label: const Text(
                                'Chọn',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            )
                          else
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Giảm số lượng',
                                  onPressed: () =>
                                      _decrementGrabFoodItemInCart(dish.id),
                                  icon: const GhstButtonIcon(
                                    Icons.remove_circle_outline,
                                    color: AppColors.danger,
                                    size: 20,
                                  ),
                                ),
                                Text(
                                  '$qtyInCart',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                    fontFamily: 'Consolas',
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Thêm số lượng',
                                  onPressed: () =>
                                      _addGrabFoodItemToCart(context, dish),
                                  icon: const GhstButtonIcon(
                                    Icons.add_circle_rounded,
                                    color: Color(0xFF00B14F),
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGrabFoodCartPanel(BuildContext context, GeoPoint dropoffPt) {
    final totalQty = _grabFoodCart.fold<int>(0, (s, e) => s + e.quantity);
    final foodSubtotalVnd = _grabFoodCart
        .fold<double>(0.0, (s, e) => s + e.lineTotalVnd)
        .roundToDouble();
    final hasColdItem = _grabFoodCart.any((e) => e.item.isColdItem);
    final headItem = _grabFoodCart.firstOrNull?.item;

    final roadMeters = headItem == null
        ? 0
        : (GeoMath.distanceMeters(headItem.storeLocation, dropoffPt) * 1.28)
              .round()
              .clamp(1500, 45000);
    final durSec = headItem == null
        ? 0
        : ((roadMeters / 1000.0) * 180).round();
    final estWeightKg = (totalQty * 0.45).clamp(0.5, 18.0);

    double extraGeofenceAndCold = headItem == null
        ? 0.0
        : _store.computeGeofenceSurchargeForPoint(dropoffPt);
    if (headItem != null && _store.isWeatherSurchargeActive) {
      extraGeofenceAndCold += _store.badWeatherSurchargeConfig;
    }
    if (headItem != null && estWeightKg > 5.0) {
      extraGeofenceAndCold += ((estWeightKg - 5.0) * 3000).roundToDouble();
    }
    if (headItem != null && hasColdItem) {
      extraGeofenceAndCold += 10000;
    }

    final baseScale = (_store.baseFareConfig / 25000.0).clamp(0.4, 5.0);
    final kmScale = (_store.pricePerKmConfig / 5000.0).clamp(0.4, 5.0);

    final preDiscountShipping = headItem == null
        ? null
        : PricingEstimate.calculate(
            serviceType: _foodDeliveryService,
            distanceMeters: roadMeters,
            durationSeconds: durSec,
            isPeakHour: _store.isPeakSurchargeActive,
            geofenceSurcharge: extraGeofenceAndCold,
            baseFareScale: baseScale,
            pricePerKmScale: kmScale,
            configuredStandardPeakSurcharge: _store.peakHourSurchargeConfig,
            greenFundContribution: _foodGreenFund,
            preferEcoEv: _foodPreferEcoEv,
          );

    double voucherDiscount = 0;
    final usableVouchers = _store.vouchers.where((v) => v.isUsable).toList();
    if (preDiscountShipping != null &&
        _selectedFoodVoucherCode != null &&
        _selectedFoodVoucherCode!.trim().isNotEmpty) {
      final matchedV = usableVouchers
          .where(
            (v) =>
                v.code.toUpperCase() ==
                _selectedFoodVoucherCode!.trim().toUpperCase(),
          )
          .firstOrNull;
      if (matchedV != null &&
          (preDiscountShipping.totalAmount + foodSubtotalVnd) >=
              matchedV.minOrderValue) {
        voucherDiscount = matchedV.isPercentage
            ? (preDiscountShipping.totalAmount *
                      (matchedV.discountValue / 100.0))
                  .clamp(0.0, matchedV.maxDiscount)
            : matchedV.discountValue;
      }
    }

    final finalShipping = headItem == null
        ? null
        : PricingEstimate.calculate(
            serviceType: _foodDeliveryService,
            distanceMeters: roadMeters,
            durationSeconds: durSec,
            isPeakHour: _store.isPeakSurchargeActive,
            geofenceSurcharge: extraGeofenceAndCold,
            voucherDiscount: voucherDiscount,
            baseFareScale: baseScale,
            pricePerKmScale: kmScale,
            configuredStandardPeakSurcharge: _store.peakHourSurchargeConfig,
            greenFundContribution: _foodGreenFund,
            preferEcoEv: _foodPreferEcoEv,
          );

    final grandTotalVnd =
        foodSubtotalVnd + (finalShipping?.totalAmount ?? 0.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.6),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF00B14F),
            offset: Offset(0, 4), blurRadius: 14,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const GhstButtonIcon(
                Icons.shopping_bag_rounded,
                color: Color(0xFF00B14F),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Giỏ hàng GrabFood ($totalQty món)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (_grabFoodCart.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.danger,
                  ),
                  onPressed: () =>
                      _rebuildCustomerUi(() => _grabFoodCart.clear()),
                  icon: const GhstButtonIcon.glyph(GhstActionKind.delete, size: 16),

                  label: const Text(
                    'Xóa giỏ',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          const Divider(height: 16),
          if (_grabFoodCart.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              color: AppColors.paper,
              child: const Column(
                children: [
                  GhstButtonIcon(
                    Icons.fastfood_outlined,
                    size: 30,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Chưa có món ăn nào trong giỏ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: AppColors.ink,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Nhấn nút "+ Chọn" ở bất kỳ món ngon nào bên cạnh để tính phí ship GPS tức thì!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xFFF0FDF4),
              child: Text(
                'Quán đang chọn: ${headItem!.storeName}\nLấy món tại: ${headItem.storeAddress}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ..._grabFoodCart.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.quantity}x ${entry.item.name}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            CurrencyFormatter.formatVnd(entry.lineTotalVnd),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Consolas',
                              color: Color(0xFF00853B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _decrementGrabFoodItemInCart(entry.item.id),
                      icon: const GhstButtonIcon(Icons.remove_circle_outline, size: 18),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _addGrabFoodItemToCart(context, entry.item),
                      icon: const GhstButtonIcon(
                        Icons.add_circle_outline,
                        size: 18,
                        color: Color(0xFF00B14F),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (hasColdItem) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  border: Border.all(color: const Color(0xFF0284C7)),
                ),
                child: const Text(
                  '❄ Giỏ có đồ lạnh: Tự động trang bị túi giữ nhiệt chống tan đá (+10.000đ)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0369A1),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _foodKitchenNoteCtrl,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Ghi chú cho quán (VD: ít đá, không hành...)',
                prefixIcon: GhstButtonIcon(Icons.sticky_note_2_outlined, size: 17),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tốc độ giao món:',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                (DeliveryServiceType.express30m, 'Siêu tốc 30p'),
                (DeliveryServiceType.sameDay2h, 'Ghép đơn 2H (-rẻ)'),
                (DeliveryServiceType.standard, 'Tiêu chuẩn'),
              ].map((opt) {
                final selected = _foodDeliveryService == opt.$1;
                return ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(opt.$2, size: 15, color: AppColors.ink), visualDensity: VisualDensity.compact, selected: selected, selectedColor: AppColors.acid, label: Text(
                    opt.$2,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ), onSelected: (_) => _rebuildCustomerUi(
                    () => _foodDeliveryService = opt.$1,
                  ),);
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '⚡ Giao Xanh bằng Xe máy điện (Xanh SM EV)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Switch.adaptive(
                  activeThumbColor: const Color(0xFF00B14F),
                  value: _foodPreferEcoEv,
                  onChanged: (v) =>
                      _rebuildCustomerUi(() => _foodPreferEcoEv = v),
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '🌱 Đóng góp Quỹ Xanh trồng cây (+1.000đ)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Switch.adaptive(
                  activeThumbColor: const Color(0xFF00B14F),
                  value: _foodGreenFund,
                  onChanged: (v) =>
                      _rebuildCustomerUi(() => _foodGreenFund = v),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                const Text(
                  'Mã giảm phí giao món:',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                ),
                InkWell(
                  onTap: () => _openPromoHubAtTab(1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      border: Border.all(color: const Color(0xFFEE4D2D)),
                    ),
                    child: const Text(
                      '🎁 Vòng Xoay / Hộp Mù săn mã →',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFEE4D2D),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (usableVouchers.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: usableVouchers.take(4).map((v) {
                  final selected = _selectedFoodVoucherCode == v.code;
                  return FilterChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel('${v.code} (${v.discountLabel})', size: 15, color: AppColors.ink), visualDensity: VisualDensity.compact, selected: selected, selectedColor: AppColors.acid, label: Text(
                      '${v.code} (${v.discountLabel})',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ), onSelected: (on) => _rebuildCustomerUi(() {
                      _selectedFoodVoucherCode = on ? v.code : null;
                    }),);
                }).toList(),
              ),
            ],
            const Divider(height: 18),
            _buildGrabFoodPriceLine(
              'Tiền món ăn ($totalQty món)',
              CurrencyFormatter.formatVnd(foodSubtotalVnd),
            ),
            if (finalShipping != null) ...[
              _buildGrabFoodPriceLine(
                'Cước giao GPS (${(roadMeters / 1000.0).toStringAsFixed(1)} km)',
                CurrencyFormatter.formatVnd(
                  finalShipping.baseFare + finalShipping.distanceFare,
                ),
              ),
              if (finalShipping.surchargeFee +
                      finalShipping.greenContributionFee >
                  0)
                _buildGrabFoodPriceLine(
                  'Phụ phí (giữ lạnh / cao điểm / Quỹ Xanh)',
                  CurrencyFormatter.formatVnd(
                    finalShipping.surchargeFee +
                        finalShipping.greenContributionFee,
                  ),
                ),
              if (finalShipping.discountAmount > 0)
                _buildGrabFoodPriceLine(
                  'Ưu đãi Voucher',
                  '-${CurrencyFormatter.formatVnd(finalShipping.discountAmount)}',
                  valueColor: AppColors.pink,
                ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Phương thức thanh toán',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final method in const [
                  'Tiền mặt khi nhận món',
                  'Chuyển khoản Ngân hàng',
                  'Quét mã VietQR',
                ])
                  ChoiceChip(showCheckmark: false, avatar: GhstButtonIcon.forLabel(method, size: 15, color: (_foodPaymentMethod == method) ? Colors.white : null), visualDensity: VisualDensity.compact, label: Text(
                      method,
                      style: const TextStyle(fontSize: 11.5),
                    ), selected: _foodPaymentMethod == method, selectedColor: const Color(0xFF00B14F), labelStyle: TextStyle(
                      color: _foodPaymentMethod == method
                          ? Colors.white
                          : AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ), onSelected: (_) => _rebuildCustomerUi(
                      () => _foodPaymentMethod = method,
                    ),),
              ],
            ),
            if (_foodPaymentMethod != 'Tiền mặt khi nhận món') ...[
              const SizedBox(height: 8),
              VietQrBankPaymentPanel(
                amountVnd: grandTotalVnd,
                orderReference: 'DON DO AN',
                selectedPayerBankBin: _selectedBankBin,
                compact: true,
                onPayerBankChanged: (bank) => _rebuildCustomerUi(() {
                  _selectedBankBin = bank.bin;
                  _selectedBankShortName = bank.shortName;
                }),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              color: AppColors.paper,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _foodPaymentMethod == 'Tiền mặt khi nhận món'
                          ? 'Tổng thanh toán khi nhận món:'
                          : 'Tổng thanh toán Ngân hàng · VietQR:',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatVnd(grandTotalVnd),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Consolas',
                      color: Color(0xFF00853B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00B14F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: () async {
                final dropAddr = _foodDropoffCtrl.text.trim().isNotEmpty
                    ? _foodDropoffCtrl.text.trim()
                    : _resolveGrabFoodDropoffText();
                if (dropAddr.length < 5) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppColors.danger,
                      content: Text(
                        'Vui lòng nhập địa chỉ nhận đồ ăn (hoặc bấm định vị GPS) trước khi Đặt món!',
                      ),
                    ),
                  );
                  return;
                }
                final resolvedDropPt = _foodDropoffCtrl.text.trim().isNotEmpty
                    ? SmartDispatchEngine.resolveAddressToCoordinate(
                        dropAddr,
                        fallback: dropoffPt,
                      )
                    : dropoffPt;
                final isFoodBankQr =
                    _foodPaymentMethod != 'Tiền mặt khi nhận món';
                final created = _store.createGrabFoodOrder(
                  cartEntries: List<GrabFoodCartEntry>.from(_grabFoodCart),
                  dropoffAddress: dropAddr,
                  customDropoffLocation: resolvedDropPt,
                  serviceType: _foodDeliveryService,
                  voucherCode: _selectedFoodVoucherCode,
                  preferEcoEv: _foodPreferEcoEv,
                  greenFundContributed: _foodGreenFund,
                  kitchenNote: _foodKitchenNoteCtrl.text,
                );
                if (isFoodBankQr && context.mounted) {
                  await _showLegacyBankQrPaymentDialog(created);
                }
                if (!context.mounted) return;
                _rebuildCustomerUi(() {
                  _grabFoodCart.clear();
                  _foodKitchenNoteCtrl.clear();
                  _selectedFoodVoucherCode = null;
                  _selectedScreenIndex = 4;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Đã đặt món thành công (${created.trackingCode})! Đang điều phối tài xế gần quán nhất...',
                    ),
                  ),
                );
              },
              icon: const GhstButtonIcon(Icons.delivery_dining_rounded, size: 19),
              label: const Text(
                'Đặt món & Giao ngay',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrabFoodPriceLine(
    String label,
    String value, {
    Color valueColor = AppColors.ink,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              fontFamily: 'Consolas',
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
