import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../widgets/cloud_order_form.dart';
import '../widgets/cloud_session_boundary.dart';
import '../widgets/ghst_button_icon.dart';

class GhstShippingScreen extends StatelessWidget {
  const GhstShippingScreen({
    super.key,
    required this.session,
    required this.onCreated,
    this.onOrderCreated,
    this.initialDetails,
  });
  final CloudAccountSession session;
  final VoidCallback onCreated;
  final ValueChanged<Map<String, dynamic>>? onOrderCreated;
  final Map<String, dynamic>? initialDetails;

  @override
  Widget build(BuildContext context) => CloudSessionBoundary(
    session: session,
    builder: (_, lease) => _ShippingFormHost(
      lease: lease,
      onCreated: onCreated,
      onOrderCreated: onOrderCreated,
      initialDetails: initialDetails,
    ),
  );
}

class _ShippingFormHost extends StatefulWidget {
  const _ShippingFormHost({
    required this.lease,
    required this.onCreated,
    this.onOrderCreated,
    this.initialDetails,
  });
  final CloudSessionLease lease;
  final VoidCallback onCreated;
  final ValueChanged<Map<String, dynamic>>? onOrderCreated;
  final Map<String, dynamic>? initialDetails;
  @override
  State<_ShippingFormHost> createState() => _ShippingFormHostState();
}

class _ShippingFormHostState extends State<_ShippingFormHost> {
  List<Map<String, dynamic>>? _merchants;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.lease.valid) return;
    setState(() {
      _failed = false;
      _merchants = null;
    });
    try {
      final session = widget.lease.session;
      final response = session.hasRole('merchant')
          ? <String, dynamic>{'merchants': <dynamic>[]}
          : await session.service.request('merchants');
      if (!mounted || !widget.lease.valid) return;
      final rows = response['merchants'];
      if (rows is! List || rows.any((row) => row is! Map)) {
        throw const FormatException('Invalid merchant response');
      }
      setState(
        () => _merchants = rows
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(),
      );
    } catch (error) {
      if (mounted &&
          widget.lease.valid &&
          !widget.lease.handleAccessFailure(error)) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.lease.valid) return const SizedBox.shrink();
    if (!widget.lease.session.canCreateShippingOrder) {
      return const Center(
        child: Text('Tài khoản chưa được phép tạo đơn giao hàng.'),
      );
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Chưa tải được dịch vụ giao hàng.'),
            TextButton.icon(
              onPressed: _load,
              icon: const GhstButtonIcon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    if (_merchants == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return CloudOrderForm(
      service: widget.lease.session.service,
      lease: widget.lease,
      merchants: _merchants!,
      embedded: true,
      onCreated: widget.onCreated,
      onOrderCreated: widget.onOrderCreated,
      initialDetails: widget.initialDetails,
    );
  }
}
