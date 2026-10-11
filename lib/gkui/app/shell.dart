part of '../../main_gkui.dart';

class GkuiShell extends StatefulWidget {
  const GkuiShell({required this.controller, super.key});
  final GkuiController controller;
  @override
  State<GkuiShell> createState() => _GkuiShellState();
}

class _GkuiShellState extends State<GkuiShell> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePane(controller: widget.controller),
      LibraryPane(controller: widget.controller),
      SearchPane(controller: widget.controller),
      SettingsPane(controller: widget.controller),
      DiagnosticsPane(
          logs: widget.controller.logs, controller: widget.controller),
    ];
    return Scaffold(
        body: SafeArea(
            child: Row(children: <Widget>[
      // Five equal touch targets fill the rail's height. The stock
      // NavigationRail with a logo was taller than 480 pixels and cut off
      // the last destination on the head unit.
      Container(
        width: 100,
        color: const Color(0xFF121212),
        child: Column(children: <Widget>[
          for (final (index, destination) in shellDestinations.indexed)
            Expanded(
              child: ShellRailButton(
                icon: destination.$1,
                label: destination.$2,
                selected: index == selected,
                onPressed: () => setState(() => selected = index),
              ),
            ),
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(child: pages[selected]),
    ])));
  }
}

const List<(IconData, String)> shellDestinations = <(IconData, String)>[
  (Icons.home, 'Home'),
  (Icons.video_library, 'Library'),
  (Icons.search, 'Search'),
  (Icons.tune, 'Settings'),
  (Icons.monitor_heart, 'Status'),
];

class ShellRailButton extends StatelessWidget {
  const ShellRailButton(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onPressed,
      super.key});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final color = selected ? accent : Colors.white70;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF242424) : null,
            border: Border(
                left: BorderSide(
                    color: selected ? accent : Colors.transparent, width: 4)),
          ),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 32, color: color),
                const SizedBox(height: 4),
                Text(label,
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 15,
                        color: color,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400)),
              ]),
        ),
      ),
    );
  }
}

class HomePane extends StatelessWidget {
  const HomePane({required this.controller, super.key});
  final GkuiController controller;
  @override
  Widget build(BuildContext context) {
    if (controller.loadingContent && controller.shelves.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () => controller.refreshContent(includeLibrary: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
        children: <Widget>[
          Row(children: <Widget>[
            Expanded(
                child: PageHeading(
                    title: controller.api!.session!.serverName,
                    subtitle:
                        '${controller.currentHomeUser?.displayName ?? controller.api!.currentHomeUserName ?? 'Plex Home'} • pull down to refresh')),
            ElevatedButton.icon(
                onPressed: controller.switchingProfile
                    ? null
                    : () => _showProfiles(context),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(150, 62),
                    padding: const EdgeInsets.symmetric(horizontal: 18)),
                icon: const Icon(Icons.switch_account, size: 28),
                label: const Text('Profiles', style: TextStyle(fontSize: 19))),
          ]),
          if (controller.error != null) ErrorBanner(controller.error!),
          if (controller.lastPlaybackProblem case final problem?)
            PlaybackProblemBanner(problem: problem, controller: controller),
          const SizedBox(height: 18),
          if (controller.shelves.isEmpty)
            const Padding(
                padding: EdgeInsets.all(30),
                child: Center(
                    child: Text('No home items returned by this server.',
                        style: TextStyle(fontSize: 19))))
          else
            for (final shelf in controller.shelves) ...<Widget>[
              MediaShelf(shelf: shelf, controller: controller),
              const SizedBox(height: 24),
            ],
        ],
      ),
    );
  }

  Future<void> _showProfiles(BuildContext context) async {
    await controller.loadHomeUsers();
    if (!context.mounted) return;
    if (controller.homeUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Plex Home profiles returned.')));
      return;
    }
    final user = await showDialog<PlexHomeUser>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch Plex Home profile'),
        content: SizedBox(
          width: 520,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: controller.homeUsers.length,
            itemBuilder: (_, index) {
              final item = controller.homeUsers[index];
              final current = item.uuid == controller.currentHomeUser?.uuid;
              return ListTile(
                leading: Icon(item.guest ? Icons.person_outline : Icons.person),
                title: Text(item.displayName),
                subtitle: Text(item.admin
                    ? 'Home owner'
                    : item.guest
                        ? 'Guest'
                        : 'Managed user'),
                trailing: current
                    ? const Icon(Icons.check, color: Color(0xFFE5A00D))
                    : item.protected
                        ? const Icon(Icons.lock_outline)
                        : null,
                onTap: current ? null : () => Navigator.pop(context, item),
              );
            },
          ),
        ),
      ),
    );
    if (user == null || !context.mounted) return;
    String? pin;
    if (user.protected) {
      final field = TextEditingController();
      pin = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('PIN for ${user.displayName}'),
          content: TextField(
            controller: field,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(labelText: 'Plex Home PIN'),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, field.text),
                child: const Text('Switch')),
          ],
        ),
      );
      field.dispose();
      if (pin == null) return;
    }
    try {
      await controller.switchProfile(user, pin: pin);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(controller.error ?? 'Profile switch failed.')));
      }
    }
  }
}

