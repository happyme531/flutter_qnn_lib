// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';

// 导入模型管理相关
// 导入设置相关
import 'settings_manager.dart';
// 导入页面
import 'pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 加载设置
  final settingsManager = SettingsManager();
  await settingsManager.loadSettings();

  // 设置状态栏颜色为透明
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  runApp(const MyApp());
}

// 定义默认颜色方案（当动态颜色不可用时使用）
const defaultLightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF0061A4),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFD1E4FF),
  onPrimaryContainer: Color(0xFF001D36),
  secondary: Color(0xFF535F70),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFD7E3F7),
  onSecondaryContainer: Color(0xFF101C2B),
  tertiary: Color(0xFF6B5778),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFF2DAFF),
  onTertiaryContainer: Color(0xFF251431),
  error: Color(0xFFBA1A1A),
  errorContainer: Color(0xFFFFDAD6),
  onError: Color(0xFFFFFFFF),
  onErrorContainer: Color(0xFF410002),
  background: Color(0xFFFDFCFF),
  onBackground: Color(0xFF1A1C1E),
  surface: Color(0xFFFDFCFF),
  onSurface: Color(0xFF1A1C1E),
  surfaceVariant: Color(0xFFDFE2EB),
  onSurfaceVariant: Color(0xFF43474E),
  outline: Color(0xFF73777F),
  onInverseSurface: Color(0xFFF1F0F4),
  inverseSurface: Color(0xFF2F3033),
  inversePrimary: Color(0xFF9ECAFF),
  shadow: Color(0xFF000000),
  surfaceTint: Color(0xFF0061A4),
  outlineVariant: Color(0xFFC3C7CF),
  scrim: Color(0xFF000000),
);

const defaultDarkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF9ECAFF),
  onPrimary: Color(0xFF003258),
  primaryContainer: Color(0xFF00497D),
  onPrimaryContainer: Color(0xFFD1E4FF),
  secondary: Color(0xFFBBC7DB),
  onSecondary: Color(0xFF253140),
  secondaryContainer: Color(0xFF3B4858),
  onSecondaryContainer: Color(0xFFD7E3F7),
  tertiary: Color(0xFFD6BEE4),
  onTertiary: Color(0xFF3B2948),
  tertiaryContainer: Color(0xFF523F5F),
  onTertiaryContainer: Color(0xFFF2DAFF),
  error: Color(0xFFFFB4AB),
  errorContainer: Color(0xFF93000A),
  onError: Color(0xFF690005),
  onErrorContainer: Color(0xFFFFDAD6),
  background: Color(0xFF1A1C1E),
  onBackground: Color(0xFFE2E2E6),
  surface: Color(0xFF1A1C1E),
  onSurface: Color(0xFFE2E2E6),
  surfaceVariant: Color(0xFF43474E),
  onSurfaceVariant: Color(0xFFC3C7CF),
  outline: Color(0xFF8D9199),
  onInverseSurface: Color(0xFF1A1C1E),
  inverseSurface: Color(0xFFE2E2E6),
  inversePrimary: Color(0xFF0061A4),
  shadow: Color(0xFF000000),
  surfaceTint: Color(0xFF9ECAFF),
  outlineVariant: Color(0xFF43474E),
  scrim: Color(0xFF000000),
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // 使用动态颜色方案（如果可用），否则使用默认颜色方案
        final lightColorScheme = lightDynamic ?? defaultLightColorScheme;
        final darkColorScheme = darkDynamic ?? defaultDarkColorScheme;

        return MaterialApp(
          title: 'QNN 演示应用',
          theme: ThemeData(
            colorScheme: lightColorScheme,
            visualDensity: VisualDensity.adaptivePlatformDensity,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: darkColorScheme,
            visualDensity: VisualDensity.adaptivePlatformDensity,
            useMaterial3: true,
          ),
          // 使用系统设置的亮/暗模式
          themeMode: ThemeMode.system,
          home: const HomePage(),
        );
      },
    );
  }
}
