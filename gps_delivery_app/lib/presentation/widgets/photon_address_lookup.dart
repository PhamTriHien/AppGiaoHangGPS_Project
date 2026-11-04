import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/env_config.dart';
import '../../core/integrations/photon_address_service.dart';
import '../../domain/entities/geo_point.dart';
import 'ghst_button_icon.dart';

class PhotonAddressLookup extends StatefulWidget {
  const PhotonAddressLookup({
    super.key,
    required this.controller,
    required this.onSelected,
    this.service,
    this.buttonLabel = 'Tìm địa chỉ · Photon',
    this.autoSearch = false,
    this.biasPoint,
  });
  final TextEditingController controller;
  final ValueChanged<PhotonPlace> onSelected;
  final PhotonAddressService? service;
  final String buttonLabel;
  final bool autoSearch;
  final GeoPoint? biasPoint;

  @override
  State<PhotonAddressLookup> createState() => _PhotonAddressLookupState();
}

class _PhotonAddressLookupState extends State<PhotonAddressLookup> {
  Timer? _debounce;
  int _generation = 0;
  bool _enabled = false;
  bool _busy = false;
  bool _suppressNextChange = false;
  String? _error;
  String _attribution = 'OpenStreetMap contributors / Photon';
  List<PhotonPlace> _places = [];

  bool get _canAutoSearch =>
      _enabled ||
      (widget.autoSearch &&
          (widget.service != null || EnvConfig.deliveryApiBaseUrl.isNotEmpty));

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant PhotonAddressLookup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _changed();
    }
  }

  void _changed() {
    if (_suppressNextChange) return;
    _debounce?.cancel();
    _generation++;
    setState(() {
      _places = [];
      _busy = false;
      _error = null;
    });
    if (!_canAutoSearch) return;
    if (widget.controller.text.trim().length < 3) return;
    _debounce = Timer(
      Duration(milliseconds: widget.autoSearch ? 750 : 1200),
      _search,
    );
  }

  Future<void> _search() async {
    _debounce?.cancel();
    final generation = ++_generation;
    final query = widget.controller.text.trim();
    if (query.length < 3) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = widget.service ?? PhotonAddressService();
      final places = await service.search(query, bias: widget.biasPoint);
      if (!mounted || generation != _generation) return;
      setState(() {
        _enabled = service.autocomplete;
        _attribution = service.attribution;
        _places = places;
        _error = places.isEmpty ? 'Không tìm thấy địa chỉ phù hợp.' : null;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _enabled = false;
        _error = e.toString();
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : _search,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const GhstButtonIcon(Icons.search, size: 17),
          label: Text(widget.buttonLabel),
        ),
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ..._places.map(
        (place) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const GhstButtonIcon(Icons.location_on_outlined, size: 18),
          title: Text(place.address, maxLines: 3),
          onTap: () {
            _enabled = false;
            _generation++;
            _debounce?.cancel();
            _suppressNextChange = true;
            try {
              widget.onSelected(place);
            } finally {
              _suppressNextChange = false;
            }
            if (!mounted) return;
            setState(() {
              _places = [];
              _error = null;
              _busy = false;
            });
          },
        ),
      ),
      if (_places.isNotEmpty)
        Text(
          _attribution == 'Google Maps'
              ? 'Google Maps'
              : '© OpenStreetMap contributors · Photon',
          style: const TextStyle(fontSize: 10),
        ),
    ],
  );
}
