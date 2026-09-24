import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef AsyncDataBuilder<T> = Widget Function(
  BuildContext context,
  T data,
);

typedef AsyncErrorBuilder = Widget Function(
  BuildContext context,
  Object error,
  StackTrace stackTrace,
);

class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    required this.value,
    required this.dataBuilder,
    this.loading,
    this.errorBuilder,
    super.key,
  });

  final AsyncValue<T> value;
  final AsyncDataBuilder<T> dataBuilder;
  final Widget? loading;
  final AsyncErrorBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (data) {
        return dataBuilder(context, data);
      },
      loading: () {
        return loading ??
            const Center(
              child: CircularProgressIndicator(),
            );
      },
      error: (error, stackTrace) {
        if (errorBuilder != null) {
          return errorBuilder!(context, error, stackTrace);
        }

        return const Center(
          child: Text('Something went wrong.'),
        );
      },
    );
  }
}
