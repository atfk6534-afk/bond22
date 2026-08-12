import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RootShell extends StatelessWidget {
  final Widget child;
  final String location;
  const RootShell({super.key, required this.child, required this.location});

  static const _tabs = [
    ('/', Icons.home_rounded, 'الرئيسية'),
    ('/students', Icons.people_alt_rounded, 'الطلاب'),
    ('/lessons', Icons.menu_book_rounded, 'الحصص'),
    ('/payments', Icons.payments_rounded, 'المدفوعات'),
    ('/materials', Icons.folder_copy_rounded, 'المواد'),
  ];

  int _indexForLocation(String loc) {
    final i = _tabs.indexWhere((t) => t.$1 == loc);
    return i == -1 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _indexForLocation(location);

    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) => context.go(_tabs[i].$1),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.$2), label: t.$3),
        ],
      ),
    );
  }
}
