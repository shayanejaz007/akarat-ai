import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/state_views.dart';
import '../localization/l10n.dart';
import 'routes.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: EmptyState(
          icon: Icons.explore_off_outlined,
          title: l.routeNotFound,
          action: FilledButton(onPressed: () => context.go(Routes.home), child: Text(l.tabHome)),
        ),
      ),
    );
  }
}
