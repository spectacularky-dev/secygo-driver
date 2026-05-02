import 'dart:convert';
import 'dart:developer';
import 'package:driver/app/chat_screens/chat_screen.dart';
import 'package:driver/constant/show_toast_dialog.dart';
import 'package:driver/models/user_model.dart';
import 'package:driver/utils/fire_store_utils.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

Future<void> firebaseMessageBackgroundHandle(RemoteMessage message) async {
  log("BackGround Message :: ${message.messageId}");
}

class NotificationService {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> initInfo() async {
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    var request = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (request.authorizationStatus == AuthorizationStatus.authorized || request.authorizationStatus == AuthorizationStatus.provisional) {
      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosInitializationSettings = DarwinInitializationSettings();

      final InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: iosInitializationSettings,
      );

      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (response.payload != null) {
            _handleNotificationClick(jsonDecode(response.payload!));
          }
        },
      );

      setupInteractedMessage();
    }
  }

  Future<void> setupInteractedMessage() async {
    // App opened from terminated state
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationClick(initialMessage.data);
    }

    // App in background and notification tapped
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationClick(message.data);
    });

    // App in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        display(message);
      }
    });

    await FirebaseMessaging.instance.subscribeToTopic("driver");
  }

  static Future<String> getToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    return token!;
  }

  void display(RemoteMessage message) async {
    try {
      const AndroidNotificationDetails androidNotificationDetails = AndroidNotificationDetails(
        'driver_notifications_channel',
        'Driver Notifications',
        channelDescription: 'App Notifications',
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'ticker',
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: iosDetails,
      );

      await flutterLocalNotificationsPlugin.show(
        0,
        message.notification?.title,
        message.notification?.body,
        notificationDetails,
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      log("Notification display error: $e");
    }
  }

  void _handleNotificationClick(Map<String, dynamic> data) async {
    log("Notification Click Data: $data");

    if (data["type"] == "chat") {
      String? orderId = data["orderId"];
      String? restaurantId = data["restaurantId"];
      String? customerId = data["customerId"];
      String? chatType = data["chatType"] ?? "Driver"; // must match ChatController

      if (orderId == null || restaurantId == null || customerId == null) {
        log("Invalid chat data in notification.");
        return;
      }

      ShowToastDialog.showLoader("Loading chat...");

      // Fetch the profiles
      UserModel? customer = await FireStoreUtils.getUserProfile(customerId);
      UserModel? restaurantUser = await FireStoreUtils.getUserProfile(restaurantId);

      ShowToastDialog.closeLoader();

      if (customer == null || restaurantUser == null) {
        log("Failed to load user profiles for chat navigation.");
        return;
      }

      // Navigate to ChatScreen with exact arguments
      Get.to(() => const ChatScreen(), arguments: {
        "customerName": customer.fullName(),
        "restaurantName": restaurantUser.fullName(),
        "orderId": orderId,
        "restaurantId": restaurantUser.id,
        "customerId": customer.id,
        "customerProfileImage": customer.profilePictureURL ?? "",
        "restaurantProfileImage": restaurantUser.profilePictureURL ?? "",
        "token": restaurantUser.fcmToken,
        "chatType": chatType, // must match ChatController
      });
    } else {
      log("Unhandled notification type: ${data['type']}");
    }
  }
}
