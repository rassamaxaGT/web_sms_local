import 'dart:async';
import 'package:http/http.dart' as http;

class NetworkScanner {
  static Future<String?> findHostIP() async {

    // ШАГ 1: Попробуем известные подсети
    final subnets = [3, 0, 1, 100];
    const int batchSize = 15; // Уменьшим размер пачки для стабильности

    for (var subnet in subnets) {
      for (var i = 1; i < 255; i += batchSize) {
        final List<Future<String?>> currentBatch = [];

        for (var j = 0; j < batchSize; j++) {
          final lastOctet = i + j;
          if (lastOctet >= 255) break;
          final ip = "192.168.$subnet.$lastOctet";
          currentBatch.add(_checkIP(ip));
        }

        final results = await Future.wait(currentBatch);
        for (var result in results) {
          if (result != null) return result;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    return null;
  }

  static Future<String?> _checkIP(String host) async {
    try {
      final url = Uri.parse("http://$host:8080/api/ping");
      // Увеличим таймаут до 2 секунд
      final response = await http.get(url).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        if (response.body.contains("Android Host")) {
          return "http://$host:8080";
        }
      }
    } catch (e) {
      // Можно раскомментировать для отладки:
      // print("Check $host failed: $e");
    }
    return null;
  }
}
