import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppDestination {
  catalog,
  order,
}

class AppNavigationController extends Notifier<AppDestination> {
  @override
  AppDestination build() {
    return AppDestination.catalog;
  }

  void select(AppDestination destination) {
    if (state == destination) {
      return;
    }

    state = destination;
  }

  void restoreForSession(AppDestination destination) {
    state = destination;
  }
}

final appNavigationControllerProvider =
    NotifierProvider<AppNavigationController, AppDestination>(
  AppNavigationController.new,
);
