import '../../core/integrations/cloud_account_session.dart';
import '../../core/network/public_json_api.dart';

enum CloudOrderView { orders, queue, accounts }

/// In-memory cloud data bound to a verified session, never the legacy cache.
class CloudOrdersRepository {
  CloudOrdersRepository({required this.session, this.admin = false}) {
    session.addListener(_onSessionChanged);
  }

  final CloudAccountSession session;
  final bool admin;
  var _orders = const <Map<String, dynamic>>[];
  var _accounts = const <Map<String, dynamic>>[];
  var _merchants = const <Map<String, dynamic>>[];
  String _scope = '';
  int _revision = -1, _generation = 0;
  bool _disposed = false, _hasMore = false, _pendingMore = false;
  CloudOrderView? _view;
  (String, String)? _cursor;
  Future<void>? _pending;

  bool _allowed(CloudOrderView view) {
    if (_disposed || !session.verified) return false;
    final operator = admin && session.isOperator;
    if (admin && !operator) return false;
    if (view == CloudOrderView.accounts) return operator;
    if (view == CloudOrderView.queue) {
      return session.hasRole('driver');
    }
    return session.canUseBusiness || operator;
  }

  bool get _visible =>
      _view != null &&
      _allowed(_view!) &&
      _scope == session.service.identityScope &&
      _revision == session.revision;

  List<Map<String, dynamic>> get orders => _visible ? _orders : const [];
  List<Map<String, dynamic>> get accounts => _visible ? _accounts : const [];
  List<Map<String, dynamic>> get merchants => _visible ? _merchants : const [];
  bool get hasMore => _visible && _hasMore;

  void _onSessionChanged() {
    if (!_visible) clear();
  }

  void _resetData() {
    _orders = const [];
    _accounts = const [];
    _merchants = const [];
    _hasMore = false;
    _cursor = null;
  }

  void clear() {
    _generation++;
    _pending = null;
    _view = null;
    _scope = '';
    _revision = -1;
    _resetData();
  }

  Future<void> load({
    CloudOrderView view = CloudOrderView.orders,
    bool more = false,
  }) {
    if (!_allowed(view)) {
      clear();
      return Future.error(StateError('Cloud account is not authorized'));
    }
    if (!_visible || _view != view) {
      clear();
      _view = view;
      _scope = session.service.identityScope;
      _revision = session.revision;
    }
    if (more && !_hasMore) return Future.value();
    if (_pending != null && _pendingMore == more) return _pending!;
    final generation = ++_generation;
    _pendingMore = more;
    late final Future<void> operation;
    operation = _fetch(generation, view, more).whenComplete(() {
      if (identical(_pending, operation)) _pending = null;
    });
    _pending = operation;
    return operation;
  }

  bool _current(int generation) => generation == _generation && _visible;

  Future<void> _fetch(int generation, CloudOrderView view, bool more) async {
    final previous = more ? _orders : const <Map<String, dynamic>>[];
    final cursor = more ? _cursor : null;
    try {
      if (view == CloudOrderView.accounts) {
        final response = await session.service.request('accounts');
        if (_current(generation)) {
          _accounts = _rows(response['accounts']);
        }
        return;
      }
      final response = await session.service.request(
        'orders',
        query: {
          if (view == CloudOrderView.queue) 'queue': 'true',
          if (cursor != null) 'before': cursor.$1,
          if (cursor != null) 'before_id': cursor.$2,
        },
      );
      if (!_current(generation)) return;
      final rows = _rows(response['orders']);
      if (rows.length > 50 ||
          rows.any((row) => row['id'] is! String || '${row['id']}'.isEmpty)) {
        throw const FormatException('Invalid cloud order page');
      }
      (String, String)? next;
      if (rows.length == 50) {
        final timestamp = rows.last['created_at'];
        if (timestamp is! String || DateTime.tryParse(timestamp) == null) {
          throw const FormatException('Invalid cloud order cursor');
        }
        next = (timestamp, rows.last['id'] as String);
        if (next == cursor) {
          throw const FormatException('Cloud order cursor did not advance');
        }
      }
      var merchants = _merchants;
      if (!more &&
          session.canCreateShippingOrder &&
          !session.hasRole('merchant')) {
        final result = await session.service.request('merchants');
        if (!_current(generation)) return;
        merchants = _rows(result['merchants']);
      }
      // Merge by ID, including updates in overlapping pages; use the raw page
      // cursor so deduplication cannot make the next request repeat a page.
      final merged = <String, Map<String, dynamic>>{
        for (final row in previous) row['id'] as String: row,
        for (final row in rows) row['id'] as String: row,
      };
      _orders = List.unmodifiable(merged.values);
      _merchants = merchants;
      _cursor = next;
      _hasMore = next != null;
    } catch (error) {
      if (!_current(generation)) return;
      if (!more ||
          error is PublicApiException &&
              [401, 403].contains(error.statusCode)) {
        _resetData();
      }
      rethrow;
    }
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) throw const FormatException('Invalid cloud rows');
    return List.unmodifiable(
      value.map((row) {
        if (row is! Map) throw const FormatException('Invalid cloud row');
        return _freeze(row) as Map<String, dynamic>;
      }),
    );
  }

  dynamic _freeze(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.unmodifiable(
        value.map((key, item) => MapEntry(key as String, _freeze(item))),
      );
    }
    if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
    return value;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    session.removeListener(_onSessionChanged);
    clear();
  }
}
