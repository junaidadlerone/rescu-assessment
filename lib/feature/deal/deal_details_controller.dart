import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../service/analytics_service.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

/// The screen has two entry paths that hand it data differently:
///
///   1. Feed / flash-rail tap → passes the whole `DealModel` in `Get.arguments`.
///      Cheap, avoids a network round-trip when we already have the object.
///   2. Deep link (e.g. `rescu://open/deal?id=42&source=push`) → only carries
///      `id` in the query string; `Get.arguments` is `null`. Must fetch by id.
///
/// The controller has to satisfy both without hard-casting `Get.arguments`,
/// which used to crash the deep-link path with `type 'Null' is not a subtype
/// of type 'DealModel'`. See RES-107.
class DealDetailsController extends GetxController {
  final DealRepo dealRepo;
  final CartService cartService;
  final AnalyticsService analytics;

  /// Testing seams. In production these default to reading `Get.arguments`
  /// and `Get.parameters`, which are getter-only on the GetX facade and so
  /// cannot be driven directly from unit tests. Overriding these lets a test
  /// construct the controller as if it had been reached via either entry
  /// path — feed tap (arguments set) or deep link (parameters set).
  final Object? Function() argumentsReader;
  final Map<String, String?> Function() parametersReader;

  DealDetailsController({
    required this.dealRepo,
    required this.cartService,
    required this.analytics,
    Object? Function()? argumentsReader,
    Map<String, String?> Function()? parametersReader,
  })  : argumentsReader = argumentsReader ?? (() => Get.arguments),
        parametersReader = parametersReader ?? (() => Get.parameters);

  final _deal = Rxn<DealModel>();
  final _quantityLeft = RxnInt();
  final _isLoading = false.obs;
  final _errorMessage = RxnString();

  DealModel? get deal => _deal.value;
  int? get quantityLeft => _quantityLeft.value;
  bool get isLoading => _isLoading.value;
  String? get errorMessage => _errorMessage.value;
  bool get canAddToCart => !isLoading && errorMessage == null && deal != null;

  Worker? _availabilityWatcher;
  int? _pendingId;

  @override
  void onInit() {
    super.onInit();
    final passed = argumentsReader();
    if (passed is DealModel) {
      _adopt(passed);
    } else {
      final idParam = parametersReader()['id'];
      final id = idParam == null ? null : int.tryParse(idParam);
      if (id == null) {
        // No usable arguments and no parseable id — nothing to render. Leave
        // the screen in the error state; router-level validation would be
        // cleaner but is out of scope for this ticket.
        _errorMessage.value = 'That deal link is malformed.';
        _logView(id: null);
      } else {
        _pendingId = id;
        _logView(id: id);
        _fetch(id);
      }
    }
  }

  void _adopt(DealModel d) {
    _deal.value = d;
    _quantityLeft.value = d.quantityLeft;
    _logView(id: d.id);
    _wireAvailabilityWatcher();
  }

  Future<void> _fetch(int id) async {
    _isLoading.value = true;
    _errorMessage.value = null;
    try {
      final fetched = await dealRepo.fetchById(id);
      _deal.value = fetched;
      _quantityLeft.value = fetched.quantityLeft;
      _wireAvailabilityWatcher();
    } catch (e) {
      LogService.error('deep-link fetch failed (id=$id)', e);
      // Deliberately generic — the fake API doesn't distinguish 404 from
      // transient failures, so the retry surface is the same for both.
      _errorMessage.value = 'We couldn\'t load that deal. Try again?';
    } finally {
      _isLoading.value = false;
    }
  }

  /// Retry hook for the error-state UI.
  Future<void> retry() async {
    final id = deal?.id ?? _pendingId;
    if (id == null) return;
    await _fetch(id);
  }

  void _wireAvailabilityWatcher() {
    // Subscribe once the deal is loaded — before that there is nothing to
    // re-check. Same shape as the RES-103 fix: the Worker is disposed in
    // onClose so it doesn't outlive this controller.
    _availabilityWatcher ??=
        ever(cartService.itemCount, (_) => _recheckAvailability());
  }

  Future<void> _recheckAvailability() async {
    final current = deal;
    if (current == null) return;
    LogService.log('re-checking availability for deal ${current.id}');
    final fresh = await dealRepo.fetchById(current.id);
    _quantityLeft.value = fresh.quantityLeft;
  }

  void _logView({required int? id}) {
    analytics.logEvent('deal_details_view', {
      'deal_id': id,
      'source': parametersReader()['source'] ?? 'unknown',
    });
  }

  void addToCart() {
    final current = deal;
    if (current == null) return;
    cartService.add(current);
    Get.snackbar(
      'Added to bag',
      '${current.name} — pick up ${current.pickupWindow.label}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void onClose() {
    _availabilityWatcher?.dispose();
    super.onClose();
  }
}
