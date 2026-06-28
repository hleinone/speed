import 'package:flutter/rendering.dart';
import 'package:rxdart/rxdart.dart';

extension StreamExtensions<T> on Stream<T> {
  Stream<(T, T)> pairwiseRecord() => pairwise().map((l) => (l[0], l[1]));

  Stream<T> debug(
    String key, {
    String Function(T data)? dataMapper,
    String Function(ErrorAndStackTrace errorAndStackTrace)? errorAndStacktTraceMapper,
  }) {
    return doOnEach((n) {
      switch (n.kind) {
        case NotificationKind.data:
          debugPrint('[$key] data: ${dataMapper?.call(n.requireDataValue) ?? n.requireDataValue}');
          break;
        case NotificationKind.done:
          debugPrint('[$key] done');
          break;
        case NotificationKind.error:
          debugPrint(
            '[$key] error: ${errorAndStacktTraceMapper?.call(n.requireErrorAndStackTrace) ?? n.requireErrorAndStackTrace}',
          );
          break;
      }
    });
  }
}
