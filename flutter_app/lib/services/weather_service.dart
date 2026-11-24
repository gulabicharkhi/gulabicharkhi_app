import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Patang udaane ke liye mausam kaisa hai
enum KiteLevel { great, okay, poor, danger }

class DayForecast {
  final DateTime date;
  final double maxTemp;
  final double minTemp;
  final int rainChance; // %
  final double maxWind; // km/h
  final int code;
  const DayForecast({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.rainChance,
    required this.maxWind,
    required this.code,
  });
}

class WeatherInfo {
  final String place; // e.g. "Jaipur, Rajasthan"
  final double temp;
  final double feelsLike;
  final int humidity;
  final double windSpeed; // km/h
  final double windGust; // km/h
  final int windDir; // degrees
  final double precipitation; // mm
  final int code;
  final bool isDay;
  final List<DayForecast> daily; // aaj se shuru
  final DateTime fetchedAt;

  const WeatherInfo({
    required this.place,
    required this.temp,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.windGust,
    required this.windDir,
    required this.precipitation,
    required this.code,
    required this.isDay,
    required this.daily,
    required this.fetchedAt,
  });

  String get condition => WeatherService.conditionText(code);
  IconData get icon => WeatherService.conditionIcon(code, isDay);
  String get windCompass => WeatherService.compass(windDir);

  // ---------------- Kite flying verdict ----------------
  bool get _stormy => code >= 95;
  bool get _rainy =>
      (code >= 51 && code <= 67) || (code >= 80 && code <= 86) || precipitation > 0.2;

  KiteLevel get kiteLevel {
    if (_stormy || windSpeed >= 40 || windGust >= 55) return KiteLevel.danger;
    if (_rainy || windSpeed < 5 || windSpeed >= 30) return KiteLevel.poor;
    if (windSpeed < 10 || windSpeed >= 25) return KiteLevel.okay;
    return KiteLevel.great;
  }

  String get kiteTitle {
    switch (kiteLevel) {
      case KiteLevel.great:
        return 'Perfect for kite flying';
      case KiteLevel.okay:
        return 'Chalega, thoda mushkil';
      case KiteLevel.poor:
        return 'Kite ke liye theek nahi';
      case KiteLevel.danger:
        return 'Aaj patang mat udao';
    }
  }

  String get kiteTip {
    if (_stormy) return 'Bijli / toofan ka khatra hai. Khule me patang udana safe nahi.';
    if (windSpeed >= 40 || windGust >= 55) return 'Hawa bahut tez hai, manjha aur patang dono control se bahar ho sakte hain.';
    if (_rainy) return 'Baarish me patang aur manjha gila ho jata hai. Match baad me rakho.';
    if (windSpeed < 5) return 'Hawa bahut halki hai, patang uthegi hi nahi.';
    if (windSpeed >= 30) return 'Hawa tez hai. Sirf experienced players, moti dor ke saath.';
    if (windSpeed < 10) return 'Hawa halki hai. Halki patang aur patli dor use karo.';
    if (windSpeed >= 25) return 'Hawa kaafi tez hai. Pecha lagate time dor sambhal ke.';
    return 'Hawa ekdum sahi hai. Pecha lagane ke liye best time!';
  }

  /// 0-100 bar ke liye
  double get kiteScore {
    switch (kiteLevel) {
      case KiteLevel.great:
        return 0.92;
      case KiteLevel.okay:
        return 0.6;
      case KiteLevel.poor:
        return 0.3;
      case KiteLevel.danger:
        return 0.1;
    }
  }

  Color get kiteColor {
    switch (kiteLevel) {
      case KiteLevel.great:
        return const Color(0xFF10B981);
      case KiteLevel.okay:
        return const Color(0xFFF59E0B);
      case KiteLevel.poor:
        return const Color(0xFFF97316);
      case KiteLevel.danger:
        return const Color(0xFFEF4444);
    }
  }
}

class WeatherException implements Exception {
  final String message;
  WeatherException(this.message);
  @override
  String toString() => message;
}

/// Open-Meteo (free, API key nahi chahiye): geocoding + current weather.
/// Same city ka result 10 minute cache hota hai.
class WeatherService {
  static const _timeout = Duration(seconds: 12);
  static const _cacheFor = Duration(minutes: 10);
  static final Map<String, WeatherInfo> _cache = {};

