import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CEORegistrationCenterScreen extends StatefulWidget {
  const CEORegistrationCenterScreen({super.key});
  @override
  State<CEORegistrationCenterScreen> createState() => _CEORegistrationCenterScreenState();
}

class _CEORegistrationCenterScreenState extends State<CEORegistrationCenterScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  // Firestore collections - SAME as registration files use
  Stream<QuerySnapshot> _stream(String col) {
    return FirebaseFirestore.instance.collection(col).snapshots();
  }

  Future<void> _approve(String fromCol, String toCol, DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    data['status'] = 'approved';
    data['isApproved'] = true;
    data['approved'] = true;
    data['approvedAt'] = FieldValue.serverTimestamp();
    await FirebaseFirestore.instance.collection(toCol).doc(doc.id).set(data, SetOptions(merge: true));
    await FirebaseFirestore.instance.collection(fromCol).doc(doc.id).delete();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Approved! Nurse can now login.')));
  }

  Future<void> _reject(String col, DocumentSnapshot doc) async {
    await FirebaseFirestore.instance.collection(col).doc(doc.id).delete();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rejected and deleted.')));
  }

  Widget _list(String col, {bool isPending = true, String? approveTo}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stream(col),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(30), child: Text('No records', style: TextStyle(color: Colors.grey))));
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i];
            final m = d.data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: (m['photoUrl'] != null && (m['photoUrl'] as String).isNotEmpty) ? NetworkImage(m['photoUrl']) : null,
                  child: (m['photoUrl'] == null) ? Text((m['name'] ?? '?').toString().substring(0, 1).toUpperCase()) : null,
                ),
                title: Text(m['name'] ?? m['username'] ?? 'No name'),
                subtitle: Text('${m['email'] ?? ''}\n${m['phone'] ?? ''} • ${m['status'] ?? ''}'),
                isThreeLine: true,
                trailing: isPending ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => _approve(col, approveTo!, d)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => _reject(col, d)),
                  ],
                ) : IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _reject(col, d)),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CEO Registration Center'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          tabs: const [
            Tab(text: 'Nurses Pending'),
            Tab(text: 'Nurses Approved'),
            Tab(text: 'Clients Pending'),
            Tab(text: 'Clients Approved'),
            Tab(text: 'ALL'),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() {}))],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _list('pending_nurses', isPending: true, approveTo: 'nurses'),
          _list('nurses', isPending: false),
          _list('pending_clients', isPending: true, approveTo: 'clients'),
          _list('clients', isPending: false),
          // ALL = show pending nurses + pending clients together
          StreamBuilder<QuerySnapshot>(
            stream: _stream('pending_nurses'),
            builder: (context, snapN) {
              return StreamBuilder<QuerySnapshot>(
                stream: _stream('pending_clients'),
                builder: (context, snapC) {
                  final n = snapN.data?.docs.length ?? 0;
                  final c = snapC.data?.docs.length ?? 0;
                  return Center(child: Text('Pending Nurses: $n\nPending Clients: $c', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)));
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
