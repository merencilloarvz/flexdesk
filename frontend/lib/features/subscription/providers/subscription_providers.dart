import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/dio_client.dart';
import '../data/subscription_api.dart';

final subscriptionApiProvider = Provider<SubscriptionApi>(
  (ref) => SubscriptionApi(ref.watch(dioProvider)),
);
