import 'dart:convert';
import 'package:crypto/crypto.dart';

String sha256Hex(String s) {
  final bytes = utf8.encode(s);
  return sha256.convert(bytes).toString();
}
