import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'auth_provider.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatRoomId;
  final String chatRoomName;
  final Map<String, dynamic> chatRoomData;

  const ChatRoomScreen({
    Key? key,
    required this.chatRoomId,
    required this.chatRoomName,
    required this.chatRoomData,
  }) : super(key: key);

  @override
  _ChatRoomScreenState createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  Timer? _typingTimer;
  bool _isTyping = false;
  String? _currentUserRole;
  String? _currentUserId;
  List<String> _typingUsers = [];
  StreamSubscription? _typingSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _getCurrentUserInfo();
    _messageController.addListener(_onTypingChanged);
    _listenToTypingIndicators();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.removeListener(_onTypingChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _typingSubscription?.cancel();
    _stopTyping();
    super.dispose();
  }

  Future<void> _getCurrentUserInfo() async {
    final user = fa.FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final userData = userDoc.data() as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _currentUserRole = userData?['role'];
            _currentUserId = user.uid;
          });
        }
      } catch (e) {
        print('Error getting user info: $e');
      }
    }
  }

  void _listenToTypingIndicators() {
    _typingSubscription = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.chatRoomId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data() as Map<String, dynamic>;
        final typingUsers = List<String>.from(data['typingUsers'] ?? []);
        typingUsers.remove(_currentUserId);
        setState(() {
          _typingUsers = typingUsers;
        });
      }
    }, onError: (e) {
      print('Error listening to typing indicators: $e');
    });
  }

  void _onTypingChanged() {
    if (_currentUserRole == 'admin') return;

    if (_messageController.text.isNotEmpty && !_isTyping) {
      _startTyping();
    } else if (_messageController.text.isEmpty && _isTyping) {
      _stopTyping();
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(Duration(seconds: 2), () {
      _stopTyping();
    });
  }

  Future<void> _startTyping() async {
    if (_currentUserId == null || _currentUserRole == 'admin') return;

    setState(() => _isTyping = true);

    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .update({
        'typingUsers': FieldValue.arrayUnion([_currentUserId])
      });
    } catch (e) {
      print('Error updating typing status: $e');
    }
  }

  Future<void> _stopTyping() async {
    if (_currentUserId == null || !_isTyping) return;

    setState(() => _isTyping = false);

    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .update({
        'typingUsers': FieldValue.arrayRemove([_currentUserId])
      });
    } catch (e) {
      print('Error updating typing status: $e');
    }
  }

  Future<void> _markMessageAsRead(String messageId, String senderId) async {
    if (_currentUserId == null || _currentUserId == senderId) return;

    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .collection('messages')
          .doc(messageId)
          .update({
        'readBy': FieldValue.arrayUnion([_currentUserId]),
        'status': 'read',
      });
    } catch (e) {
      print('Error marking message as read: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_currentUserRole == 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Admins can only view messages'),
          backgroundColor: Colors.orange[600],
        ),
      );
      return;
    }

    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    _stopTyping();

    setState(() => _isLoading = true);
    try {
      final user = fa.FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() as Map<String, dynamic>;

      final messageRef = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .collection('messages')
          .add({
        'senderId': user.uid,
        'senderName': userData['name'] ?? 'Unknown',
        'senderRole': userData['role'] ?? 'employee',
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'text',
        'status': 'sent',
        'readBy': [user.uid],
        'deliveredTo': [user.uid],
      });

      Future.delayed(Duration(milliseconds: 500), () async {
        try {
          await messageRef.update({'status': 'delivered'});
        } catch (e) {
          print('Error updating message status: $e');
        }
      });

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .update({
        'lastMessage': message,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSender': userData['name'] ?? 'Unknown',
      });

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red[600],
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildMessageStatus(Map<String, dynamic> messageData, bool isMe) {
    if (!isMe) return SizedBox.shrink();

    final String status = messageData['status'] ?? 'sent';
    final List<dynamic> readBy = messageData['readBy'] ?? [];
    final List<dynamic> deliveredTo = messageData['deliveredTo'] ?? [];

    IconData icon;
    Color color;

    if (readBy.length > 1) {
      icon = Icons.done_all;
      color = Colors.blue[600]!;
    } else if (deliveredTo.length > 1) {
      icon = Icons.done_all;
      color = Colors.grey[600]!;
    } else if (status == 'delivered') {
      icon = Icons.done_all;
      color = Colors.grey[600]!;
    } else {
      icon = Icons.done;
      color = Colors.grey[600]!;
    }

    return Icon(icon, size: 12, color: color);
  }

  Widget _buildMessage(DocumentSnapshot messageDoc, bool isMe) {
    final messageData = messageDoc.data() as Map<String, dynamic>;
    final String message = messageData['message'] ?? '';
    final String senderName = messageData['senderName'] ?? 'Unknown';
    final String senderRole = messageData['senderRole'] ?? 'employee';
    final Timestamp? timestamp = messageData['timestamp'];
    final String senderId = messageData['senderId'] ?? '';

    if (!isMe && _currentUserId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _markMessageAsRead(messageDoc.id, senderId);
      });
    }

    Color roleColor;
    switch (senderRole) {
      case 'admin':
        roleColor = Colors.red[600]!;
        break;
      case 'manager':
        roleColor = Colors.orange[600]!;
        break;
      default:
        roleColor = Colors.blue[600]!;
    }

    return Container(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: roleColor.withOpacity(0.1),
              child: Text(
                senderName.isNotEmpty ? senderName[0].toUpperCase() : 'U',
                style: TextStyle(
                  color: roleColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue[600] : Colors.grey[200],
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe) ...[
                    Row(
                      children: [
                        Text(
                          senderName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: roleColor,
                          ),
                        ),
                        SizedBox(width: 4),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: roleColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            senderRole.toUpperCase(),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: roleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                  ],
                  Text(
                    message,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timestamp != null
                            ? DateFormat('HH:mm').format(timestamp.toDate())
                            : 'Sending...',
                        style: TextStyle(
                          color: isMe ? Colors.white70 : Colors.grey[600],
                          fontSize: 10,
                        ),
                      ),
                      if (isMe) ...[
                        SizedBox(width: 4),
                        _buildMessageStatus(messageData, isMe),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue[100],
              child: Icon(
                Icons.person,
                color: Colors.blue[600],
                size: 16,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    if (_typingUsers.isEmpty) return SizedBox.shrink();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildTypingDot(0),
                      _buildTypingDot(1),
                      _buildTypingDot(2),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  _typingUsers.length == 1
                      ? 'Someone is typing...'
                      : '${_typingUsers.length} people are typing...',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDot(int index) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey[600],
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildMessageInput() {
    if (_currentUserRole == 'admin') {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border(
            top: BorderSide(color: Colors.grey[300]!),
          ),
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.visibility, color: Colors.grey[600]),
              SizedBox(width: 8),
              Text(
                'Admin View - Read Only',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[600]!, Colors.blue[400]!],
                ),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _isLoading
                    ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : Icon(Icons.send, color: Colors.white),
                onPressed: _isLoading ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChatInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChatInfoBottomSheet(
        chatRoomId: widget.chatRoomId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .snapshots(),
      builder: (context, chatRoomSnapshot) {
        if (!chatRoomSnapshot.hasData) {
          return Scaffold(
            backgroundColor: Colors.grey[50],
            appBar: AppBar(
              title: Text('Loading...'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 1,
            ),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final chatRoomData = chatRoomSnapshot.data!.data() as Map<String, dynamic>?;
        if (chatRoomData == null) {
          return Scaffold(
            backgroundColor: Colors.grey[50],
            appBar: AppBar(
              title: Text('Chat Not Found'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 1,
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                  SizedBox(height: 16),
                  Text('Chat room not found or has been deleted'),
                ],
              ),
            ),
          );
        }

        final chatRoomName = chatRoomData['name'] ?? 'Unknown Chat';
        final members = chatRoomData['members'] as List? ?? [];

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      chatRoomName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_currentUserRole == 'admin') ...[
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'READ ONLY',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[600],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${members.length} members',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 1,
            actions: [
              IconButton(
                icon: Icon(Icons.info_outline),
                onPressed: _showChatInfo,
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chat_rooms')
                      .doc(widget.chatRoomId)
                      .collection('messages')
                      .orderBy('timestamp', descending: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                            SizedBox(height: 16),
                            Text(
                              'Error loading messages',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                            ),
                            SizedBox(height: 8),
                            Text('Please try again later', style: TextStyle(color: Colors.grey[600])),
                          ],
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              _currentUserRole == 'admin'
                                  ? 'Monitoring team communications'
                                  : 'Start the conversation!',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      );
                    }

                    final messages = snapshot.data!.docs;

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });

                    return Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              final messageData = message.data() as Map<String, dynamic>;
                              final isMe = messageData['senderId'] == _currentUserId;

                              return _buildMessage(message, isMe);
                            },
                          ),
                        ),
                        _buildTypingIndicator(),
                      ],
                    );
                  },
                ),
              ),
              _buildMessageInput(),
            ],
          ),
        );
      },
    );
  }
}

