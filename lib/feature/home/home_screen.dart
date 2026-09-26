import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

import '../../app_config.dart';
import '../../routes/routes.dart';
import '../shared_widget/deal_card.dart';
import '../shared_widget/shimmer_deal_card.dart';
import 'home_controller.dart';
import 'widget/flash_deals_section.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Scaffold is intentionally NOT wrapped in Obx. Each reactive island below
    // rebuilds only when its own dependency changes — see RES-105.
    return Scaffold(
      appBar: _HomeAppBar(controller: controller),
      body: Obx(() {
        if (controller.isLoading.value) {
          return ListView(
            children: const [
              ShimmerDealCard(),
              ShimmerDealCard(),
              ShimmerDealCard(),
            ],
          );
        }
        // Materialise the filtered iterable once for both length and access.
        final visible = controller.visibleDeals.toList(growable: false);
        return SmartRefresher(
          controller: controller.refreshController,
          enablePullDown: true,
          enablePullUp: true,
          onRefresh: controller.refreshDeals,
          onLoading: controller.loadMore,
          child: CustomScrollView(
            controller: controller.scrollController,
            slivers: [
              if (controller.flashDeals.isNotEmpty)
                SliverToBoxAdapter(
                  child: FlashDealsSection(deals: controller.flashDeals),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const Text('Nearby deals',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      FilterChip(
                        label: const Text('Pickup today'),
                        selected: controller.todayOnly.value,
                        onSelected: (v) => controller.todayOnly.value = v,
                      ),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, i) => DealCard(deal: visible[i]),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      }),
      floatingActionButton: Obx(() => controller.showScrollToTop.value
          ? FloatingActionButton.small(
              onPressed: controller.scrollToTop,
              child: const Icon(Icons.arrow_upward),
            )
          : const SizedBox.shrink()),
    );
  }
}

// Extracted so the AppBar's Obx watches only [showAppBarShadow]. The rest of
// the bar is const or captures immutable callbacks — nothing else rebuilds on
// scroll.
class _HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final HomeController controller;
  const _HomeAppBar({required this.controller});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return Obx(() => AppBar(
          elevation: controller.showAppBarShadow.value ? 2 : 0,
          shadowColor: Colors.black26,
          title: const Row(
            children: [
              Icon(Icons.eco, color: AppConfig.primaryGreen),
              SizedBox(width: 8),
              Text('Rescu',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => Get.toNamed(Routes.search),
            ),
            IconButton(
              icon: const Icon(Icons.map_outlined),
              onPressed: () => Get.toNamed(Routes.map),
            ),
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => Get.toNamed(Routes.orders),
            ),
            IconButton(
              icon: const Icon(Icons.shopping_bag_outlined),
              onPressed: () => Get.toNamed(Routes.cart),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'deeplink') _showDeepLinkDialog(context);
                if (value == 'analytics') Get.toNamed(Routes.analyticsDebug);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                    value: 'deeplink', child: Text('Simulate deep link…')),
                PopupMenuItem(
                    value: 'analytics', child: Text('Analytics debug')),
              ],
            ),
          ],
        ));
  }

  void _showDeepLinkDialog(BuildContext context) {
    final textController =
        TextEditingController(text: 'rescu://open/deal?id=42&source=push');
    Get.dialog(
      AlertDialog(
        title: const Text('Simulate deep link'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            helperText: 'e.g. rescu://open/deal?id=42&source=push',
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final uri = Uri.tryParse(textController.text.trim());
              Get.back();
              if (uri == null) return;
              final route = uri.hasQuery
                  ? '${uri.path}?${uri.query}'
                  : uri.path;
              Get.toNamed(route);
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}
