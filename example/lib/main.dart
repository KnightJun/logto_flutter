import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logto_dart_sdk/logto_client.dart';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter SDK Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: const MyHomePage(title: 'Logto SDK Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static String welcome = 'Logto SDK Demo Home Page';
  String? content;

  final redirectUri = 'io.logto://callback';
  final config = const LogtoConfig(
      appId: 'ez8bpDXRZesPVFQFNLCBf',
      scopes: ['custom_data'],
      endpoint: 'https://login.jpgupup.com',
      scheme: 'io.logto',
      schemeDescription: 'logtoExample');

  late LogtoClient logtoClient;

  @override
  void initState() {
    _init();
    super.initState();
  }

  Future<void> onLoginStateChange(LogtoClientState state) async {
    if (logtoClient.loginState == LogtoClientState.loginFinish) {
      var claims = await logtoClient.idTokenClaims;
      content = claims!.toJson().toString();
    }
    setState(() {});
  }

  void _init() async {
    logtoClient = LogtoClient(
      config: config,
      httpClient: http.Client(),
    );
    logtoClient.onLoginStateChange = ((state) {
      onLoginStateChange(state);
    });
    logtoClient.tryRecoverId(
      getUserInfoCB: (userInfo) {
        print(userInfo.toJson());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget signInButton = TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.deepPurpleAccent,
        padding: const EdgeInsets.all(16.0),
        textStyle: const TextStyle(fontSize: 20),
      ),
      onPressed: () async {
        await logtoClient.signIn(
          redirectUri,
          getUserInfoCB: (userInfo) {
            print(userInfo.toJson());
          },
        );
      },
      child: const Text('Sign In'),
    );

    Widget signOutButton = TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Colors.black,
        padding: const EdgeInsets.all(16.0),
        textStyle: const TextStyle(fontSize: 20),
      ),
      onPressed: () async {
        await logtoClient.signOut(redirectUri, completelySignOut: true);
      },
      child: const Text('Sign Out'),
    );

    Widget cancelButton = TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Colors.black,
        padding: const EdgeInsets.all(16.0),
        textStyle: const TextStyle(fontSize: 20),
      ),
      onPressed: () async {
        logtoClient.cancelSignIn();
      },
      child: const Text('cancel'),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SelectableText(welcome, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.all(64),
              child: SelectableText(
                logtoClient.loginState == LogtoClientState.loginFinish ? content! : logtoClient.loginState.name,
              ),
            ),
            logtoClient.loginState == LogtoClientState.loginFinish
                ? signOutButton
                : logtoClient.loginState == LogtoClientState.waitingUserLogin
                    ? cancelButton
                    : signInButton
          ],
        ),
      ),
    );
  }
}
