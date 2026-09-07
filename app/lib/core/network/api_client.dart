import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// FluxForge 全局统一高性能 HTTP 网络客户端
/// 内置默认请求头、防爬伪装 User-Agent、超时配置与统一异常拦截
class ApiClient {
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

  late final Dio dio;

  ApiClient({BaseOptions? options}) {
    dio = Dio(
      options ??
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
            headers: {
              'User-Agent': defaultUserAgent,
              'Accept': 'application/json, text/plain, */*',
            },
          ),
    );

    // 仅在调试模式下打印网络请求摘要
    if (kDebugMode) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            debugPrint('[HTTP Request] [${options.method}] ${options.uri}');
            return handler.next(options);
          },
          onResponse: (response, handler) {
            debugPrint('[HTTP Response] [${response.statusCode}] ${response.requestOptions.uri}');
            return handler.next(response);
          },
          onError: (DioException e, handler) {
            debugPrint('[HTTP Error] [${e.response?.statusCode}] ${e.message} - ${e.requestOptions.uri}');
            return handler.next(e);
          },
        ),
      );
    }
  }

  /// 发起 GET 请求
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// 发起 POST 请求
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }
}
