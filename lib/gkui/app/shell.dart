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
      Container(
          width: 96,
          color: const Color(0xFF121212),
          child: NavigationRail(
            backgroundColor: Colors.transparent,
            selectedIndex: selected,
            labelType: NavigationRailLabelType.all,
            minWidth: 92,
            onDestinationSelected: (value) => setState(() => selected = value),
            leading: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Image.asset('assets/plezy.png', width: 45, height: 45)),
            destinations: const <NavigationRailDestination>[
              NavigationRailDestination(
                  icon: Icon(Icons.home_outlined, size: 29),
                  selectedIcon: Icon(Icons.home, size: 31),
                  label: Text('Home')),
              NavigationRailDestination(
                  icon: Icon(Icons.video_library_outlined, size: 29),
                  selectedIcon: Icon(Icons.video_library, size: 31),
                  label: Text('Library')),
              NavigationRailDestination(
                  icon: Icon(Icons.search, size: 29),
                  selectedIcon: Icon(Icons.manage_search, size: 31),
                  label: Text('Search')),
              NavigationRailDestination(
                  icon: Icon(Icons.tune, size: 29),
                  selectedIcon: Icon(Icons.tune, size: 31),
                  label: Text('Settings')),
              NavigationRailDestination(
                  icon: Icon(Icons.monitor_heart_outlined, size: 29),
                  selectedIcon: Icon(Icons.monitor_heart, size: 31),
                  label: Text('Status')),
            ],
          )),
      const VerticalDivider(width: 1),
      Expanded(child: pages[selected]),
    ])));
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
                icon: const Icon(Icons.switch_account),
                label: const Text('Profiles')),
          ]),
          if (controller.error != null) ErrorBanner(controller.error!),
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
