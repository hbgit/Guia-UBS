/// Monta uma tela isolada com tema, i18n e providers — sem plugins.
///
/// Toda dependência de plataforma (TTS, picker, provisionamento) fica de fora
/// por padrão. Um teste de UI que precise de engine de voz para passar é um
/// teste que não estaria verificando a UI.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guia_ubs/l10n/app_localizations.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';

Widget harness(
  Widget child, {
  LocaleStore? localeStore,
  AppLocale locale = AppLocale.pt,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      localeStoreProvider.overrideWithValue(
        localeStore ?? MemoryLocaleStore(locale),
      ),
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
