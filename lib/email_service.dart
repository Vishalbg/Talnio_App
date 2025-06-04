import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EmailService {
  // SMTP Configuration - Replace with your actual SMTP settings
  static const String _smtpHost = 'smtp.gmail.com';
  static const int _smtpPort = 587;
  static const String _username = 'talnioofficial@gmail.com'; // Replace with your email
  static const String _password = 'bqnk mowy tfgn sozp'; // Replace with your app password
  static const String _fromEmail = 'talnioofficial@gmail.com'; // Replace with your email
  static const String _fromName = 'Talnio';

  static SmtpServer get _smtpServer => gmail(_username, _password);

  // Send task assignment email
  static Future<bool> sendTaskAssignmentEmail({
    required String employeeEmail,
    required String employeeName,
    required String taskTitle,
    required String taskDescription,
    required String dueDate,
    required String managerName,
  }) async {
    try {
      final message = Message()
        ..from = Address(_fromEmail, _fromName)
        ..recipients.add(employeeEmail)
        ..subject = 'New Task Assigned: $taskTitle'
        ..html = '''
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background-color: #2563EB; color: white; padding: 20px; text-align: center;">
              <h1 style="margin: 0;">New Task Assigned</h1>
            </div>
            <div style="padding: 20px; background-color: #f9fafb;">
              <p>Dear $employeeName,</p>
              <p>You have been assigned a new task by $managerName.</p>
              
              <div style="background-color: white; padding: 15px; border-radius: 8px; margin: 15px 0;">
                <h3 style="color: #2563EB; margin-top: 0;">Task Details:</h3>
                <p><strong>Title:</strong> $taskTitle</p>
                <p><strong>Description:</strong> $taskDescription</p>
                <p><strong>Due Date:</strong> $dueDate</p>
              </div>
              
              <p>Please log into the Talnio app to view and manage your task.</p>
              <p>Best regards,<br>Talnio</p>
            </div>
          </div>
        ''';

      await send(message, _smtpServer);
      print('Task assignment email sent successfully to $employeeEmail');
      return true;
    } catch (e) {
      print('Error sending task assignment email: $e');
      return false;
    }
  }

  // Send due date reminder email
  static Future<bool> sendDueDateReminderEmail({
    required String employeeEmail,
    required String employeeName,
    required String taskTitle,
    required String dueDate,
  }) async {
    try {
      final message = Message()
        ..from = Address(_fromEmail, _fromName)
        ..recipients.add(employeeEmail)
        ..subject = 'Task Due Today: $taskTitle'
        ..html = '''
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background-color: #F59E0B; color: white; padding: 20px; text-align: center;">
              <h1 style="margin: 0;">Task Due Today</h1>
            </div>
            <div style="padding: 20px; background-color: #fef3c7;">
              <p>Dear $employeeName,</p>
              <p><strong>Reminder:</strong> Your task is due today!</p>
              
              <div style="background-color: white; padding: 15px; border-radius: 8px; margin: 15px 0;">
                <h3 style="color: #F59E0B; margin-top: 0;">Task Details:</h3>
                <p><strong>Title:</strong> $taskTitle</p>
                <p><strong>Due Date:</strong> $dueDate</p>
              </div>
              
              <p>Please complete and submit your task today to avoid it becoming overdue.</p>
              <p>Log into the Talnio app to submit your task.</p>
              <p>Best regards,<br>Talnio</p>
            </div>
          </div>
        ''';

      await send(message, _smtpServer);
      print('Due date reminder email sent successfully to $employeeEmail');
      return true;
    } catch (e) {
      print('Error sending due date reminder email: $e');
      return false;
    }
  }

  // Send overdue task email
  static Future<bool> sendOverdueTaskEmail({
    required String employeeEmail,
    required String employeeName,
    required String taskTitle,
    required String dueDate,
    required int daysOverdue,
  }) async {
    try {
      final message = Message()
        ..from = Address(_fromEmail, _fromName)
        ..recipients.add(employeeEmail)
        ..subject = 'URGENT: Overdue Task - $taskTitle'
        ..html = '''
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background-color: #DC2626; color: white; padding: 20px; text-align: center;">
              <h1 style="margin: 0;">URGENT: Task Overdue</h1>
            </div>
            <div style="padding: 20px; background-color: #fee2e2;">
              <p>Dear $employeeName,</p>
              <p><strong>URGENT:</strong> Your task is now $daysOverdue day${daysOverdue > 1 ? 's' : ''} overdue!</p>
              
              <div style="background-color: white; padding: 15px; border-radius: 8px; margin: 15px 0;">
                <h3 style="color: #DC2626; margin-top: 0;">Task Details:</h3>
                <p><strong>Title:</strong> $taskTitle</p>
                <p><strong>Due Date:</strong> $dueDate</p>
                <p><strong>Days Overdue:</strong> $daysOverdue</p>
              </div>
              
              <p>Please submit your daily delay reason and complete this task as soon as possible.</p>
              <p>Log into the Talnio app immediately to provide an update.</p>
              <p>Best regards,<br>Talnio</p>
            </div>
          </div>
        ''';

      await send(message, _smtpServer);
      print('Overdue task email sent successfully to $employeeEmail');
      return true;
    } catch (e) {
      print('Error sending overdue task email: $e');
      return false;
    }
  }

  // Check and send due date notifications
  static Future<void> checkAndSendDueDateNotifications() async {
    try {
      final today = DateTime.now();
      final todayString = today.toIso8601String().split('T')[0];

      // Get all tasks due today that are not submitted
      final tasksQuery = await FirebaseFirestore.instance
          .collection('tasks')
          .where('dueDate', isEqualTo: todayString)
          .where('status', isEqualTo: 'assigned')
          .get();

      for (var taskDoc in tasksQuery.docs) {
        final taskData = taskDoc.data();
        final employeeId = taskData['assignedTo'];

        // Get employee details
        final employeeDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(employeeId)
            .get();

        if (employeeDoc.exists) {
          final employeeData = employeeDoc.data() as Map<String, dynamic>;
          final employeeEmail = employeeData['email'];
          final employeeName = employeeData['name'];

          if (employeeEmail != null && employeeName != null) {
            await sendDueDateReminderEmail(
              employeeEmail: employeeEmail,
              employeeName: employeeName,
              taskTitle: taskData['title'],
              dueDate: taskData['dueDate'],
            );
          }
        }
      }
    } catch (e) {
      print('Error checking due date notifications: $e');
    }
  }

  // Check and send overdue notifications
  static Future<void> checkAndSendOverdueNotifications() async {
    try {
      final today = DateTime.now();
      final todayString = today.toIso8601String().split('T')[0];

      // Get all overdue tasks that are not submitted
      final tasksQuery = await FirebaseFirestore.instance
          .collection('tasks')
          .where('status', isEqualTo: 'assigned')
          .get();

      for (var taskDoc in tasksQuery.docs) {
        final taskData = taskDoc.data();
        final dueDate = DateTime.parse(taskData['dueDate']);

        // Check if task is overdue
        if (today.isAfter(dueDate)) {
          final daysOverdue = today.difference(dueDate).inDays;
          final employeeId = taskData['assignedTo'];

          // Get employee details
          final employeeDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(employeeId)
              .get();

          if (employeeDoc.exists) {
            final employeeData = employeeDoc.data() as Map<String, dynamic>;
            final employeeEmail = employeeData['email'];
            final employeeName = employeeData['name'];

            if (employeeEmail != null && employeeName != null) {
              await sendOverdueTaskEmail(
                employeeEmail: employeeEmail,
                employeeName: employeeName,
                taskTitle: taskData['title'],
                dueDate: taskData['dueDate'],
                daysOverdue: daysOverdue,
              );
            }
          }
        }
      }
    } catch (e) {
      print('Error checking overdue notifications: $e');
    }
  }
}
