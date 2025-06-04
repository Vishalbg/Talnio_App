import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'auth_provider.dart';

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _messageController = TextEditingController();
  String? _selectedChatRoom;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    // Only show one tab for employees (just chat rooms)
    _tabController = TabController(
        length: authProvider.role == 'employee' ? 1 : 2,
        vsync: this
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String chatRoomId, String message) async {
    if (message.trim().isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final user = fa.FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() as Map<String, dynamic>;

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'senderId': user.uid,
        'senderName': userData['name'] ?? 'Unknown',
        'senderRole': userData['role'] ?? 'employee',
        'message': message.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'text',
      });

      // Update last message in chat room
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(chatRoomId)
          .update({
        'lastMessage': message.trim(),
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSender': userData['name'] ?? 'Unknown',
      });

      _messageController.clear();
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

  Widget _buildChatRoomsList() {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = fa.FirebaseAuth.instance.currentUser!;

    return StreamBuilder<QuerySnapshot>(
      stream: _getChatRoomsStream(authProvider.role!, currentUser.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading chat rooms: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                SizedBox(height: 16),
                Text(
                  'No chat rooms available',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  authProvider.role == 'employee'
                      ? 'Your manager will create team chat rooms'
                      : 'Create a team chat room to get started',
                  style: TextStyle(color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final chatRooms = snapshot.data!.docs;
        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: chatRooms.length,
          itemBuilder: (context, index) {
            final chatRoom = chatRooms[index];
            final data = chatRoom.data() as Map<String, dynamic>;
            return _buildChatRoomCard(chatRoom.id, data);
          },
        );
      },
    );
  }

  Widget _buildChatRoomCard(String chatRoomId, Map<String, dynamic> data) {
    final String name = data['name'] ?? 'Unknown Chat';
    final String? lastMessage = data['lastMessage'];
    final String? lastSender = data['lastMessageSender'];
    final Timestamp? lastMessageTime = data['lastMessageTime'];
    final List<dynamic> members = data['members'] ?? [];
    final String type = data['type'] ?? 'team';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: type == 'team' ? Colors.blue[100] : Colors.green[100],
          radius: 25,
          child: Icon(
            type == 'team' ? Icons.group : Icons.chat,
            color: type == 'team' ? Colors.blue[600] : Colors.green[600],
            size: 24,
          ),
        ),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text(
              '${members.length} members',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
            if (lastMessage != null) ...[
              SizedBox(height: 4),
              Text(
                '$lastSender: $lastMessage',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (lastMessageTime != null)
              Text(
                _formatTime(lastMessageTime.toDate()),
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            SizedBox(height: 4),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatRoomScreen(
                chatRoomId: chatRoomId,
                chatRoomName: name,
                chatRoomData: data,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCreateChatTab() {
    return CreateChatRoomWidget();
  }

  Stream<QuerySnapshot> _getChatRoomsStream(String userRole, String userId) {
    if (userRole == 'admin') {
      // Admins can see all chat rooms
      return FirebaseFirestore.instance
          .collection('chat_rooms')
          .orderBy('lastMessageTime', descending: true)
          .snapshots();
    } else {
      // Managers and employees see only rooms they're members of
      return FirebaseFirestore.instance
          .collection('chat_rooms')
          .where('members', arrayContains: userId)
          .orderBy('lastMessageTime', descending: true)
          .snapshots();
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return DateFormat('MMM dd').format(dateTime);
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Team Chat',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        bottom: authProvider.role == 'employee'
            ? null // No tabs for employees
            : TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Chat Rooms'),
            Tab(text: 'Create Room'),
          ],
          labelColor: Colors.blue[600],
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: Colors.blue[600],
        ),
      ),
      body: authProvider.role == 'employee'
          ? _buildChatRoomsList() // Only show chat rooms for employees
          : TabBarView(
        controller: _tabController,
        children: [
          _buildChatRoomsList(),
          _buildCreateChatTab(),
        ],
      ),
    );
  }
}

class CreateChatRoomWidget extends StatefulWidget {
  @override
  _CreateChatRoomWidgetState createState() => _CreateChatRoomWidgetState();
}

class _CreateChatRoomWidgetState extends State<CreateChatRoomWidget> {
  final TextEditingController _roomNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<String> _selectedMembers = [];
  List<DocumentSnapshot> _allUsers = [];
  List<DocumentSnapshot> _filteredUsers = [];
  bool _isLoading = false;
  bool _isExpanded = false;
  String _chatType = 'team';

  @override
  void dispose() {
    _roomNameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
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

  Future<void> _createChatRoom() async {
    if (_roomNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a room name')),
      );
      return;
    }

    if (_selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select at least one member')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final currentUser = fa.FirebaseAuth.instance.currentUser!;
      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final currentUserData = currentUserDoc.data() as Map<String, dynamic>;

      // Add current user to members list
      final allMembers = [..._selectedMembers, currentUser.uid];

      await FirebaseFirestore.instance.collection('chat_rooms').add({
        'name': _roomNameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'type': _chatType,
        'members': allMembers,
        'createdBy': currentUser.uid,
        'createdByName': currentUserData['name'] ?? 'Unknown',
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSender': null,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chat room created successfully!'),
          backgroundColor: Colors.green[600],
        ),
      );

      _roomNameController.clear();
      _descriptionController.clear();
      _searchController.clear();
      setState(() {
        _selectedMembers.clear();
        _isExpanded = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create chat room: $e'),
          backgroundColor: Colors.red[600],
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildMemberSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Members (${_selectedMembers.length} selected)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              icon: Icon(
                _isExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.blue[600],
              ),
              label: Text(
                _isExpanded ? 'Collapse' : 'Expand',
                style: TextStyle(color: Colors.blue[600]),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),

        // Search field
        if (_isExpanded) ...[
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search employees...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: _filterUsers,
          ),
          SizedBox(height: 12),
        ],

        // Selected members preview (when collapsed)
        if (!_isExpanded && _selectedMembers.isNotEmpty) ...[
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedMembers.take(3).map((memberId) {
                final user = _allUsers.firstWhere(
                      (user) => user.id == memberId,
                  orElse: () => _allUsers.first,
                );
                final userData = user.data() as Map<String, dynamic>;
                final userName = userData['name'] ?? 'Unknown';

                return Chip(
                  label: Text(userName),
                  deleteIcon: Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      _selectedMembers.remove(memberId);
                    });
                  },
                  backgroundColor: Colors.blue[100],
                );
              }).toList()
                ..addAll(_selectedMembers.length > 3
                    ? [Chip(
                  label: Text('+${_selectedMembers.length - 3} more'),
                  backgroundColor: Colors.grey[200],
                )]
                    : []),
            ),
          ),
          SizedBox(height: 8),
        ],

        // Full member list (when expanded)
        if (_isExpanded) ...[
          Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _filteredUsers.isEmpty
                ? Center(
              child: Text(
                _searchController.text.isNotEmpty
                    ? 'No employees found'
                    : 'No employees available to add',
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
                : ListView.builder(
              itemCount: _filteredUsers.length,
              itemBuilder: (context, index) {
                final user = _filteredUsers[index];
                final userData = user.data() as Map<String, dynamic>;
                final userId = user.id;
                final userName = userData['name'] ?? 'Unknown';
                final userRole = userData['role'] ?? 'employee';

                return CheckboxListTile(
                  title: Text(userName),
                  subtitle: Text(userRole.toUpperCase()),
                  value: _selectedMembers.contains(userId),
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedMembers.add(userId);
                      } else {
                        _selectedMembers.remove(userId);
                      }
                    });
                  },
                  secondary: CircleAvatar(
                    backgroundColor: Colors.blue[100],
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                      style: TextStyle(color: Colors.blue[600]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;

    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[600]!, Colors.blue[400]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.add_comment, color: Colors.white, size: 32),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create Chat Room',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Start a new conversation with your team',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24),
          TextField(
            controller: _roomNameController,
            decoration: InputDecoration(
              labelText: 'Room Name *',
              hintText: 'Enter chat room name',
              prefixIcon: Icon(Icons.chat_bubble_outline),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: 'Description (Optional)',
              hintText: 'Describe the purpose of this chat room',
              prefixIcon: Icon(Icons.description),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            maxLines: 3,
          ),
          SizedBox(height: 16),
          Text(
            'Chat Type',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  title: Text('Team Chat'),
                  subtitle: Text('For team discussions'),
                  value: 'team',
                  groupValue: _chatType,
                  onChanged: (value) {
                    setState(() => _chatType = value!);
                  },
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  title: Text('Project Chat'),
                  subtitle: Text('For project updates'),
                  value: 'project',
                  groupValue: _chatType,
                  onChanged: (value) {
                    setState(() => _chatType = value!);
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 16),

          // Enhanced member selector
          StreamBuilder<QuerySnapshot>(
            stream: _getAvailableUsersStream(authProvider.role!, currentUserId!),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(child: CircularProgressIndicator());
              }

              _allUsers = snapshot.data!.docs;
              if (_filteredUsers.isEmpty && _searchController.text.isEmpty) {
                _filteredUsers = _allUsers;
              }

              return _buildMemberSelector();
            },
          ),

          SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _createChatRoom,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Creating...'),
                ],
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_comment, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Create Chat Room',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Stream<QuerySnapshot> _getAvailableUsersStream(String userRole, String currentUserId) {
    if (userRole == 'admin') {
      // Admins can add anyone except themselves
      return FirebaseFirestore.instance
          .collection('users')
          .where('uid', isNotEqualTo: currentUserId)
          .snapshots();
    } else if (userRole == 'manager') {
      // Managers can add their employees
      return FirebaseFirestore.instance
          .collection('users')
          .where('managerId', isEqualTo: currentUserId)
          .snapshots();
    } else {
      // Employees can't create rooms, but this shouldn't be called
      return Stream.empty();
    }
  }
}

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

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final user = fa.FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() as Map<String, dynamic>;

      await FirebaseFirestore.instance
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
      });

      // Update last message in chat room
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

  Widget _buildMessage(Map<String, dynamic> messageData, bool isMe) {
    final String message = messageData['message'] ?? '';
    final String senderName = messageData['senderName'] ?? 'Unknown';
    final String senderRole = messageData['senderRole'] ?? 'employee';
    final Timestamp? timestamp = messageData['timestamp'];

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
                  Text(
                    timestamp != null
                        ? DateFormat('HH:mm').format(timestamp.toDate())
                        : 'Sending...',
                    style: TextStyle(
                      color: isMe ? Colors.white70 : Colors.grey[600],
                      fontSize: 10,
                    ),
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

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
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
                color: Colors.blue[600],
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
        chatRoomData: widget.chatRoomData,
        chatRoomId: widget.chatRoomId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.chatRoomName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${(widget.chatRoomData['members'] as List?)?.length ?? 0} members',
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
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading messages: ${snapshot.error}'),
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
                          'Start the conversation!',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                final messages = snapshot.data!.docs;

                // Auto-scroll to bottom when new messages arrive
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final messageData = message.data() as Map<String, dynamic>;
                    final isMe = messageData['senderId'] == currentUserId;

                    return _buildMessage(messageData, isMe);
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }
}

