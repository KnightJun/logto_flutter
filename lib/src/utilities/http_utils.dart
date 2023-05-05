import 'dart:convert';

import '/src/exceptions/http_request_exceptions.dart';
import 'package:dio/dio.dart' as dio;

dynamic httpResponseHandler(dio.Response response) {
  var contentType = response.headers.map.entries
      .firstWhere((v) => v.key.toLowerCase() == 'content-type',
          orElse: () => const MapEntry('', ['']))
      .value;

  var isJson = contentType[0].split(';').first == 'application/json';

  var body = response.data;

  if (response.statusCode! < 200 || response.statusCode! >= 300) {
    throw HttpRequestException(statusCode: response.statusCode!, body: body);
  }

  return body;
}
