import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/integrations/delivery_weather_service.dart';
import '../../domain/entities/geo_point.dart';

class DeliveryWeatherStrip extends StatefulWidget {
  const DeliveryWeatherStrip({super.key, required this.point, this.service});

  final GeoPoint? point;
  final DeliveryWeatherService? service;

  @override
  State<DeliveryWeatherStrip> createState() => _DeliveryWeatherStripState();
}

class _DeliveryWeatherStripState extends State<DeliveryWeatherStrip> {
  Future<DeliveryWeather>? _request;
  DeliveryWeatherService get _service =>
      widget.service ?? DeliveryWeatherService.instance;

  String _grid(GeoPoint? point) => point == null
      ? ''
      : '${point.latitude.toStringAsFixed(2)},${point.longitude.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    if (widget.point != null) _request = _service.load(widget.point!);
  }

  @override
  void didUpdateWidget(covariant DeliveryWeatherStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_grid(oldWidget.point) != _grid(widget.point) ||
        oldWidget.service != widget.service) {
      _request = widget.point == null ? null : _service.load(widget.point!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.point == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FutureBuilder<DeliveryWeather>(
        future: _request,
        builder: (context, snapshot) {
          final done = snapshot.connectionState == ConnectionState.done;
          final weather = done && !snapshot.hasError ? snapshot.data : null;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(
                  weather?.needsCaution == true
                      ? Icons.thunderstorm_outlined
                      : Icons.cloud_outlined,
                  color: weather?.needsCaution == true
                      ? Colors.deepOrange
                      : Colors.teal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!done)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Đang tải dự báo thời tiết...',
                          style: TextStyle(fontSize: 12),
                        ),
                      )
                    else if (weather == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Chưa có dự báo thời tiết.',
                          style: TextStyle(fontSize: 12),
                        ),
                      )
                    else ...[
                      Text(
                        'Dự báo ${DateFormat('HH:mm').format(weather.forecastAt.toLocal())} · ${weather.temperatureCelsius.toStringAsFixed(1)} °C',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${weather.rainNextHourMm == null ? 'Chưa có lượng mưa giờ tới' : 'Mưa giờ tới ${weather.rainNextHourMm!.toStringAsFixed(1)} mm'} · Gió ${(weather.windSpeedMetersPerSecond * 3.6).toStringAsFixed(0)} km/h',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (weather.needsCaution)
                        const Text(
                          'Mưa hoặc gió mạnh dự kiến, cần thận trọng khi giao hàng.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.deepOrange,
                          ),
                        ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => launchUrl(
                          Uri.parse('https://api.met.no/doc/License'),
                        ),
                        child: const Text(
                          'MET Norway · CC BY 4.0',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cập nhật dự báo',
                onPressed: done
                    ? () => setState(
                        () => _request = _service.load(widget.point!),
                      )
                    : null,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          );
        },
      ),
    );
  }
}
