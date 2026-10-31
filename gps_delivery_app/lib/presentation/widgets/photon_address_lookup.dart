import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/integrations/photon_address_service.dart';

class PhotonAddressLookup extends StatefulWidget {
  const PhotonAddressLookup({
    super.key,
    required this.controller,
    required this.onSelected,
    this.service,
  });
  final TextEditingController controller;
  final ValueChanged<PhotonPlace> onSelected;
  final PhotonAddressService? service;
  @override
  State<PhotonAddressLookup> createState() => _PhotonAddressLookupState();
}

class _PhotonAddressLookupState extends State<PhotonAddressLookup> {
  Timer? _debounce;
  int _generation = 0;
  bool _enabled = false;
  bool _busy = false;
  String? _error;
  List<PhotonPlace> _places = [];
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
    _debounce?.cancel();
    _generation++;
    setState(() {
      _places = [];
      _busy = false;
      _error = null;
    });
    if (!_enabled) return;
    if (widget.controller.text.trim().length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 1200), _search);
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
      final places = await service.search(query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _enabled = service.autocomplete;
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
              : const Icon(Icons.search, size: 17),
          label: const Text('Tìm địa chỉ · Photon'),
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
          leading: const Icon(Icons.location_on_outlined, size: 18),
          title: Text(place.address, maxLines: 3),
          onTap: () {
            _enabled = false;
            _generation++;
            _debounce?.cancel();
            widget.onSelected(place);
            setState(() {
              _places = [];
              _error = null;
              _busy = false;
            });
          },
        ),
      ),
      if (_places.isNotEmpty)
        const Text(
          '© OpenStreetMap contributors · Photon',
          style: TextStyle(fontSize: 10),
        ),
    ],
  );
}
