import 'dart:convert';
import 'package:http/http.dart' as http;

// SAME Firebase as your HTML file - no change
const String firebaseDbUrl = 'https://web-care-618e8-default-rtdb.firebaseio.com';

class CeoAnnouncement {
  final String id;
  final String text;
  final String senderName;
  final String textColor;
  final String bgColor;
  final String displayType;
  final String speed;
  final String videoUrl;
  final String imageUrl;
  final int createdAt;
  CeoAnnouncement({required this.id, required this.text, required this.senderName, this.textColor = '#FFFFFF', this.bgColor = '#191531', this.displayType = 'marquee_slow', this.speed = 'slow', this.videoUrl = '', this.imageUrl = '', required this.createdAt});
  factory CeoAnnouncement.fromJson(String id, Map<String, dynamic> j) {
    return CeoAnnouncement(
      id: id,
      text: (j['text'] ?? '').toString(),
      senderName: (j['senderName'] ?? 'Asabere Peter - CEO').toString(),
      textColor: (j['textColor'] ?? '#FFFFFF').toString(),
      bgColor: (j['bgColor'] ?? '#191531').toString(),
      displayType: (j['displayType'] ?? 'marquee_slow').toString(),
      speed: (j['speed'] ?? 'slow').toString(),
      videoUrl: (j['videoUrl'] ?? '').toString(),
      imageUrl: (j['imageUrl'] ?? '').toString(),
      createdAt: (j['createdAt'] is int) ? j['createdAt'] as int : 0,
    );
  }
}

class CeoService {
  // GET current Home Banner - Index go call this every 10 sec
  static Future<CeoAnnouncement?> getCurrentHomeBanner() async {
    try {
      final res = await http.get(Uri.parse('$firebaseDbUrl/ceoHomePageCurrent.json'));
      if (res.statusCode != 200 || res.body == 'null') return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return CeoAnnouncement.fromJson('current', j);
    } catch (e) { return null; }
  }

  // GET Nurses messages
  static Future<List<CeoAnnouncement>> getNursesMessages() async {
    try {
      final res = await http.get(Uri.parse('$firebaseDbUrl/nurses_group_chat/messages.json'));
      if (res.statusCode != 200 || res.body == 'null') return [];
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final list = j.entries.map((e) => CeoAnnouncement.fromJson(e.key, Map<String, dynamic>.from(e.value))).toList();
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    } catch (e) { return []; }
  }

  // SEND to Nurses OR Home - same as your HTML send()
  static Future<bool> send({required String dest, required String text, String textColor = '#FFFFFF', String bgColor = '#191531', String displayType = 'marquee_slow', String speed = 'slow', String videoUrl = '', String imageUrl = ''}) async {
    final id = 'MSG-${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final base = {'messageId': id, 'senderId': 'CEO_ASABERE', 'senderName': 'Asabere Peter - CEO', 'senderPhoto': 'https://ui-avatars.com/api/?name=Asabere+Peter&background=facc15&color=000', 'text': text, 'createdAt': now, 'isCEO': true, 'videoUrl': videoUrl, 'imageUrl': imageUrl};
    try {
      if (dest == 'nurses') {
        await http.put(Uri.parse('$firebaseDbUrl/nurses_group_chat/messages/$id.json'), body: jsonEncode({...base, 'destination': 'nurses'}));
        await http.put(Uri.parse('$firebaseDbUrl/nurseCommunityChat/messages/$id.json'), body: jsonEncode({...base, 'destination': 'nurses'}));
      } else {
        final home = {...base, 'announcementId': id, 'textColor': textColor, 'bgColor': bgColor, 'displayType': displayType, 'speed': speed, 'active': true, 'destination': 'index', 'isHomePage': true};
        await http.put(Uri.parse('$firebaseDbUrl/ceoHomePageAnnouncements/$id.json'), body: jsonEncode(home));
        await http.put(Uri.parse('$firebaseDbUrl/ceoHomePageCurrent.json'), body: jsonEncode(home));
        await http.put(Uri.parse('$firebaseDbUrl/homePageBanner/current.json'), body: jsonEncode(home));
      }
      return true;
    } catch (e) { return false; }
  }

  static Future<bool> delete(String id, String dest) async {
    try {
      if (dest == 'nurses') {
        await http.delete(Uri.parse('$firebaseDbUrl/nurses_group_chat/messages/$id.json'));
      } else {
        await http.delete(Uri.parse('$firebaseDbUrl/ceoHomePageAnnouncements/$id.json'));
        await http.delete(Uri.parse('$firebaseDbUrl/ceoHomePageCurrent.json'));
      }
      return true;
    } catch (e) { return false; }
  }
}
