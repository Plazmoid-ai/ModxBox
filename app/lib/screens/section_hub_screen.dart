import 'package:flutter/material.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../services/l10n/locale_controller.dart';
import '../services/subscription/auto_updater.dart';
import 'about_screen.dart';
import 'app_settings_screen.dart';
import 'config_screen.dart';
import 'debug_screen.dart';
import 'dns_settings_screen.dart';
import 'routing_screen.dart';
import 'settings_screen.dart';
import 'speed_test_screen.dart';
import 'stats_screen.dart';
import 'subscriptions_screen.dart';

class HubSection {
  const HubSection({
    required this.title,
    required this.icon,
    required this.tabs,
  });

  final String title;
  final IconData icon;
  final List<HubTab> tabs;
}

class HubTab {
  const HubTab({
    required this.title,
    required this.icon,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final WidgetBuilder builder;
}

class HubTool {
  const HubTool({
    required this.title,
    required this.icon,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final WidgetBuilder builder;
}

class SectionHubScreen extends StatefulWidget {
  const SectionHubScreen({
    super.key,
    required this.sections,
    required this.tools,
    this.initialIndex = 0,
  }) : assert(sections.length > 0);

  final List<HubSection> sections;
  final List<HubTool> tools;
  final int initialIndex;

  @override
  State<SectionHubScreen> createState() => _SectionHubScreenState();
}

class _SectionHubScreenState extends State<SectionHubScreen> {
  late final int _initialIndex =
      widget.initialIndex.clamp(0, widget.sections.length - 1);
  late final PageController _pages =
      PageController(initialPage: _initialIndex);
  late int _index = _initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    _pages.animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
                          child: Text(
                            widget.sections[_index].title,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Expanded(
                          child: PageView.builder(
                            controller: _pages,
                            itemCount: widget.sections.length,
                            onPageChanged: (i) => setState(() => _index = i),
                            itemBuilder: (c, i) => _KeepAlive(
                              child: _HubTabList(section: widget.sections[i]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 64,
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        IconButton.outlined(
                          tooltip: getLocalText.s("Main screen"),
                          icon: const Icon(Icons.home_outlined),
                          onPressed: () =>
                              Navigator.of(context).popUntil((r) => r.isFirst),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemExtent: 60,
                            itemCount: widget.sections.length,
                            itemBuilder: (c, i) => _RibbonItem(
                              section: widget.sections[i],
                              active: i == _index,
                              onTap: () => _select(i),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _ToolsGrid(tools: widget.tools),
          ],
        ),
      ),
    );
  }
}

class _RibbonItem extends StatelessWidget {
  const _RibbonItem({
    required this.section,
    required this.active,
    required this.onTap,
  });

  final HubSection section;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: active,
      label: section.title,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Center(
          child: AnimatedScale(
            scale: active ? 1.3 : 1.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? cs.secondaryContainer : Colors.transparent,
              ),
              child: Icon(
                section.icon,
                size: 22,
                color: active ? cs.onSecondaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolsGrid extends StatelessWidget {
  const _ToolsGrid({required this.tools});

  final List<HubTool> tools;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.3,
        padding: const EdgeInsets.all(12),
        children: [
          for (final tool in tools)
            Material(
              color: cs.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: cs.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: tool.builder),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        tool.icon,
                        size: 28,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tool.title,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, height: 1.2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

List<HubSection> buildHubSections({
  required HomeController homeController,
  required SubscriptionController subController,
  required AutoUpdater autoUpdater,
}) =>
    [
      HubSection(
        title: getLocalText.s("Routing"),
        icon: Icons.route_outlined,
        tabs: [
          HubTab(
            title: getLocalText.s("Directions"),
            icon: Icons.alt_route,
            builder: (_) => RoutingScreen(
              subController: subController,
              homeController: homeController,
              singleTabIndex: 0,
            ),
          ),
          HubTab(
            title: getLocalText.s("Presets"),
            icon: Icons.grid_view_outlined,
            builder: (_) => RoutingScreen(
              subController: subController,
              homeController: homeController,
              singleTabIndex: 1,
            ),
          ),
          HubTab(
            title: getLocalText.s("Rules"),
            icon: Icons.rule_outlined,
            builder: (_) => RoutingScreen(
              subController: subController,
              homeController: homeController,
              singleTabIndex: 2,
            ),
          ),
          HubTab(
            title: getLocalText.s("Tunnel apps"),
            icon: Icons.apps_outlined,
            builder: (_) => RoutingScreen(
              subController: subController,
              homeController: homeController,
              singleTabIndex: 3,
            ),
          ),
        ],
      ),
      HubSection(
        title: getLocalText.s("DNS Settings"),
        icon: Icons.language,
        tabs: [
          HubTab(
            title: getLocalText.s("Settings"),
            icon: Icons.tune,
            builder: (_) => DnsSettingsScreen(
              subController: subController,
              homeController: homeController,
              singleTabIndex: 0,
            ),
          ),
          HubTab(
            title: getLocalText.s("DNS Servers"),
            icon: Icons.dns_outlined,
            builder: (_) => DnsSettingsScreen(
              subController: subController,
              homeController: homeController,
              singleTabIndex: 1,
            ),
          ),
          HubTab(
            title: getLocalText.s("DNS Rules"),
            icon: Icons.rule_outlined,
            builder: (_) => DnsSettingsScreen(
              subController: subController,
              homeController: homeController,
              singleTabIndex: 2,
            ),
          ),
        ],
      ),
      HubSection(
        title: getLocalText.s("VPN Settings"),
        icon: Icons.tune,
        tabs: [
          HubTab(
            title: getLocalText.s("System"),
            icon: Icons.settings_suggest_outlined,
            builder: (_) => SettingsScreen(
              subController: subController,
              homeController: homeController,
              singleTabIndex: 0,
            ),
          ),
          HubTab(
            title: getLocalText.s("Core"),
            icon: Icons.data_object,
            builder: (_) => SettingsScreen(
              subController: subController,
              homeController: homeController,
              singleTabIndex: 1,
            ),
          ),
          HubTab(
            title: getLocalText.s("Mode"),
            icon: Icons.vpn_key_outlined,
            builder: (_) => SettingsScreen(
              subController: subController,
              homeController: homeController,
              singleTabIndex: 2,
            ),
          ),
        ],
      ),
      HubSection(
        title: getLocalText.s("App Settings"),
        icon: Icons.settings_outlined,
        tabs: [
          HubTab(
            title: getLocalText.s("General"),
            icon: Icons.tune,
            builder: (_) => AppSettingsScreen(
              homeController: homeController,
              subController: subController,
              autoUpdater: autoUpdater,
              initialTab: 0,
              singleTabIndex: 0,
            ),
          ),
          HubTab(
            title: getLocalText.s("Subscriptions"),
            icon: Icons.rss_feed,
            builder: (_) => AppSettingsScreen(
              homeController: homeController,
              subController: subController,
              autoUpdater: autoUpdater,
              initialTab: 2,
              singleTabIndex: 2,
            ),
          ),
          HubTab(
            title: getLocalText.s("Diagnostics"),
            icon: Icons.monitor_heart_outlined,
            builder: (_) => AppSettingsScreen(
              homeController: homeController,
              subController: subController,
              autoUpdater: autoUpdater,
              initialTab: 3,
              singleTabIndex: 3,
            ),
          ),
          HubTab(
            title: getLocalText.s("Automation"),
            icon: Icons.bolt,
            builder: (_) => AppSettingsScreen(
              homeController: homeController,
              subController: subController,
              autoUpdater: autoUpdater,
              initialTab: 4,
              singleTabIndex: 4,
            ),
          ),
          HubTab(
            title: getLocalText.s("History"),
            icon: Icons.history,
            builder: (_) => AppSettingsScreen(
              homeController: homeController,
              subController: subController,
              autoUpdater: autoUpdater,
              initialTab: 5,
              singleTabIndex: 5,
            ),
          ),
        ],
      ),
    ];

class _HubTabList extends StatelessWidget {
  const _HubTabList({required this.section});

  final HubSection section;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: section.tabs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final tab = section.tabs[index];
        return SizedBox(
          height: 60,
          child: Material(
            color: cs.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: cs.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: tab.builder),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Icon(
                        tab.icon,
                        size: 26,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        tab.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(fontSize: 19),
                      ),
                    ),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

List<HubTool> buildHubTools({
  required HomeController homeController,
  required SubscriptionController subController,
  required AutoUpdater autoUpdater,
}) =>
    [
      HubTool(
        title: getLocalText.s("Servers"),
        icon: Icons.storage_outlined,
        builder: (_) => SubscriptionsScreen(
          subController: subController,
          homeController: homeController,
          autoUpdater: autoUpdater,
        ),
      ),
      HubTool(
        title: getLocalText.s("Statistics"),
        icon: Icons.bar_chart,
        builder: (_) => StatsScreen(
          configRaw: homeController.state.activeConfigRaw,
          subController: subController,
          homeController: homeController,
        ),
      ),
      HubTool(
        title: getLocalText.s("Speed Test"),
        icon: Icons.speed,
        builder: (_) => SpeedTestScreen(homeController: homeController),
      ),
      HubTool(
        title: getLocalText.s("Debug"),
        icon: Icons.bug_report_outlined,
        builder: (_) => const DebugScreen(),
      ),
      HubTool(
        title: getLocalText.s("Config"),
        icon: Icons.data_object,
        builder: (_) => ConfigScreen(controller: homeController),
      ),
      HubTool(
        title: getLocalText.s("About"),
        icon: Icons.info_outline,
        builder: (_) => const AboutScreen(),
      ),
    ];

Future<void> openSectionHub(
  BuildContext context, {
  required HomeController homeController,
  required SubscriptionController subController,
  required AutoUpdater autoUpdater,
  int initialIndex = 0,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => AnimatedBuilder(
        // App Settings can change the active locale while this route stays alive.
        // Rebuild the localized labels without resetting the selected section.
        animation: LocaleController.I,
        builder: (_, _) => SectionHubScreen(
          sections: buildHubSections(
            homeController: homeController,
            subController: subController,
            autoUpdater: autoUpdater,
          ),
          tools: buildHubTools(
            homeController: homeController,
            subController: subController,
            autoUpdater: autoUpdater,
          ),
          initialIndex: initialIndex,
        ),
      ),
    ),
  );
}
