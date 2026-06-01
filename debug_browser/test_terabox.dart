import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = 'https://terabox.hnn.workers.dev/api/get-info?shorturl=1qW8xxxx';
  try {
    final response = await http.get(Uri.parse(url));
    print('Status: \${response.statusCode}');
    print('Body: \${response.body}');
  } catch (e) {
    print('Error: \$e');
  }
}