class ChatInfoBottomSheet extends StatefulWidget {
  final String chatRoomId;

  const ChatInfoBottomSheet({
    Key? key,
    required this.chatRoomId,
  }) : super(key: key);

  @override
  _ChatInfoBottomSheetState createState() => _ChatInfoBottomSheetState();
}

class _ChatInfoBottomSheetState extends State<ChatInfoBottomSheet> {
  late TextEditingController _searchController;
  List<DocumentSnapshot> _allUsers = [];
  List<DocumentSnapshot> _filteredUsers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _canManage() {
    final currentUserRole = Provider.of<AuthProvider>(context, listen: false).role;
    return currentUserRole == 'manager' || currentUserRole == 'admin';
  }

  Future<void> _loadAllUsers() async {
    if (!_canManage()) return;

    try {
      final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;
      final currentUserRole = Provider.of<AuthProvider>(context, listen: false).role;

      QuerySnapshot snapshot;
      if (currentUserRole == 'admin') {
        snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('uid', isNotEqualTo: currentUserId)
            .get();
      } else {
        snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('managerId', isEqualTo: currentUserId)
            .get();
      }

      setState(() {
        _allUsers = snapshot.docs;
        _filteredUsers = _allUsers;
      });
    } catch (e) {
      print('Error loading users: $e');
    }
  }

