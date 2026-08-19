import '../pack_config.dart';
import '../pack_planner.dart';
import 'asset_packs.dart';

/// Total size Play allows across all install-time asset packs.
const int installTimeTotalLimit = 1024 * 1024 * 1024;

/// Download size Play allows for one fast-follow or on-demand asset pack.
const int perPackDownloadLimit = 512 * 1024 * 1024;

/// A pack, or a group of them, over what Play accepts.
final class LimitWarning {
  const LimitWarning({
    required this.title,
    required this.detail,
    required this.fix,
  });

  final String title;
  final String detail;
  final String fix;
}

/// Checks packs against Play's published size limits.
///
/// Only Play's limits: Apple documents its own, but they have not been checked
/// here, and warning about numbers that were never verified would be worse than
/// staying quiet.
///
/// These are warnings rather than errors. A project that never ships to Android
/// is entitled to ignore them, and the store rejection they predict happens long
/// after the build.
List<LimitWarning> checkPlayLimits(List<PackPlan> plans) {
  final warnings = <LimitWarning>[];

  for (final plan in plans) {
    if (plan.config.delivery == DeliveryPolicy.essential) continue;
    final size = plan.sizeInBytes;
    if (size > perPackDownloadLimit) {
      warnings.add(
        LimitWarning(
          title: 'pack "${plan.config.id}" size',
          detail:
              '${_format(size)} exceeds the ${_format(perPackDownloadLimit)} '
              'Play allows for a ${deliveryTypeOf(plan.config.delivery)} pack',
          fix: 'Split it into several packs, or deliver it install-time.',
        ),
      );
    }
  }

  final installTime = plans
      .where((plan) => plan.config.delivery == DeliveryPolicy.essential)
      .fold(0, (total, plan) => total + plan.sizeInBytes);
  if (installTime > installTimeTotalLimit) {
    warnings.add(
      LimitWarning(
        title: 'install-time total',
        detail:
            '${_format(installTime)} across all install-time packs exceeds the '
            '${_format(installTimeTotalLimit)} Play allows',
        fix: 'Move some of it to prefetch or onDemand delivery.',
      ),
    );
  }

  return warnings;
}

String _format(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}
