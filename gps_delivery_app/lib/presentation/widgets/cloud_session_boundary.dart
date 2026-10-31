import 'package:flutter/material.dart';

import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';

class CloudSessionBoundary extends StatefulWidget {
  const CloudSessionBoundary({
    super.key,
    required this.session,
    required this.builder,
    this.profile = false,
    this.operator = false,
    this.dialog = false,
    this.roles = const {},
  });

  final CloudAccountSession session;
  final Widget Function(BuildContext, CloudSessionLease) builder;
  final bool profile, operator, dialog;
  final Set<String> roles;

  @override
  State<CloudSessionBoundary> createState() => _CloudSessionBoundaryState();
}

class _CloudSessionBoundaryState extends State<CloudSessionBoundary> {
  late final _lease = CloudSessionLease(
    session: widget.session,
    profile: widget.profile,
    operator: widget.operator,
    roles: widget.roles,
  );

  @override
  void initState() {
    super.initState();
    _lease.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    // Remove confirmations/address pickers above this view as well. They may
    // contain private fields even after the protected page itself is hidden.
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_lease.valid && route?.isActive == true) {
        route!.navigator?.popUntil((candidate) => identical(candidate, route));
      }
    });
  }

  @override
  void dispose() {
    _lease.removeListener(_changed);
    _lease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lease.valid) return widget.builder(context, _lease);
    const message = 'Phiên làm việc đã thay đổi. Vui lòng mở lại mục này.';
    if (widget.dialog) {
      return AlertDialog(
        content: const Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Đóng'),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: const SafeArea(
        child: Padding(padding: EdgeInsets.all(24), child: Text(message)),
      ),
    );
  }
}