class ChatInfoBottomSheet extends StatefulWidget {
  final Map<String, dynamic> chatRoomData;
  final String chatRoomId;

  const ChatInfoBottomSheet({
    Key? key,
    required this.chatRoomData,
    required this.chatRoomId,
  }) : super(key: key);

  @override
  _ChatInfoBottomSheetState createState() => _ChatInfoBottomSheetState();
}

class _ChatInfoBottomSheetState extends State<ChatInfoBottomSheet> {
  bool _isEditing = false;
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _searchController;
  List<String> _selectedMembers = [];
  List<DocumentSnapshot> _allUsers = [];
  List<DocumentSnapshot> _filteredUsers = [];
  bool _isExpanded = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.chatRoomData['name'] ?? '');
    _descriptionController = TextEditingController(text: widget.chatRoomData['description'] ?? '');
    _searchController = TextEditingController();
    _selectedMembers = List<String>.from(widget.chatRoomData['members'] ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _canEdit() {
    final currentUserId = fa.FirebaseAuth.instance.currentUser?.uid;
    return currentUserId == widget.chatRoomData['createdBy'] || _isAdmin();
  }

  bool _isAdmin() {
    // You'll need to check the current user's role
    // This is a simplified check - implement based on your auth system
    return false; // Replace with actual admin check
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

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .update({
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'members': _selectedMembers,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chat room updated successfully!'),
          backgroundColor: Colors.green[600],
        ),
      );

      setState(() => _isEditing = false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update chat room: $e'),
          backgroundColor: Colors.red[600],
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildMemberSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Members (${_selectedMembers.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            if (_isEditing) ...[
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                icon: Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.blue[600],
                ),
                label: Text(
                  _isExpanded ? 'Collapse' : 'Edit Members',
                  style: TextStyle(color: Colors.blue[600]),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 12),

        // Search field (when editing and expanded)
        if (_isEditing && _isExpanded) ...[
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search employees...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: _filterUsers,
          ),
          SizedBox(height: 12),
        ],

        // Member list
        if (_isEditing && _isExpanded) ...[
          Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _filteredUsers.isEmpty
                ? Center(
              child: Text(
                _searchController.text.isNotEmpty
                    ? 'No employees found'
                    : 'Loading employees...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
                : ListView.builder(
              itemCount: _filteredUsers.length,
              itemBuilder: (context, index) {
                final user = _filteredUsers[index];
                final userData = user.data() as Map<String, dynamic>;
                final userId = user.id;
                final userName = userData['name'] ?? 'Unknown';
                final userRole = userData['role'] ?? 'employee';

                return CheckboxListTile(
                  title: Text(userName),
                  subtitle: Text(userRole.toUpperCase()),
                  value: _selectedMembers.contains(userId),
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedMembers.add(userId);
                      } else {
                        _selectedMembers.remove(userId);
                      }
                    });
                  },
                  secondary: CircleAvatar(
                    backgroundColor: Colors.blue[100],
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                      style: TextStyle(color: Colors.blue[600]),
                    ),
                  ),
                );
              },
            ),
          ),
        ] else ...[
          // Display current members
          ...widget.chatRoomData['members'].map((memberId) {
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(memberId)
                  .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return ListTile(
                    leading: CircularProgressIndicator(),
                    title: Text('Loading...'),
                  );
                }

                final userData = snapshot.data!.data() as Map<String, dynamic>?;
                final userName = userData?['name'] ?? 'Unknown User';
                final userRole = userData?['role'] ?? 'employee';

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

                return ListTile(
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
                  title: Text(userName),
                  subtitle: Text(userRole.toUpperCase()),
                  trailing: Container(
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
                );
              },
            );
          }).toList(),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String description = widget.chatRoomData['description'] ?? '';
    final String type = widget.chatRoomData['type'] ?? 'team';
    final String createdByName = widget.chatRoomData['createdByName'] ?? 'Unknown';

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
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: type == 'team' ? Colors.blue[100] : Colors.green[100],
                        radius: 30,
                        child: Icon(
                          type == 'team' ? Icons.group : Icons.chat,
                          color: type == 'team' ? Colors.blue[600] : Colors.green[600],
                          size: 30,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _isEditing
                                ? TextField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'Room Name',
                                border: OutlineInputBorder(),
                              ),
                            )
                                : Text(
                              widget.chatRoomData['name'] ?? 'Unknown Chat',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '${type.toUpperCase()} CHAT',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
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
                      if (_canEdit()) ...[
                        IconButton(
                          icon: Icon(_isEditing ? Icons.close : Icons.edit),
                          onPressed: () {
                            setState(() {
                              _isEditing = !_isEditing;
                              if (!_isEditing) {
                                // Reset changes
                                _nameController.text = widget.chatRoomData['name'] ?? '';
                                _descriptionController.text = widget.chatRoomData['description'] ?? '';
                                _selectedMembers = List<String>.from(widget.chatRoomData['members'] ?? []);
                              }
                            });
                          },
                        ),
                      ],
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
                  _isEditing
                      ? TextField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      hintText: 'Enter description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  )
                      : Container(
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

                  // Members section with editing capability
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        _allUsers = snapshot.data!.docs;
                        if (_filteredUsers.isEmpty && _searchController.text.isEmpty) {
                          _filteredUsers = _allUsers;
                        }
                      }
                      return _buildMemberSelector();
                    },
                  ),

                  if (_isEditing) ...[
                    SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _saveChanges,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[600],
                              foregroundColor: Colors.white,
                            ),
                            child: _isLoading
                                ? CircularProgressIndicator(color: Colors.white)
                                : Text('Save Changes'),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _isEditing = false;
                                _nameController.text = widget.chatRoomData['name'] ?? '';
                                _descriptionController.text = widget.chatRoomData['description'] ?? '';
                                _selectedMembers = List<String>.from(widget.chatRoomData['members'] ?? []);
                              });
                            },
                            child: Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
