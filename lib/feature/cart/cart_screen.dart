import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app_config.dart';
import '../../model/cart_item_model.dart';
import '../../service/cart_service.dart';
import '../../service/countdown_ticker.dart';
import '../shared_widget/the_network_image.dart';
import 'cart_controller.dart';

class CartScreen extends GetView<CartController> {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = controller.cartService;
    return Scaffold(
      appBar: AppBar(title: const Text('My bag')),
      body: Obx(() {
        if (cart.items.isEmpty) {
          return const Center(child: Text('Your bag is empty'));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: cart.items.length,
          itemBuilder: (context, index) => _CartLine(
            item: cart.items[index],
            cart: cart,
          ),
        );
      }),
      bottomNavigationBar: Obx(() {
        if (cart.items.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          color: Colors.white,
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 13)),
                  Text('฿${cart.total.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: FilledButton(
                  onPressed: controller.isCheckingOut.value
                      ? null
                      : controller.checkout,
                  child: controller.isCheckingOut.value
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Checkout'),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _CartLine extends StatelessWidget {
  final CartItemModel item;
  final CartService cart;

  const _CartLine({required this.item, required this.cart});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.white,
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TheNetworkImage(
                  url: item.deal.imageUrl,
                  width: 64,
                  height: 64,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.deal.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600)),
                      Text(item.deal.storeName,
                          style: TextStyle(
                              fontSize: 12.5, color: Colors.grey.shade600)),
                      Text('฿${item.deal.price.toStringAsFixed(0)} each',
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppConfig.primaryGreen,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => cart.decrement(item.deal.id),
                    ),
                    Text('${item.quantity}',
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => cart.add(item.deal),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            _HoldStatusRow(item: item, cart: cart),
          ],
        ),
      ),
    );
  }
}

/// Per-line hold status. Three visual states driven by CartService:
///   - Reserving  — spinner + "Reserving stock…"
///   - Active     — timer icon + "Held for mm:ss"
///   - Expired    — warning icon + "Hold expired" + Refresh button
///
/// The Obx here reads `cart.reservingDealIds` and `ticker.now.value`; it
/// rebuilds only this row per tick, never the parent Card or the image
/// above. Same discipline as F-1's FlashCountdown.
class _HoldStatusRow extends StatelessWidget {
  final CartItemModel item;
  final CartService cart;

  const _HoldStatusRow({required this.item, required this.cart});

  @override
  Widget build(BuildContext context) {
    final ticker = Get.find<CountdownTicker>();
    return Obx(() {
      // Read ticker.now.value so the row rebuilds when the second changes.
      ticker.now.value; // ignore: unused_local_variable
      final reserving = cart.isReserving(item.deal.id);
      if (reserving) {
        return const Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Reserving stock…',
                style: TextStyle(fontSize: 12.5, color: Colors.black54)),
          ],
        );
      }
      final res = item.reservation;
      if (res == null) {
        return const SizedBox.shrink();
      }
      if (cart.isReservationExpired(item)) {
        return Row(
          children: [
            Icon(Icons.error_outline,
                size: 16, color: Colors.orange.shade700),
            const SizedBox(width: 6),
            Text('Hold expired',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => cart.refreshHold(item.deal.id),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        );
      }
      final remaining = cart.holdRemaining(item) ?? Duration.zero;
      return Row(
        children: [
          Icon(Icons.lock_clock,
              size: 15, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text('Held for ${_mmss(remaining)}',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
        ],
      );
    });
  }
}

String _mmss(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final m = (total ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
