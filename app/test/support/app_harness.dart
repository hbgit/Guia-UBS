/// Monta uma tela isolada com tema, i18n e providers — sem plugins.
///
/// Toda dependência de plataforma (TTS, picker, provisionamento) fica de fora
/// por padrão. Um teste de UI que precise de engine de voz para passar é um
/// teste que não estaria verificando a UI.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:guia_ubs/l10n/app_localizations.dart';
import 'package:guia_ubs/content/data/content_repository.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/ui/app_router.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';

/// Monta o app pelo ROTEADOR REAL, numa rota escolhida.
///
/// [harness] monta um widget solto, o que basta para telas que constroem o
/// proprio `Scaffold` (a inicial, a de idioma). Nao basta para nenhuma tela que
/// use `GubsScaffold`: ele resolve o botao voltar consultando o `GoRouter` do
/// contexto e estoura com "No GoRouter found in context" sem um.
///
/// Os portoes de idioma e de modelo ficam de fora de proposito — sao assunto de
/// `redirect_test`, e liga-los aqui faria toda tela precisar de provisionamento
/// para ser desenhada.
Widget routedHarness(
  String initialLocation, {
  LocaleStore? localeStore,
  AppLocale locale = AppLocale.pt,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  ContentRepository? content,
  List<Override> extraOverrides = const [],
  void Function(GoRouter router)? onRouter,
}) {
  final router = buildGubsRouter(initialLocation: initialLocation);
  onRouter?.call(router);

  return ProviderScope(
    overrides: [
      localeStoreProvider.overrideWithValue(
        localeStore ?? MemoryLocaleStore(locale),
      ),
      contentProvider.overrideWithValue(content),
      ...extraOverrides,
    ],
    child: MaterialApp.router(
      theme: brightness == Brightness.light ? gubsLightTheme : gubsDarkTheme,
      locale: Locale(locale.code),
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      builder: (context, widget) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: widget!,
      ),
      routerConfig: router,
    ),
  );
}

Widget harness(
  Widget child, {
  LocaleStore? localeStore,
  AppLocale locale = AppLocale.pt,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  ContentRepository? content,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      localeStoreProvider.overrideWithValue(
        localeStore ?? MemoryLocaleStore(locale),
      ),
      // `null` = sem pack instalado, que e um estado valido do app e o padrao
      // certo para um teste de UI que nao esta verificando conteudo.
      contentProvider.overrideWithValue(content),
      ...extraOverrides,
    ],
    child: MaterialApp(
      theme: brightness == Brightness.light ? gubsLightTheme : gubsDarkTheme,
      locale: Locale(locale.code),
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      builder: (context, widget) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: widget!,
      ),
      home: child,
    ),
  );
}
