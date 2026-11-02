class StopOrderPlan {
  const StopOrderPlan({
    required this.order,
    required this.currentMeters,
    required this.optimizedMeters,
  });

  /// Indices of the intermediate stops in visiting order.
  final List<int> order;
  final double currentMeters;
  final double optimizedMeters;

  bool get improves => optimizedMeters < currentMeters;
}

/// Orders the intermediate stops of a road distance matrix whose first row is
/// the pickup and last row the dropoff. The cloud quote accepts at most five
/// stops, so an exhaustive search (120 permutations) returns the exact optimum
/// on asymmetric road distances.
StopOrderPlan bestStopOrder(List<List<double>> distances) {
  final n = distances.length;
  if (n < 2 || distances.any((row) => row.length != n)) {
    throw ArgumentError('A square matrix with pickup and dropoff is required.');
  }
  final stops = [for (var i = 1; i < n - 1; i++) i];
  if (stops.length > 5) {
    throw ArgumentError('At most five intermediate stops are supported.');
  }
  double cost(List<int> sequence) {
    var total = 0.0;
    var previous = 0;
    for (final stop in [...sequence, n - 1]) {
      total += distances[previous][stop];
      previous = stop;
    }
    return total;
  }

  final current = cost(stops);
  var best = List<int>.of(stops);
  var bestCost = current;
  void permute(List<int> prefix, List<int> remaining) {
    if (remaining.isEmpty) {
      final candidate = cost(prefix);
      if (candidate < bestCost) {
        bestCost = candidate;
        best = List<int>.of(prefix);
      }
      return;
    }
    for (var i = 0; i < remaining.length; i++) {
      permute(
        [...prefix, remaining[i]],
        [...remaining.sublist(0, i), ...remaining.sublist(i + 1)],
      );
    }
  }

  permute(const [], stops);
  return StopOrderPlan(
    order: [for (final stop in best) stop - 1],
    currentMeters: current,
    optimizedMeters: bestCost,
  );
}
