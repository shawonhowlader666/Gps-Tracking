// enable_roads_api_oauth.dart
// Browser-based OAuth2 Authorization Code flow with local redirect server
// Opens your browser, you log in, then it automatically enables Roads API
// Run: dart run enable_roads_api_oauth.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

const projectId = 'smartlock-gps';
const service = 'roads.googleapis.com';
const redirectPort = 9004;
const redirectUri = 'http://localhost:$redirectPort';

// Google OAuth2 "Desktop App" credentials
// These are created in Google Cloud Console → APIs → Credentials → OAuth 2.0 Client IDs
// Using Google's own public client for testing (works for any Google account)
// Source: Android SDK / ADC public client
const clientId =
    '764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur.apps.googleusercontent.com';
const clientSecret = 'd-FL95Q19q7MQmFpd7hHD0Ty';

Future<void> main() async {
  print('');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('  Google Roads API Enabler');
  print('  Project: $projectId');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('');

  // Build authorization URL
  final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'response_type': 'code',
    'scope': 'https://www.googleapis.com/auth/cloud-platform',
    'access_type': 'offline',
    'prompt': 'consent',
  });

  // Start local server to receive the code
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, redirectPort);
  print('🌐 Opening browser for Google login...');
  print('   If browser does not open, visit:');
  print('   $authUrl\n');

  // Open browser
  await Process.run('cmd', ['/c', 'start', authUrl.toString()]);

  print('⏳ Waiting for authorization (browser login)...');

  // Wait for redirect
  String? authCode;
  await for (final request in server) {
    final code = request.uri.queryParameters['code'];
    final error = request.uri.queryParameters['error'];

    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write('''
        <html><body style="font-family:sans-serif;text-align:center;padding:50px">
          <h2 style="color:${error != null ? 'red' : 'green'}">
            ${error != null ? '❌ Authorization failed: $error' : '✅ Authorization successful!'}
          </h2>
          <p>You can close this tab now.</p>
        </body></html>
      ''')
      ..close();

    if (code != null) {
      authCode = code;
      break;
    }
    if (error != null) {
      print('❌ Authorization error: $error');
      exit(1);
    }
  }
  await server.close();

  if (authCode == null) {
    print('❌ No authorization code received');
    exit(1);
  }

  print('✅ Authorization received! Exchanging for token...');

  // Exchange code for token
  final tokenResponse = await http.post(
    Uri.parse('https://oauth2.googleapis.com/token'),
    body: {
      'client_id': clientId,
      'client_secret': clientSecret,
      'code': authCode,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
    },
  );

  final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
  if (tokenData['access_token'] == null) {
    print('❌ Token error: ${tokenData['error_description']}');
    exit(1);
  }

  final accessToken = tokenData['access_token'] as String;
  print('✅ Token obtained!\n');

  // Enable Roads API
  print('🛣️  Enabling Roads API for project "$projectId"...');
  final enableResponse = await http.post(
    Uri.parse(
        'https://serviceusage.googleapis.com/v1/projects/$projectId/services/$service:enable'),
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
    body: '{}',
  );

  print('Response status: ${enableResponse.statusCode}');

  if (enableResponse.statusCode == 200 || enableResponse.statusCode == 201) {
    print('\n✅✅ Roads API enabled successfully! ✅✅');
    print('   The vehicle marker will now snap to roads in your app.');
  } else {
    final data = jsonDecode(enableResponse.body) as Map<String, dynamic>;
    final errMsg =
        (data['error'] as Map?)?['message']?.toString() ?? enableResponse.body;
    if (errMsg.toLowerCase().contains('already enabled') ||
        enableResponse.statusCode == 409) {
      print('\n✅ Roads API was already enabled!');
    } else {
      print('\n❌ Failed: $errMsg');
      // Try checking current status
      final checkResp = await http.get(
        Uri.parse(
            'https://serviceusage.googleapis.com/v1/projects/$projectId/services/$service'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      final checkData = jsonDecode(checkResp.body) as Map<String, dynamic>;
      print('Current state: ${checkData['state']}');
    }
  }
}
