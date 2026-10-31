part of 'app_state_store.dart';

extension AppStateLiveDeliveryOps on AppStateStore {
  bool isRoomConnected(String room) => _liveRooms.containsKey(room);

  Future<void> connectLiveRoom(String room) async {
    if (_liveRooms.containsKey(room)) return;
    final service = LiveDeliveryService.instance;
    final role = await service.memberRole(room);
    _liveRoomRoles[room] = role;
    final order = orders.where((o) => o.trackingCode == room).firstOrNull;
    if (order != null) _publishedStatuses[room] = order.status.name;
    liveRoomMessages[room] = 'Đang kết nối';
    _liveRooms[room] = service
        .events(room)
        .listen(
          (rows) {
            _applyingLiveEvents = true;
            try {
              final sorted = [...rows]
                ..sort(
                  (a, b) =>
                      '${a['created_at']}'.compareTo('${b['created_at']}'),
                );
              for (final row in sorted) {
                final id = row['id'] as String;
                if (_seenLiveEvents.contains(id)) continue;
                _seenLiveEvents.add(id);
                if (_seenLiveEvents.length > 2000) {
                  _seenLiveEvents.remove(_seenLiveEvents.first);
                }
                final payload = Map<String, dynamic>.from(
                  row['payload'] as Map,
                );
                if (row['kind'] == 'chat') {
                  final text = payload['text'] as String?;
                  if (text == null || text.isEmpty) continue;
                  final msg = ChatMessageRecord(
                    id: id,
                    orderId: room,
                    senderName: 'Thành viên đơn hàng',
                    isCustomer: payload['isCustomer'] == true,
                    text: text,
                    timeLabel: 'Đồng bộ cloud',
                  );
                  if (chatMessages.any((m) => m.id == id)) continue;
                  chatMessages.add(msg);
                  unawaited(
                    _sqliteDb
                        .upsertRow('chat_messages_and_notifications', {
                          'id': id,
                          'record_type': 'CHAT',
                          'order_id': room,
                          'sender_name': msg.senderName,
                          'is_customer': msg.isCustomer ? 1 : 0,
                          'category': 'CHAT_MESSAGE',
                          'title': msg.senderName,
                          'content': text,
                          'target_group': 'INDIVIDUAL',
                          'time_label': msg.timeLabel,
                          'is_read': 0,
                          'created_at_ms':
                              DateTime.tryParse('${row['created_at']}')
                                  ?.millisecondsSinceEpoch ??
                              0,
                        })
                        .catchError((_) {}),
                  );
                } else if (row['kind'] == 'status' && order != null) {
                  final at = DateTime.tryParse('${row['created_at']}');
                  final next = OrderStatus.values
                      .where((s) => s.name == payload['status'])
                      .firstOrNull;
                  if (next == null ||
                      at == null ||
                      !at.isAfter(_lastRemoteStatus[room] ?? DateTime(1970))) {
                    continue;
                  }
                  _lastRemoteStatus[room] = at;
                  order.status = next;
                  _publishedStatuses[room] = next.name;
                  unawaited(
                    _sqliteDb
                        .upsertRow('orders', order.toSqlRow())
                        .catchError((_) {}),
                  );
                } else if (row['kind'] == 'pod') {
                  final path = payload['path'];
                  if (path is String &&
                      path.startsWith('$room/') &&
                      !path.contains('..')) {
                    liveEvidencePaths[room] = path;
                  }
                } else if (row['kind'] == 'gps' && order != null) {
                  final at = DateTime.tryParse('${row['created_at']}');
                  final lat = payload['latitude'];
                  final lng = payload['longitude'];
                  if (at == null ||
                      DateTime.now().difference(at).inMinutes > 2 ||
                      lat is! num ||
                      lng is! num ||
                      !lat.isFinite ||
                      !lng.isFinite ||
                      lat.abs() > 90 ||
                      lng.abs() > 180) {
                    continue;
                  }
                  final driver = drivers
                      .where(
                        (d) =>
                            d.fullName == order.assignedDriverName &&
                            d.licensePlate == order.assignedDriverPlate,
                      )
                      .firstOrNull;
                  if (driver != null) {
                    final point = GeoPoint(
                      latitude: lat.toDouble(),
                      longitude: lng.toDouble(),
                    );
                    verifiedDriverLocations[driver.id] = point;
                    driver.location = point;
                  }
                }
              }
              liveRoomMessages[room] = 'Đang đồng bộ trực tiếp';
              _notifyStoreChanged();
            } catch (_) {
              liveRoomMessages[room] = 'Có dữ liệu cloud không hợp lệ';
              _notifyStoreChanged();
            } finally {
              _applyingLiveEvents = false;
            }
          },
          onError: (Object error) {
            liveRoomMessages[room] =
                'Mất kết nối hoặc chưa được cấp quyền cloud';
            _notifyStoreChanged();
          },
        );
    _notifyStoreChanged();
  }

  Future<void> disconnectLiveRooms() async {
    for (final subscription in _liveRooms.values) {
      await subscription.cancel();
    }
    _liveRooms.clear();
    _liveRoomRoles.clear();
    _publishedStatuses.clear();
    _lastPublishedGps.clear();
    _lastRemoteStatus.clear();
    _seenLiveEvents.clear();
    liveRoomMessages.clear();
    liveEvidencePaths.clear();
    _notifyStoreChanged();
  }

  void _publishLiveChanges() {
    for (final room in _liveRooms.keys) {
      final role = _liveRoomRoles[room];
      if (role != 'driver' && role != 'operator') continue;
      final order = orders.where((o) => o.trackingCode == room).firstOrNull;
      if (order == null) continue;
      if (_publishedStatuses[room] != order.status.name) {
        final status = order.status.name;
        _publishedStatuses[room] = status;
        unawaited(
          LiveDeliveryService.instance
              .publish(room, 'status', {'status': status})
              .catchError((_) {
                if (_publishedStatuses[room] == status) {
                  _publishedStatuses.remove(room);
                }
                liveRoomMessages[room] = 'Chưa gửi được trạng thái cloud';
              }),
        );
      }
      if (role == 'driver' &&
          hasRealDeviceGpsFix &&
          lastLiveGpsFixAt != null &&
          DateTime.now().difference(lastLiveGpsFixAt!).inSeconds < 30 &&
          DateTime.now()
                  .difference(_lastPublishedGps[room] ?? DateTime(1970))
                  .inSeconds >=
              15 &&
          order.assignedDriverName == activeDriverName &&
          order.assignedDriverPlate ==
              drivers
                  .where((d) => d.id == activeDriverId)
                  .firstOrNull
                  ?.licensePlate) {
        _lastPublishedGps[room] = DateTime.now();
        unawaited(
          LiveDeliveryService.instance
              .publish(room, 'gps', {
                'latitude': liveDeviceLocation!.latitude,
                'longitude': liveDeviceLocation!.longitude,
              })
              .catchError((_) {
                liveRoomMessages[room] = 'Chưa gửi được vị trí cloud';
              }),
        );
      }
    }
  }

  void _publishLiveChat(
    String room,
    String text,
    bool isCustomer,
    String eventId,
  ) {
    if (!_liveRooms.containsKey(room)) return;
    unawaited(
      LiveDeliveryService.instance
          .publish(room, 'chat', {
            'text': text,
            'isCustomer': isCustomer,
          }, eventId: eventId)
          .catchError((_) {
            liveRoomMessages[room] =
                'Tin nhắn đã lưu trên máy, chưa gửi được cloud';
            _notifyStoreChanged();
          }),
    );
  }
}
