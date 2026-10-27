import 'dart:async';

import 'package:flutter/material.dart';

class PaymentSuccessPage extends StatefulWidget {
  const PaymentSuccessPage({
    super.key,
    required this.orderId,
    required this.amount,
    required this.scheduleApplied,
    required this.scheduleDescription,
    this.redirectDelay = const Duration(seconds: 10),
    this.memberName,
  });

  final String orderId;
  final String amount;
  final bool scheduleApplied;
  final String scheduleDescription;
  final Duration redirectDelay;
  final String? memberName;

  @override
  State<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends State<PaymentSuccessPage>
    with SingleTickerProviderStateMixin {
  Timer? _redirectTimer;
  late final AnimationController _redirectProgress;

  @override
  void initState() {
    super.initState();
    _redirectProgress = AnimationController(
      vsync: this,
      duration: widget.redirectDelay,
    )..forward();
    _redirectTimer = Timer(widget.redirectDelay, _returnToDashboard);
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    _redirectProgress.dispose();
    super.dispose();
  }

  void _returnToDashboard() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final headerForeground = colors.onPrimaryContainer;

    return Dialog(
      key: const Key('payment-success-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: colors.surface,
      elevation: 20,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 720),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                key: const Key('payment-success-header'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [colors.primaryContainer, colors.tertiaryContainer],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
                  child: Column(
                    children: [
                      TweenAnimationBuilder<double>(
                        key: const Key('payment-success-icon-animation'),
                        tween: Tween(begin: 0.55, end: 1),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (context, scale, child) => Transform.scale(
                          key: const Key('payment-success-icon-transform'),
                          scale: scale,
                          child: Opacity(
                            opacity: scale.clamp(0, 1),
                            child: child,
                          ),
                        ),
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: headerForeground.withValues(alpha: .12),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: headerForeground.withValues(alpha: .42),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            key: const Key('payment-success-check-icon'),
                            color: headerForeground,
                            size: 38,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Payment successful',
                        key: const Key('payment-success-title'),
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: headerForeground,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your payment has been confirmed securely.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: headerForeground.withValues(alpha: .88),
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        child: Column(
                          children: [
                            Text(
                              'AMOUNT PAID',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    letterSpacing: 1.1,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.amount,
                              key: const Key('payment-success-amount'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    color: colors.onSurface,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (widget.memberName?.trim().isNotEmpty == true) ...[
                      _SuccessDetail(
                        label: 'Paid for',
                        value: widget.memberName!.trim(),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _SuccessDetail(
                      label: 'Order ID',
                      value: widget.orderId,
                    ),
                    const SizedBox(height: 10),
                    if (widget.scheduleApplied)
                      _SuccessDetail(
                        label: 'Schedule updated',
                        value: widget.scheduleDescription,
                      )
                    else
                      _ScheduleWarning(message: widget.scheduleDescription),
                    const SizedBox(height: 18),
                    AnimatedBuilder(
                      animation: _redirectProgress,
                      builder: (context, child) {
                        final remainingSeconds =
                            (widget.redirectDelay.inMilliseconds *
                                    (1 - _redirectProgress.value) /
                                    1000)
                                .ceil();
                        return Column(
                          children: [
                            LinearProgressIndicator(
                              key: const Key('payment-success-progress'),
                              value: _redirectProgress.value,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Returning to dashboard in '
                              '$remainingSeconds '
                              '${remainingSeconds == 1 ? 'second' : 'seconds'}…',
                              key: const Key('payment-success-countdown'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleWarning extends StatelessWidget {
  const _ScheduleWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = message.trim().isEmpty
        ? 'Payment confirmed, but the schedule update could not be confirmed. Contact an administrator.'
        : message;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                key: const Key('payment-schedule-warning'),
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessDetail extends StatelessWidget {
  const _SuccessDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
