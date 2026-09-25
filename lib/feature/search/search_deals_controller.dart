import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../util/log_service.dart';

class SearchDealsController extends GetxController {
  final DealRepo dealRepo;

  SearchDealsController({required this.dealRepo});

  static const searchDebounce = Duration(milliseconds: 300);

  final results = <DealModel>[].obs;
  final isLoading = false.obs;
  final hasSearched = false.obs;

  /// Latest text from the field. Searches run off this, debounced, rather than
  /// straight off `onChanged`.
  final _query = ''.obs;
  Worker? _debounceWorker;

  /// Identifies the most recent search. A response whose id no longer matches
  /// belongs to a query the user has already moved on from, and is discarded:
  /// the backend answers short queries more slowly than long ones, so replies
  /// routinely arrive out of the order they were sent.
  int _requestId = 0;

  @override
  void onInit() {
    super.onInit();
    _debounceWorker = debounce(_query, _search, time: searchDebounce);
  }

  @override
  void onClose() {
    _debounceWorker?.dispose();
    super.onClose();
  }

  void onQueryChanged(String query) {
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      // Abandon anything in flight, or its reply would repopulate the list
      // after the user has cleared the field.
      _requestId++;
      _query.value = '';
      results.clear();
      hasSearched.value = false;
      isLoading.value = false;
      return;
    }

    // Show the spinner while the debounce window runs, so typing still feels
    // responsive even though no request has been sent yet.
    isLoading.value = true;
    hasSearched.value = true;
    _query.value = trimmed;
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) return;

    final id = ++_requestId;
    try {
      final found = await dealRepo.search(query);
      if (id != _requestId) return;
      results.assignAll(found);
    } catch (e) {
      if (id != _requestId) return;
      LogService.error('search failed', e);
    }
    if (id == _requestId) isLoading.value = false;
  }
}
