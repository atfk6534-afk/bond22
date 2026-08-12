import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../shared/widgets/empty_state.dart';
import 'lessons_repository.dart';

class LessonsListScreen extends ConsumerWidget {
  const LessonsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(_upcomingProvider);
    final past = ref.watch(_pastProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الحصص'),
          bottom: const TabBar(tabs: [Tab(text: 'القادمة'), Tab(text: 'السابقة')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/lessons/add'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('حصة جديدة'),
        ),
        body: TabBarView(
          children: [
            upcoming.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => const Center(child: Text('تعذر تحميل الحصص')),
              data: (list) => _LessonsList(lessons: list, emptyMessage: 'لا توجد حصص قادمة'),
            ),
            past.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => const Center(child: Text('تعذر تحميل الحصص')),
              data: (list) => _LessonsList(lessons: list, emptyMessage: 'لا توجد حصص سابقة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonsList extends StatelessWidget {
  final List<Lesson> lessons;
  final String emptyMessage;
  const _LessonsList({required this.lessons, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    if (lessons.isEmpty) {
      return EmptyState(icon: Icons.menu_book_outlined, message: emptyMessage);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      itemCount: lessons.length,
      itemBuilder: (context, i) {
        final l = lessons[i];
        return Card(
          child: ListTile(
            title: Text(l.name ?? 'حصة', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${l.date.year}/${l.date.month}/${l.date.day} — ${l.startTime}'),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => context.push('/lessons/${l.id}'),
          ),
        );
      },
    );
  }
}

final _upcomingProvider = StreamProvider((ref) => ref.watch(lessonsRepositoryProvider).watchUpcoming());
final _pastProvider = StreamProvider((ref) => ref.watch(lessonsRepositoryProvider).watchPast());
