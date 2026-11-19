import 'package:flutter/material.dart';

import '../../../app/theme/lunar_theme.dart';
import '../../../core/widgets/lunar_widgets.dart';
import '../../../core/widgets/pressable_action.dart';
import '../domain/home_summary.dart';

class TodayOverview extends StatelessWidget {
  const TodayOverview({super.key, required this.summary, this.onStart});
  final HomeSummary summary;
  final Future<void> Function()? onStart;
  @override
  Widget build(BuildContext context) {
    final a = summary.availability;
    final p = LunarPalette.of(context);
    final next = a.nextDueAtUtc?.add(Duration(minutes: a.offsetMinutes));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LunarHero(
          label: '现在可学',
          value: '${a.availableCards}',
          subtitle: a.blockedCards > 0 && a.availableCards == 0
              ? '有 ${a.blockedCards} 张到期卡受今日额度限制，可在学习设置中调整'
              : '记忆学习 · 按到期与剩余额度安排',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '今日已学 ${summary.studiedCards} 张',
                style: TextStyle(color: p.moon, fontSize: 13),
              ),
              const SizedBox(height: 13),
              Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: Theme.of(context).colorScheme.copyWith(
                    primary: p.moon,
                    onPrimary: p.night,
                    primaryContainer: p.moon,
                    onPrimaryContainer: p.night,
                  ),
                ),
                child: PressableAction(
                  label: a.availableCards > 0 ? '开始今日学习' : '暂时没有可学卡片',
                  onPressed: a.availableCards > 0 ? onStart : null,
                ),
              ),
              if (next != null && a.availableCards == 0) ...[
                const SizedBox(height: 10),
                Text(
                  '下次到期：${next.month}月${next.day}日 ${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}（学习日时区）',
                  style: TextStyle(
                    color: p.moon.withValues(alpha: .88),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        LunarStats([
          ('待复习', '${a.reviews} 张'),
          ('学习中', '${a.learning} 张'),
          ('可学新卡', '${a.newCards} 张'),
        ]),
      ],
    );
  }
}
