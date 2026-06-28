extension ScopeFunctions<T> on T {
  /// Applies the given [function] to this object and returns its result.
  R let<R>(R Function(T) function) {
    return function(this);
  }

  /// Applies the given [function] to this object and returns this object.
  T also(void Function(T) function) {
    function(this);
    return this;
  }

  /// Returns this object if it satisfies the given [predicate] or `null` otherwise.
  T? takeIf(bool Function(T) predicate) {
    return predicate(this) ? this : null;
  }
}