  Future<void> _addMember(String userId, List<String> currentMembers) async {
    if (!_canManage()) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .update({
        'members': FieldValue.arrayUnion([userId])
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Member added successfully!'),
          backgroundColor: Colors.green[600],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add member: $e'),
          backgroundColor: Colors.red[600],
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeMember(String userId, String createdBy) async {
    if (!_canManage()) return;

    // Prevent removing the creator
    if (userId == createdBy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot remove chat room creator'),
          backgroundColor: Colors.orange[600],
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .update({
        'members': FieldValue.arrayRemove([userId])
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Member removed successfully!'),
          backgroundColor: Colors.green[600],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove member: $e'),
          backgroundColor: Colors.red[600],
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteChatRoom() async {
    if (!_canManage()) return;

    // Show confirmation dialog
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Chat Room'),
        content: Text('Are you sure you want to delete this chat room? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      // Delete all messages in the chat room
      final messagesSnapshot = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .collection('messages')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in messagesSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // Delete the chat room itself
      batch.delete(FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId));

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chat room deleted successfully!'),
          backgroundColor: Colors.green[600],
        ),
      );

      // Navigate back to chat list
      Navigator.of(context).popUntil((route) => route.isFirst);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete chat room: $e'),
          backgroundColor: Colors.red[600],
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showAddMemberDialog(List<String> currentMembers) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add Members'),
          content: Container(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search employees...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (query) {
                    setDialogState(() {
                      _filterUsers(query);
                    });
                  },
                ),
                SizedBox(height: 16),
                Expanded(
                  child: _filteredUsers.isEmpty
                      ? Center(child: Text('No employees found'))
                      : ListView.builder(
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      final userData = user.data() as Map<String, dynamic>;
                      final userId = user.id;
                      final userName = userData['name'] ?? 'Unknown';
                      final userRole = userData['role'] ?? 'employee';
                      final isAlreadyMember = currentMembers.contains(userId);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[100],
                          child: Text(
                            userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                            style: TextStyle(color: Colors.blue[600]),
                          ),
                        ),
                        title: Text(userName),
                        subtitle: Text(userRole.toUpperCase()),
                        trailing: isAlreadyMember
                            ? Icon(Icons.check, color: Colors.green)
                            : IconButton(
                          icon: Icon(Icons.add, color: Colors.blue),
                          onPressed: () {
                            _addMember(userId, currentMembers);
                            Navigator.of(context).pop();
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = _allUsers;
      } else {
        _filteredUsers = _allUsers.where((user) {
          final userData = user.data() as Map<String, dynamic>;
          final userName = userData['name']?.toString().toLowerCase() ?? '';
          final userRole = userData['role']?.toString().toLowerCase() ?? '';
          return userName.contains(query.toLowerCase()) ||
              userRole.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Widget _buildMembersList(List<dynamic> members, String createdBy) {
    final bool canManage = _canManage();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Members (${members.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            if (canManage)
              IconButton(
                onPressed: () {
                  _loadAllUsers().then((_) => _showAddMemberDialog(List<String>.from(members)));
                },
                icon: Icon(Icons.person_add, color: Colors.blue[600]),
                tooltip: 'Add Member',
              ),
          ],
        ),
        SizedBox(height: 12),
        ...members.map((memberId) {
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(memberId)
                .get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.grey[300],
                        radius: 20,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 16,
                              width: 100,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            SizedBox(height: 4),
                            Container(
                              height: 12,
                              width: 60,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (snapshot.hasError || !snapshot.hasData) {
                return Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.red[100],
                        child: Icon(Icons.error, color: Colors.red[600]),
                        radius: 20,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Error loading user',
                        style: TextStyle(color: Colors.red[600]),
                      ),
                    ],
                  ),
                );
              }

              final userData = snapshot.data!.data() as Map<String, dynamic>?;
              final userName = userData?['name'] ?? 'Unknown User';
              final userRole = userData?['role'] ?? 'employee';
              final isCreator = memberId == createdBy;

              Color roleColor;
              switch (userRole) {
                case 'admin':
                  roleColor = Colors.red[600]!;
                  break;
                case 'manager':
                  roleColor = Colors.orange[600]!;
                  break;
                default:
                  roleColor = Colors.blue[600]!;
              }

              return Container(
                margin: EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: roleColor.withOpacity(0.1),
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                      style: TextStyle(
                        color: roleColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        userName,
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (isCreator) ...[
                        SizedBox(width: 8),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'CREATOR',
                            style: TextStyle(
                              color: Colors.amber[800],
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(userRole.toUpperCase()),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          userRole.toUpperCase(),
                          style: TextStyle(
                            color: roleColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (canManage && !isCreator) ...[
                        SizedBox(width: 8),
                        IconButton(
                          onPressed: () => _removeMember(memberId, createdBy),
                          icon: Icon(Icons.remove_circle, color: Colors.red[600]),
                          tooltip: 'Remove Member',
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        }).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final chatRoomData = snapshot.data!.data() as Map<String, dynamic>?;
        if (chatRoomData == null) {
          return Container(
            height: 200,
            child: Center(child: Text('Chat room not found')),
          );
        }

        final String description = chatRoomData['description'] ?? '';
        final String type = chatRoomData['type'] ?? 'team';
        final String createdByName = chatRoomData['createdByName'] ?? 'Unknown';
        final String createdBy = chatRoomData['createdBy'] ?? '';
        final List<dynamic> members = chatRoomData['members'] ?? [];
        final bool canManage = _canManage();

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (canManage)
                Padding(
                  padding: EdgeInsets.only(right: 16, top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: _isLoading ? null : _deleteChatRoom,
                        icon: Icon(Icons.delete, color: Colors.red[600]),
                        tooltip: 'Delete Chat Room',
                      ),
                    ],
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: type == 'team'
                                    ? [Colors.blue[400]!, Colors.blue[600]!]
                                    : [Colors.green[400]!, Colors.green[600]!],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Icon(
                              type == 'team' ? Icons.group : Icons.chat,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  chatRoomData['name'] ?? 'Unknown Chat',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: type == 'team' ? Colors.blue[100] : Colors.green[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${type.toUpperCase()} CHAT',
                                    style: TextStyle(
                                      color: type == 'team' ? Colors.blue[600] : Colors.green[600],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Created by $createdByName',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          description.isEmpty ? 'No description' : description,
                          style: TextStyle(
                            color: description.isEmpty ? Colors.grey[500] : Colors.grey[700],
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      _buildMembersList(members, createdBy),
                      if (_isLoading) ...[
                        SizedBox(height: 20),
                        Center(
                          child: CircularProgressIndicator(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}