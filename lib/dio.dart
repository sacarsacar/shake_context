/// Dio integration for shake_context.
///
/// Import this file only if your app uses `package:dio/dio.dart` and you
/// want HTTP cycles to appear in the developer overlay's Network panel.
/// Apps that don't import this file have dio tree-shaken from release
/// builds.
library;

export 'src/integrations/shake_dio_interceptor.dart';
