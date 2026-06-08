import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_theme.dart';
import '../ui/common.dart';

/// A person chosen (or typed) in the picker, to seed a new qardan.
class PickedContact {
  final String name;
  final String phone;
  const PickedContact({required this.name, required this.phone});
}

/// GPay-style first step of adding a qardan: search your contacts, tap one,
/// or type a name / number for someone not saved on the device.
class ContactPickerScreen extends StatefulWidget {
  const ContactPickerScreen({super.key});

  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<ContactPickerScreen> {
  final _searchController = TextEditingController();

  List<Contact> _all = [];
  bool _loading = true;
  bool _permissionDenied = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      setState(() {
        _permissionDenied = true;
        _loading = false;
      });
      return;
    }
    final contacts =
        await FlutterContacts.getContacts(withProperties: true);
    // Keep only contacts that actually have a phone number.
    contacts.retainWhere((c) => c.phones.isNotEmpty);
    contacts.sort((a, b) => a.displayName
        .toLowerCase()
        .compareTo(b.displayName.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _all = contacts;
      _loading = false;
    });
  }

  /// Contacts whose name or any number matches the query.
  List<Contact> get _filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all.where((c) {
      if (c.displayName.toLowerCase().contains(q)) return true;
      return c.phones.any((p) => p.number.replaceAll(' ', '').contains(q));
    }).toList();
  }

  bool get _queryLooksLikeNumber {
    final digits = _query.replaceAll(RegExp(r'[^0-9+]'), '');
    return digits.length >= 5;
  }

  void _pick(String name, String phone) {
    Navigator.of(context).pop(PickedContact(name: name, phone: phone));
  }

  /// Re-request contacts access; if the OS won't prompt again (permanently
  /// denied), send the user straight to app settings.
  Future<void> _grantContacts() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (granted) {
      setState(() {
        _permissionDenied = false;
        _loading = true;
      });
      await _loadContacts();
    } else {
      await openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search name or number',
            border: InputBorder.none,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final manualTiles = _buildManualTiles();
    final results = _filtered;

    return ListView(
      children: [
        if (_permissionDenied) _permissionBanner(),
        ...manualTiles,
        if (manualTiles.isNotEmpty && results.isNotEmpty)
          const Divider(height: 1),
        ...results.map(_contactTile),
        if (!_permissionDenied && results.isEmpty && manualTiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
                child: Text('Type a name or number above to add someone.')),
          ),
      ],
    );
  }

  Widget _permissionBanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sage.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Contacts access is off',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Turn it on to search your contacts, or just type a name and number '
            'below to add someone manually.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _grantContacts,
            icon: const Icon(Icons.contacts_outlined),
            label: const Text('Grant contacts access'),
          ),
        ],
      ),
    );
  }

  /// Quick-add tiles shown above the results when the user has typed something
  /// that isn't (yet) a saved contact.
  List<Widget> _buildManualTiles() {
    if (_query.isEmpty) return [];
    final tiles = <Widget>[];

    // Exact phone-number entry -> use number as both number and label.
    if (_queryLooksLikeNumber) {
      tiles.add(_actionTile(
        icon: Icons.dialpad,
        title: 'Add to $_query',
        subtitle: 'Use this number',
        onTap: () => _pick(_query, _query),
      ));
    } else {
      // Typed a name with no match -> proceed with the name, enter number next.
      final hasExactName = _all.any(
          (c) => c.displayName.toLowerCase() == _query.toLowerCase());
      if (!hasExactName) {
        tiles.add(_actionTile(
          icon: Icons.person_add_alt_1,
          title: 'Add new: “$_query”',
          subtitle: 'Enter number on the next screen',
          onTap: () => _pick(_query, ''),
        ));
      }
    }
    return tiles;
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.sage,
        child: Icon(icon, color: AppColors.pine),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }

  Widget _contactTile(Contact c) {
    final phone = c.phones.first.number;
    return ListTile(
      leading: InitialAvatar(name: c.displayName, radius: 22),
      title: Text(c.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(phone),
      onTap: () => _pick(c.displayName, phone),
    );
  }
}
