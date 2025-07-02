import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'auth_provider.dart';
import 'chat_room_screen.dart';

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  StreamSubscription? _chatRoomsSubscription;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _tabController = TabController(
        length: authProvider.role == 'manager' ? 2 : 1,
        vsync: this
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatRoomsSubscription?.cancel();
    super.dispose();
  }

  Widget _buildChatRoomsList() {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = fa.FirebaseAuth.instance.currentUser;

    // Handle signed out user
    if (currentUser == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              'Please sign in to view chats',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _getChatRoomsStream(authProvider.role!, currentUser.uid),
      builder: (context, snapshot) {
        // Remove loading indicator to prevent keyboard issues
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                SizedBox(height: 16),
                Text(
                  'Error loading chat rooms',
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
                      : authProvider.role == 'admin'
                      ? 'Monitor team communications here'
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
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
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
        child: Container(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue[400]!, Colors.blue[600]!], // Always blue since all are team chats now
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Icon(
                  Icons.group, // Always group icon since all are team chats now
                  color: Colors.white,
                  size: 24,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
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
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (lastMessageTime != null)
                    Text(
                      _formatTime(lastMessageTime.toDate()),
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  SizedBox(height: 8),
                  Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateChatTab() {
    return CreateChatRoomWidget();
  }

  Stream<QuerySnapshot>? _getChatRoomsStream(String userRole, String userId) {
    try {
      if (userRole == 'admin') {
        return FirebaseFirestore.instance
            .collection('chat_rooms')
            .orderBy('lastMessageTime', descending: true)
            .snapshots();
      } else {
        return FirebaseFirestore.instance
            .collection('chat_rooms')
            .where('members', arrayContains: userId)
            .orderBy('lastMessageTime', descending: true)
            .snapshots();
      }
    } catch (e) {
      print('Error creating chat rooms stream: $e');
      return null;
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
        title: Row(
          children: [
            Text(
              'Team Chat',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            if (authProvider.role == 'admin') ...[
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'ADMIN VIEW',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[600],
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        bottom: authProvider.role == 'manager'
            ? TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Chat Rooms'),
            Tab(text: 'Create Room'),
          ],
          labelColor: Colors.blue[600],
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: Colors.blue[600],
        )
            : null,
      ),
      body: authProvider.role == 'manager'
          ? TabBarView(
        controller: _tabController,
        children: [
          _buildChatRoomsList(),
          _buildCreateChatTab(),
        ],
      )
          : _buildChatRoomsList(),
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
  // Removed: String _chatType = 'team';

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

      final allMembers = [..._selectedMembers, currentUser.uid];

      await FirebaseFirestore.instance.collection('chat_rooms').add({
        'name': _roomNameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'type': 'team', // Always set to 'team' - removed chat type selection
        'members': allMembers,
        'createdBy': currentUser.uid,
        'createdByName': currentUserData['name'] ?? 'Unknown',
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSender': null,
        'typingUsers': [],
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
                  orElse: () => _allUsers.isNotEmpty ? _allUsers.first : throw StateError('No users available'),
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
                        'Create Team Chat Room',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Start a new team conversation',
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
          // Removed: Chat Type selection section

          StreamBuilder<QuerySnapshot>(
            stream: _getAvailableUsersStream(authProvider.role!, currentUserId!),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Loading users...', style: TextStyle(color: Colors.grey[600])),
                  ),
                );
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
                    'Create Team Chat Room',
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

  Stream<QuerySnapshot>? _getAvailableUsersStream(String userRole, String currentUserId) {
    try {
      if (userRole == 'admin') {
        return FirebaseFirestore.instance
            .collection('users')
            .where('uid', isNotEqualTo: currentUserId)
            .snapshots();
      } else if (userRole == 'manager') {
        return FirebaseFirestore.instance
            .collection('users')
            .where('managerId', isEqualTo: currentUserId)
            .snapshots();
      } else {
        return Stream.empty();
      }
    } catch (e) {
      print('Error creating users stream: $e');
      return null;
    }
  }
}