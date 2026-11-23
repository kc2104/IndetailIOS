import 'package:material_ui/material_ui.dart';

import '../theme.dart';

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      if (actionLabel != null)
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 5),
          ),
          child: Text(actionLabel!),
        ),
    ],
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 17, color: accent),
            ),
            const Spacer(),
            const Icon(
              Icons.more_horiz_rounded,
              size: 18,
              color: Palette.muted,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Palette.ink,
            fontSize: 24,
            height: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Palette.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class ShortcutCard extends StatelessWidget {
  const ShortcutCard({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    required this.color,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(14),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Palette.ink,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: const TextStyle(color: Palette.muted, fontSize: 10),
            ),
          ],
        ),
      ],
    ),
  );
}

class PreviewBanner extends StatelessWidget {
  const PreviewBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
    color: const Color(0xFFEAE4D9),
    child: const Row(
      children: [
        Icon(Icons.visibility_outlined, color: Palette.navy, size: 15),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Preview mode · sample content only · no live attendance',
            style: TextStyle(
              color: Palette.navy,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class EmptyInline extends StatelessWidget {
  const EmptyInline({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Palette.sand,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Palette.navy),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Palette.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(
                  color: Palette.muted,
                  height: 1.35,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null)
          IconButton(
            onPressed: onAction,
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: Palette.blue,
            ),
          ),
      ],
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, color: Palette.muted, size: 36),
          const SizedBox(height: 12),
          const Text(
            'Could not load this view',
            style: TextStyle(color: Palette.ink, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Palette.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.value});
  final String value;
  @override
  Widget build(BuildContext context) {
    final normalized = value.toLowerCase().replaceAll('_', ' ');
    final color = switch (normalized) {
      'approved' || 'done' || 'completed' => Palette.green,
      'revision required' || 'rejected' || 'overdue' => Palette.red,
      'under review' || 'in progress' || 'submitted' => Palette.blue,
      _ => Palette.amber,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        normalized.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 9,
          letterSpacing: .5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.value,
    this.color = Palette.blue,
  });
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) => LinearProgressIndicator(
        value: progress,
        minHeight: 6,
        color: color,
        backgroundColor: Palette.sand,
      ),
    ),
  );
}

String formattedDate(DateTime? date, {bool withYear = false}) {
  if (date == null) return 'No deadline';
  final months = const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]}${withYear ? ' ${date.year}' : ''}';
}

String formattedTime(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
}
