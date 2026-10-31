import 'package:flutter/foundation.dart';

import '../network/public_json_api.dart';
import 'cloud_account_session.dart';

/// A private view cannot be revived by a later verification or same-user login.
class CloudSessionLease extends ChangeNotifier {
  CloudSessionLease({
    required this.session,
    this.profile = false,
    this.operator = false,
    this.roles = const {},
  }) : _scope = session.service.identityScope,
       _revision = session.revision {
    _revoked = !_allowed;
    session.addListener(_onSessionChanged);
  }

  final CloudAccountSession session;
  final bool profile, operator;
  final Set<String> roles;
  final String _scope;
  final int _revision;
  bool _revoked = false, _disposed = false;

  bool get _allowed {
    if (_disposed ||
        !session.verified ||
        _scope != session.service.identityScope) {
      return false;
    }
    // Saving one's profile may create the initial business account or change
    // a role request. It never grants permission to keep an old business view.
    if (profile) return session.account?['blocked'] != true;
    if (_revision != session.revision) return false;
    if (operator) return session.isOperator;
    return session.canUseBusiness &&
        (roles.isEmpty ||
            roles.any(
              (r) =>
                  r == 'merchant' ? session.hasMerchantAccess : session.hasRole(r),
            ));
  }

  bool get valid => !_revoked && _allowed;

  bool handleAccessFailure(Object error) {
    if (!valid ||
        error is! PublicApiException ||
        ![401, 403].contains(error.statusCode)) {
      return false;
    }
    session.invalidateVerification(error: error);
    return true;
  }

  void _onSessionChanged() {
    if (_revoked || _allowed) return;
    _revoked = true;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    session.removeListener(_onSessionChanged);
    super.dispose();
  }
}
