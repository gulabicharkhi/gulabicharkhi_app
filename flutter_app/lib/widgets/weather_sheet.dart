import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../services/weather_service.dart';

/// Sheet that opens when the Home > Weather chip is pressed.
/// Current weather + the kite-flying verdict + the next 3 days.
Future<void> showWeatherSheet(BuildContext context, {required String city}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => WeatherSheet(city: city),
  );
}

class WeatherSheet extends StatefulWidget {
  final String city;
  const WeatherSheet({super.key, required this.city});

  @override
  State<WeatherSheet> createState() => _WeatherSheetState();
}

class _WeatherSheetState extends State<WeatherSheet> {
  WeatherInfo? _w;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.city.trim().isEmpty) {
      _error = 'Add your city in your Profile, then the weather of that city will show here.';
    } else {
      _load();
    }
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final w = await WeatherService.forCity(widget.city, force: force);
      if (!mounted) return;
      setState(() {
        _w = w;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.88;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (_w != null) ..._content(_w!)
              else if (_loading) _loadingView()
              else _errorView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadingView() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: AppColors.primaryPink)),
      );

  Widget _errorView() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded, size: 52, color: AppColors.primaryPink.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Could not load the weather.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textGrey, fontSize: 14),
            ),
            if (widget.city.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _load(force: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryPink,
                  side: const BorderSide(color: AppColors.primaryPink),
                ),
              ),
            ],
          ],
        ),
      );

  List<Widget> _content(WeatherInfo w) {
    return [
      // ---- Top: temp + condition ----
      Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFE93D95), Color(0xFFA64CF5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(w.icon, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${w.temp.round()}°C',
                  style: const TextStyle(
                    fontSize: 32,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  w.condition,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 13, color: AppColors.textGrey),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        w.place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textGrey),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loading ? null : () => _load(force: true),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryPink),
                  )
                : const Icon(Icons.refresh_rounded, color: AppColors.primaryPink),
          ),
        ],
      ),
      const SizedBox(height: 18),

      // ---- Kite verdict ----
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: w.kiteColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: w.kiteColor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.air_rounded, color: w.kiteColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    w.kiteTitle,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: w.kiteColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              w.kiteTip,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textDark, height: 1.35),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: w.kiteScore,
                minHeight: 7,
                backgroundColor: Colors.white,
                valueColor: AlwaysStoppedAnimation(w.kiteColor),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // ---- Stats ----
      Row(
        children: [
          _stat(Icons.air_rounded, '${w.windSpeed.round()} km/h', 'Wind ${w.windCompass}'),
          const SizedBox(width: 10),
          _stat(Icons.speed_rounded, '${w.windGust.round()} km/h', 'Gusts'),
          const SizedBox(width: 10),
          _stat(Icons.water_drop_outlined, '${w.humidity}%', 'Humidity'),
          const SizedBox(width: 10),
          _stat(Icons.thermostat_rounded, '${w.feelsLike.round()}°', 'Feels like'),
        ],
      ),

      // ---- Forecast ----
      if (w.daily.length > 1) ...[
        const SizedBox(height: 18),
        const Text(
          'Next days',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark),
        ),
        const SizedBox(height: 8),
        for (final d in w.daily.skip(1)) _dayRow(d),
      ],
      const SizedBox(height: 6),
      const Text(
        'Data: Open-Meteo',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10.5, color: AppColors.textGrey),
      ),
    ];
  }

  Widget _stat(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F3F8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppColors.primaryPink),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textGrey)),
          ],
        ),
      ),
    );
  }

  Widget _dayRow(DayForecast d) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              names[d.date.weekday - 1],
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark),
            ),
          ),
          Icon(WeatherService.conditionIcon(d.code, true), size: 20, color: AppColors.primaryPink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              WeatherService.conditionText(d.code),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textGrey),
            ),
          ),
          Text(
            '${d.maxWind.round()} km/h',
            style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Text(
              '${d.maxTemp.round()}° / ${d.minTemp.round()}°',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}
