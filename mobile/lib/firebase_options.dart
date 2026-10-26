// File generated for ServeSync Firebase project servesync-798c7
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDki0dmKRy7TFOBUYl6B_qM1rBKl7WFwPo',
    appId: '1:1023257586929:web:1584b42bfae6b29dffcd50',
    messagingSenderId: '1023257586929',
    projectId: 'servesync-798c7',
    authDomain: 'servesync-798c7.firebaseapp.com',
    storageBucket: 'servesync-798c7.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDki0dmKRy7TFOBUYl6B_qM1rBKl7WFwPo',
    appId: '1:1023257586929:android:a33a927a7c790196ffcd50',
    messagingSenderId: '1023257586929',
    projectId: 'servesync-798c7',
    storageBucket: 'servesync-798c7.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDki0dmKRy7TFOBUYl6B_qM1rBKl7WFwPo',
    appId: '1:1023257586929:ios:0fb8d008f4cf6c09ffcd50',
    messagingSenderId: '1023257586929',
    projectId: 'servesync-798c7',
    storageBucket: 'servesync-798c7.firebasestorage.app',
    iosBundleId: 'com.salem.ServeSyncLocal',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDki0dmKRy7TFOBUYl6B_qM1rBKl7WFwPo',
    appId: '1:1023257586929:ios:0fb8d008f4cf6c09ffcd50',
    messagingSenderId: '1023257586929',
    projectId: 'servesync-798c7',
    storageBucket: 'servesync-798c7.firebasestorage.app',
    iosBundleId: 'com.salem.ServeSyncLocal',
  );
}
