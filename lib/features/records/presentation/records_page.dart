import 'package:flutter/material.dart';

import '../../../core/widgets/page_frame.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key});
  @override
  Widget build(BuildContext context) => const PageFrame(
    title: '记录',
    subtitle: '学习日历和复习趋势将在这里汇总。',
    child: Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('开始学习后，这里会显示你的连续学习天数、复习量和错题收藏。'),
      ),
    ),
  );
}
