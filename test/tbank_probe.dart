// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// Utility scratch probe for testing T-Bank contractor service endpoints
void main() async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 5);
  client.userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

  const inn = '7707083893';
  const url =
      'https://www.tbank.ru/business/contractor/company-pages/papi/dadata/suggestions/api/4_1/rs/suggest/party?appName=company-pages';

  try {
    stdout.writeln('Querying T-Bank suggest for INN: $inn');
    final req = await client.postUrl(Uri.parse(url)).timeout(const Duration(seconds: 5));
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Accept', 'application/json');
    req.headers.set('Referer', 'https://www.tbank.ru/business/contractor/');

    req.add(utf8.encode(jsonEncode({'count': 5, 'query': inn})));
    final resp = await req.close().timeout(const Duration(seconds: 5));

    final respBody = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
    final json = jsonDecode(respBody) as Map<String, dynamic>;
    final suggestions = (json['payload'] as Map<String, dynamic>?)?['suggestions'] as List?;

    stdout.writeln('Status: ${resp.statusCode}, Results: ${suggestions?.length ?? 0}');
    if (suggestions != null) {
      for (final s in suggestions) {
        final data = s['data'] as Map<String, dynamic>?;
        stdout.writeln(' - ${s['value']} (ИНН: ${data?['inn']}, ОГРН: ${data?['ogrn']})');
      }
    }
  } catch (e) {
    stderr.writeln('Error: $e');
  } finally {
    client.close();
  }
}
