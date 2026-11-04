import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/gps/osrm_dispatch_service.dart';
import '../../core/utils/geo_math.dart';
import '../../domain/entities/geo_point.dart';
import 'ghst_button_icon.dart';

class RoadDispatchComparison extends StatefulWidget {
  const RoadDispatchComparison({
    super.key,
    required this.pickup,
    required this.candidates,
    this.service,
  });

  final GeoPoint pickup;
  final List<RoadDispatchCandidate> candidates;
  final OsrmDispatchService? service;

  @override
  State<RoadDispatchComparison> createState() => _RoadDispatchComparisonState();
}

class _RoadDispatchComparisonState extends State<RoadDispatchComparison> {
  List<RoadApproach>? _results;
  bool _loading = false;
  String? _error;
  int _generation = 0;

  String _signature(RoadDispatchComparison value) =>
      '${value.pickup.latitude},${value.pickup.longitude}|${value.candidates.map((c) => '${c.id}:${c.name}:${c.location.latitude},${c.location.longitude}').join('|')}';

  @override
  void didUpdateWidget(covariant RoadDispatchComparison oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signature(oldWidget) != _signature(widget) ||
        oldWidget.service != widget.service) {
      _generation++;
      _results = null;
      _loading = false;
      _error = null;
    }
  }

  Future<void> _compare() async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _results = null;
    });
    try {
      final candidates = [...widget.candidates]
        ..sort(
          (a, b) => GeoMath.distanceMeters(
            widget.pickup,
            a.location,
          ).compareTo(GeoMath.distanceMeters(widget.pickup, b.location)),
        );
      final results = await (widget.service ?? OsrmDispatchService.instance)
          .compare(
            pickup: widget.pickup,
            candidates: candidates.take(10).toList(),
          );
      if (!mounted || generation != _generation) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = 'Chưa tính được tuyến đường đến điểm lấy hàng.');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            const Text(
              'Đường đến điểm lấy hàng',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            IconButton(
              tooltip: 'So sánh thời gian đường bộ',
              onPressed: _loading || widget.candidates.isEmpty
                  ? null
                  : _compare,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const GhstButtonIcon(Icons.compare_arrows),
            ),
          ],
        ),
        if (widget.candidates.isEmpty)
          const Text(
            'Chưa có tài xế rảnh đủ điều kiện với GPS đã xác minh.',
            style: TextStyle(fontSize: 12),
          )
        else if (_error != null)
          Text(
            _error!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          )
        else if (_results != null)
          ..._results!.map(
            (result) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      result.candidate.name,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      result.reachable
                          ? '${(result.distanceMeters! / 1000).toStringAsFixed(1)} km · ${(result.durationSeconds! / 60).ceil()} phút'
                          : 'Không có đường đi',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_results != null) ...[
          const Text(
            'Ước tính đường ô tô, chưa gồm giao thông trực tiếp.',
            style: TextStyle(fontSize: 11),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.zero,
            ),
            onPressed: () =>
                launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
            icon: const GhstButtonIcon.glyph(GhstActionKind.route, size: 16),

            label: const Text(
              'OSRM · © OpenStreetMap contributors',
              style: TextStyle(fontSize: 10),
            ),
          ),
        ],
      ],
    ),
  );
}
