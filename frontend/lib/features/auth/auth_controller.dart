import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';

sealed class AuthState {
  const AuthState();
}

class Authenticated extends AuthState {
  const Authenticated(this.email);

  final String email;
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return PocketBaseApiClient(
    PocketBaseApiClient.createClient(AppConfig.backendBaseUrl),
  );
});

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final email = await ref.read(apiClientProvider).currentUserEmail();
    return email == null ? const Unauthenticated() : Authenticated(email);
  }

  Future<void> login() async {
    final api = ref.read(apiClientProvider);
    await api.loginWithGoogle(); // throws ApiException(403) when not whitelisted
    final email = await api.currentUserEmail() ?? 'user';
    state = AsyncData(Authenticated(email));
  }

  Future<void> logout() async {
    await ref.read(apiClientProvider).logout();
    state = const AsyncData(Unauthenticated());
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