class LibraryPane extends StatelessWidget {
  const LibraryPane({required this.controller, super.key});
  final GkuiController controller;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
            child: PageHeading(
                title: 'Library',
                subtitle: controller.selectedSection?.title ??
                    'No Plex libraries found')),
        SizedBox(
            height: 54,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: controller.sections.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final section = controller.sections[index];
                return ChoiceChip(
                  label:
                      Text(section.title, style: const TextStyle(fontSize: 17)),
                  selected: section.key == controller.selectedSection?.key,
                  onSelected: (_) => controller.selectSection(section),
                );
              },
            )),
        SizedBox(
            height: 48,
            child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  ChoiceChip(
                      label: const Text('All'),
                      selected: controller.libraryView == LibraryView.all,
                      onSelected: (_) =>
                          controller.selectLibraryView(LibraryView.all)),
                  const SizedBox(width: 10),
                  ChoiceChip(
                      label: const Text('Unwatched'),
                      selected: controller.libraryView == LibraryView.unwatched,
                      onSelected: (_) =>
                          controller.selectLibraryView(LibraryView.unwatched)),
                  const SizedBox(width: 10),
                  ChoiceChip(
                      label: const Text('Collections'),
                      selected:
                          controller.libraryView == LibraryView.collections,
                      onSelected: (_) => controller
                          .selectLibraryView(LibraryView.collections)),
                ])),
        if (controller.error != null) ErrorBanner(controller.error!),
        Expanded(
            child: controller.loadingContent
                ? const Center(child: CircularProgressIndicator())
                : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.extentAfter < 500) {
                        unawaited(controller.loadMoreLibrary());
                      }
                      return false;
                    },
                    child: GridView.builder(
                      padding: const EdgeInsets.all(24),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 170,
                        childAspectRatio: 0.66,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 20,
                      ),
                      itemCount: controller.libraryItems.length +
                          (controller.loadingMoreLibrary ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= controller.libraryItems.length) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        return MediaCard(
                            media: controller.libraryItems[index],
                            controller: controller);
                      },
                    ),
                  )),
      ]);
}

class SearchPane extends StatefulWidget {
  const SearchPane({required this.controller, super.key});
  final GkuiController controller;

  @override
  State<SearchPane> createState() => _SearchPaneState();
}

class _SearchPaneState extends State<SearchPane> {
  late final TextEditingController field =
      TextEditingController(text: widget.controller.searchQuery);

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 18, 24, 12),
            child: PageHeading(
                title: 'Search', subtitle: 'Find movies, shows and episodes'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: <Widget>[
              Expanded(
                child: TextField(
                  controller: field,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 19),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search this Plex server',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: widget.controller.runSearch,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: widget.controller.searching
                    ? null
                    : () => widget.controller.runSearch(field.text),
                icon: const Icon(Icons.search),
                label: const Text('Search'),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              children: SearchMediaFilter.values
                  .map((filter) => Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ChoiceChip(
                          label: Text(switch (filter) {
                            SearchMediaFilter.all => 'All',
                            SearchMediaFilter.movie => 'Movies',
                            SearchMediaFilter.show => 'Shows',
                            SearchMediaFilter.episode => 'Episodes',
                          }),
                          selected: widget.controller.searchFilter == filter,
                          onSelected: (_) =>
                              widget.controller.setSearchFilter(filter),
                        ),
                      ))
                  .toList(),
            ),
          ),
          if (widget.controller.error != null)
            ErrorBanner(widget.controller.error!),
          Expanded(
            child: widget.controller.searching
                ? const Center(child: CircularProgressIndicator())
                : widget.controller.searchResults.isEmpty
                    ? Center(
                        child: Text(
                          widget.controller.searchQuery.isEmpty
                              ? 'Enter at least two characters.'
                              : 'No matching Plex items.',
                          style: const TextStyle(
                              fontSize: 18, color: Colors.white70),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(24),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 170,
                          childAspectRatio: 0.66,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 20,
                        ),
                        itemCount: widget.controller.searchResults.length,
                        itemBuilder: (context, index) => MediaCard(
                          media: widget.controller.searchResults[index],
                          controller: widget.controller,
                        ),
                      ),
          ),
        ],
      );
}

/// Why the last video closed, with a one-tap way back into it.
class PlaybackProblemBanner extends StatelessWidget {
  const PlaybackProblemBanner(
      {required this.problem, required this.controller, super.key});
  final PlaybackProblem problem;
  final GkuiController controller;

  @override
  Widget build(BuildContext context) {
    final resumeAt = problem.resumeAtMs;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2410),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF8A5A20)),
      ),
      child: Row(children: <Widget>[
        const Icon(Icons.warning_amber_rounded,
            size: 32, color: Color(0xFFFFB74D)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${problem.media.title} stopped',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                Text(
                    <String>[
                      problem.message,
                      if (problem.reconnectAttempts > 0)
                        'Gave up after ${problem.reconnectAttempts} reconnect '
                            '${problem.reconnectAttempts == 1 ? 'attempt' : 'attempts'}.',
                    ].join(' '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 15, color: Colors.white70)),
              ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 60,
          child: ElevatedButton.icon(
            onPressed: () {
              controller.dismissPlaybackProblem();
              controller.play(context, problem.media, problem.mode,
                  startMs: resumeAt);
            },
            icon: const Icon(Icons.play_arrow, size: 28),
            label: Text(
                resumeAt != null && resumeAt > 0
                    ? 'Resume ${formatPlaybackTime(resumeAt)}'
                    : 'Try again',
                style: const TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          height: 60,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: controller.dismissPlaybackProblem,
            child: const Icon(Icons.close, size: 28, semanticLabel: 'Dismiss'),
          ),
        ),
      ]),
    );
  }
}