  static Future<WeatherInfo> forCity(String rawCity, {bool force = false}) async {
    // "Jaipur, Rajasthan" jaisa likha ho to pehla hissa hi city hai
    final city = rawCity.split(',').first.trim();
    if (city.isEmpty) throw WeatherException('City set nahi hai.');

    final key = city.toLowerCase();
    final cached = _cache[key];
    if (!force && cached != null && DateTime.now().difference(cached.fetchedAt) < _cacheFor) {
      return cached;
    }

    try {
      // 1) city -> lat/lng
      final geoUri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': city,
        'count': '1',
        'language': 'en',
        'format': 'json',
      });
      final geoRes = await http.get(geoUri).timeout(_timeout);
      if (geoRes.statusCode != 200) throw WeatherException('Location nahi mili. Baad me try karo.');
      final geo = jsonDecode(geoRes.body);
      final results = geo is Map ? geo['results'] : null;
      if (results is! List || results.isEmpty) {
        throw WeatherException('"$city" ka mausam nahi mila. City ka naam check karo.');
      }
      final g = results.first as Map;
      final lat = (g['latitude'] as num).toDouble();
      final lng = (g['longitude'] as num).toDouble();
      final admin = (g['admin1'] ?? '').toString();
      final place = admin.isNotEmpty && admin != g['name'] ? '${g['name']}, $admin' : '${g['name']}';

      // 2) weather
      final wUri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '$lat',
        'longitude': '$lng',
        'current':
            'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m',
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max',
        'wind_speed_unit': 'kmh',
        'timezone': 'auto',
        'forecast_days': '4',
      });
      final wRes = await http.get(wUri).timeout(_timeout);
      if (wRes.statusCode != 200) throw WeatherException('Mausam ka data nahi aa paya.');
      final w = jsonDecode(wRes.body) as Map;
      final c = w['current'] as Map;
      final d = w['daily'] as Map;

      double n(dynamic v) => (v is num) ? v.toDouble() : 0;
      List dl(String k) => (d[k] as List?) ?? const [];

      final times = dl('time');
      final daily = <DayForecast>[
        for (var i = 0; i < times.length; i++)
          DayForecast(
            date: DateTime.parse(times[i].toString()),
            maxTemp: n(dl('temperature_2m_max')[i]),
            minTemp: n(dl('temperature_2m_min')[i]),
            rainChance: n(dl('precipitation_probability_max')[i]).round(),
            maxWind: n(dl('wind_speed_10m_max')[i]),
            code: n(dl('weather_code')[i]).round(),
          ),
      ];

      final info = WeatherInfo(
        place: place,
        temp: n(c['temperature_2m']),
        feelsLike: n(c['apparent_temperature']),
        humidity: n(c['relative_humidity_2m']).round(),
        windSpeed: n(c['wind_speed_10m']),
        windGust: n(c['wind_gusts_10m']),
        windDir: n(c['wind_direction_10m']).round(),
        precipitation: n(c['precipitation']),
        code: n(c['weather_code']).round(),
        isDay: n(c['is_day']) == 1,
        daily: daily,
        fetchedAt: DateTime.now(),
      );
      _cache[key] = info;
      return info;
    } on WeatherException {
      rethrow;
    } on TimeoutException {
      throw WeatherException('Internet slow hai. Thodi der baad try karo.');
    } catch (_) {
      throw WeatherException('Mausam load nahi ho paya. Internet check karo.');
    }
  }

  // ---------------- WMO weather code helpers ----------------
  static String conditionText(int code) {
    if (code == 0) return 'Clear sky';
    if (code == 1) return 'Mainly clear';
    if (code == 2) return 'Partly cloudy';
    if (code == 3) return 'Overcast';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 57) return 'Drizzle';
    if (code >= 61 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Rain showers';
    if (code == 85 || code == 86) return 'Snow showers';
    if (code == 95) return 'Thunderstorm';
    if (code >= 96) return 'Thunderstorm, hail';
    return 'Unknown';
  }

  static IconData conditionIcon(int code, bool isDay) {
    if (code == 0 || code == 1) return isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round;
    if (code == 2) return isDay ? Icons.wb_cloudy_outlined : Icons.cloud_outlined;
    if (code == 3) return Icons.cloud_rounded;
    if (code == 45 || code == 48) return Icons.blur_on_rounded;
    if (code >= 51 && code <= 67) return Icons.water_drop_rounded;
    if (code >= 71 && code <= 77) return Icons.ac_unit_rounded;
    if (code >= 80 && code <= 86) return Icons.grain_rounded;
    if (code >= 95) return Icons.thunderstorm_rounded;
    return Icons.cloud_outlined;
  }

  static String compass(int deg) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[((deg % 360) / 45).round() % 8];
  }
}
