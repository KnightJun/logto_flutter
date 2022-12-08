import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:win32_registry/win32_registry.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as pathlib;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:win32/win32.dart';

Future<void> _registerScheme(String scheme, String schemeDescription) async {
  String appPath = Platform.resolvedExecutable;

  final releaseTarget = pathlib.join(pathlib.dirname(appPath), "$scheme.exe");
  String protocolRegKey = 'Software\\Classes\\$scheme';
  RegistryValue protocolRegValue = const RegistryValue(
    'URL Protocol',
    RegistryValueType.string,
    '',
  );

  RegistryValue descriptionValue = RegistryValue(
    '',
    RegistryValueType.string,
    schemeDescription,
  );
  String protocolCmdRegKey = 'shell\\open\\command';
  RegistryValue protocolCmdRegValue = RegistryValue(
    '',
    RegistryValueType.string,
    '$releaseTarget "%1"',
  );

  final regKey = Registry.currentUser.createKey(protocolRegKey);
  regKey.createValue(protocolRegValue);
  regKey.createValue(descriptionValue);
  regKey.createKey(protocolCmdRegKey).createValue(protocolCmdRegValue);
}

Future<void> _unregisterScheme(String scheme) async {
  String protocolRegKey = 'Software\\Classes\\$scheme';
  // it will cause a bug
  // Registry.currentUser.deleteKey(protocolRegKey);
  return;
}

Future<void> _releaseUrlCallbackProgram(String scheme) async {
  String appPath = Platform.resolvedExecutable;
  final releaseTarget = pathlib.join(pathlib.dirname(appPath), "$scheme.exe");
  // if(await File(releaseTarget).exists()){
  //   return;
  // }
  final exeBuff = await rootBundle.load("packages/logto_dart_sdk/assets/url_callback.exe");
  final callbackexe = await File(releaseTarget).open(mode: FileMode.write);
  await callbackexe.writeFrom(exeBuff.buffer.asUint8List());
  await callbackexe.close();
}

Future<void> _cleanSchemeCallBack(String scheme, {double overtime = 90 * 1000}) async {
  String appPath = Platform.resolvedExecutable;
  final releaseTarget = pathlib.join(pathlib.dirname(appPath), "$scheme.cb");
  if (await File(releaseTarget).exists()) {
    File(releaseTarget).delete();
  }
}

/// Implements the plugin interface for Windows.
class FlutterWebAuthWindows {
  static bool cancelFlag = false;

  /// Registers the Windows implementation.
  static void registerScheme(String scheme, String schemeDescription) {
    _registerScheme(scheme, schemeDescription);
    _releaseUrlCallbackProgram(scheme);
  }

  static Future<void> unregisterScheme(String scheme) async {
    await _unregisterScheme(scheme);
  }

  static Future<String> authenticate(
      {required String url, required String callbackUrlScheme, required bool preferEphemeral}) async {
    await _cleanSchemeCallBack(callbackUrlScheme);
    await launchUrl(Uri.parse(url));
    cancelFlag = false;
    final result = await _waitSchemeCallBack(callbackUrlScheme);
    if (result != null) {
      _bringWindowToFront();
      return result;
    }
    throw const SignalException('User canceled login');
  }

  static Future<String?> _waitSchemeCallBack(String scheme) async {
    String appPath = Platform.resolvedExecutable;
    final releaseTarget = pathlib.join(pathlib.dirname(appPath), "$scheme.cb");
    String? cbText;
    while (cancelFlag == false) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await File(releaseTarget).exists()) {
        final callbackfile = await File(releaseTarget).open(mode: FileMode.read);
        cbText = utf8.decode((await callbackfile.read(await callbackfile.length())).buffer.asInt8List());
        await callbackfile.close();
        File(releaseTarget).delete();
        break;
      }
    }
    return cbText;
  }

  static void _bringWindowToFront() {
    // https://stackoverflow.com/questions/916259/win32-bring-a-window-to-top/34414846#34414846

    final lWindowName = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final mHWnd = FindWindow(lWindowName, nullptr);
    free(lWindowName);

    final hCurWnd = GetForegroundWindow();
    final dwMyID = GetCurrentThreadId();
    final dwCurID = GetWindowThreadProcessId(hCurWnd, nullptr);
    AttachThreadInput(dwCurID, dwMyID, TRUE);
    SetWindowPos(mHWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE);
    SetWindowPos(
      mHWnd,
      HWND_NOTOPMOST,
      0,
      0,
      0,
      0,
      SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE,
    );
    SetForegroundWindow(mHWnd);
    SetFocus(mHWnd);
    SetActiveWindow(mHWnd);
    AttachThreadInput(dwCurID, dwMyID, FALSE);
  }
}
