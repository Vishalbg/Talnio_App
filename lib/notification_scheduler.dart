import 'dart:async';
import 'package:flutter/material.dart';
import 'email_service.dart';

class NotificationScheduler {
  static Timer? _dailyTimer;
  static Timer? _hourlyTimer;

  // Start the notification scheduler
  static void startScheduler() {
    // Stop any existing timers
    stopScheduler();

    // Schedule daily checks at 9 AM
    _scheduleDailyChecks();

    // Schedule hourly overdue checks
    _scheduleHourlyChecks();

    print('Notification scheduler started');
  }

  // Stop the notification scheduler
  static void stopScheduler() {
    _dailyTimer?.cancel();
    _hourlyTimer?.cancel();
    print('Notification scheduler stopped');
  }

  // Schedule daily checks for due dates
  static void _scheduleDailyChecks() {
    final now = DateTime.now();
    final targetTime = DateTime(now.year, now.month, now.day, 9, 0); // 9 AM

    Duration initialDelay;
    if (now.isBefore(targetTime)) {
      initialDelay = targetTime.difference(now);
    } else {
      // If it's already past 9 AM, schedule for tomorrow
      final tomorrow = targetTime.add(Duration(days: 1));
      initialDelay = tomorrow.difference(now);
    }

    // Initial timer for the first execution
    Timer(initialDelay, () {
      _performDailyChecks();

      // Set up recurring daily timer
      _dailyTimer = Timer.periodic(Duration(days: 1), (timer) {
        _performDailyChecks();
      });
    });
  }

  // Schedule hourly checks for overdue tasks
  static void _scheduleHourlyChecks() {
    _hourlyTimer = Timer.periodic(Duration(hours: 1), (timer) {
      _performHourlyChecks();
    });
  }

  // Perform daily checks
  static Future<void> _performDailyChecks() async {
    print('Performing daily notification checks...');

    try {
      // Check for due date reminders
      await EmailService.checkAndSendDueDateNotifications();

      print('Daily notification checks completed');
    } catch (e) {
      print('Error in daily notification checks: $e');
    }
  }

  // Perform hourly checks
  static Future<void> _performHourlyChecks() async {
    print('Performing hourly notification checks...');

    try {
      // Check for overdue tasks
      await EmailService.checkAndSendOverdueNotifications();

      print('Hourly notification checks completed');
    } catch (e) {
      print('Error in hourly notification checks: $e');
    }
  }

  // Manual trigger for testing
  static Future<void> triggerManualCheck() async {
    print('Manual notification check triggered...');
    await _performDailyChecks();
    await _performHourlyChecks();
  }
}
