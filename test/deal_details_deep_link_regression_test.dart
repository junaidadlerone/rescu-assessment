import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/deal/deal_details_controller.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/fake_api_service.dart';

/// Uses only the pre-existing public API — so it compiles against both the
/// pre-fix and post-fix versions of [DealDetailsController]. It's the
/// regression witness for RES-107's crash.
///
/// In the test environment there is no navigation stack, so `Get.arguments`
/// is `null`. Calling `.onInit()` on the pre-fix controller executes
/// `deal = Get.arguments as DealModel;` and throws
/// `type 'Null' is not a subtype of type 'DealModel'` — the exact error the
/// ticket names.
///
/// The fixed controller reads `Get.parameters['id']` instead, finds nothing
/// in the test environment either, and enters its "malformed link" error
/// state. That is a rendered UI (see [DealDetailsScreen]), not a thrown
/// exception, so the assertion holds.
///
/// The main test suite (`deal_details_controller_test.dart`) drives the
/// argument / parameter readers directly and verifies the loaded / loading
/// / error / retry paths end-to-end.
///
/// Pre-fix: fails with `type 'Null' is not a subtype of type 'DealModel'`.
/// Post-fix: passes.
class _StubDealRepo extends DealRepo {
  _StubDealRepo() : super(api: FakeApiService());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onInit does not crash when arguments and id are both absent', () {
    final controller = DealDetailsController(
      dealRepo: _StubDealRepo(),
      cartService: CartService(),
      analytics: AnalyticsService(),
    );

    expect(() => controller.onInit(), returnsNormally);
    controller.onClose();
  });
}
