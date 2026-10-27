import 'package:flutter/material.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../strings.dart';

class NotificationsScreen extends StatefulWidget {
  final AuthState auth;
  const NotificationsScreen({super.key, required this.auth});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  List<AppNotification> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.auth.api.notifications();
      setState(() {
        _items = list.map((n) => AppNotification.fromJson(n)).toList();
        _loading = false;
      });
    } on ApiException {
      setState(() => _loading = false);
    }
  }

  Future<void> _markRead(AppNotification n) async {
    if (n.isRead) return;
    // تحديث فوري في الواجهة ثم تأكيد من الخادم
    setState(() => _items = _items
        .map((x) => x.id == n.id
            ? AppNotification.fromJson({
                'id': x.id,
                'title': x.title,
                'body': x.body,
                'isRead': true,
                'createdAt': x.createdAt,
              })
            : x)
        .toList());
    try {
      await widget.auth.api.markNotificationRead(n.id);
    } on ApiException {
      // تجاهل — التحديث المحلي يكفي لتجربة المستخدم
    }
  }

  void _openNotification(AppNotification n) {
    _markRead(n); // الضغط على الإشعار يجعله مقروءاً مباشرة
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n.title),
        content: SingleChildScrollView(child: Text(n.body)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(S.t('إغلاق'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('الإشعارات'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(
                            child: Text(
                                S.t('لا توجد إشعارات — ستصلك تنبيهات الحجوزات وانخفاض الأسعار هنا'))),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final n = _items[i];
                      return Card(
                        color: n.isRead ? null : const Color(0xFFFDF6E7),
                        child: ListTile(
                          leading: Icon(
                            n.isRead
                                ? Icons.notifications_none
                                : Icons.notifications_active,
                            color: n.isRead ? Colors.grey : const Color(0xFFD9A441),
                          ),
                          title: Text(n.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              '${n.body}\n${n.createdAt.replaceAll('T', ' ').substring(0, 16)}'),
                          isThreeLine: true,
                          trailing: n.isRead
                              ? null
                              : Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFD9A441),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                          onTap: () => _openNotification(n),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
