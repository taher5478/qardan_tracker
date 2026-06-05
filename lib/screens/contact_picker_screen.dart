import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

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

    if (results.isEmpty && manualTiles.isEmpty) {
      return Center(
        child: Text(_permissionDenied
            ? 'Contacts permission denied.\nType a name or number above to add manually.'
            : 'No contacts found.\nType a name or number above.'),
      );
    }

    return ListView(
      children: [
        ...manualTiles,
        if (manualTiles.isNotEmpty && results.isNotEmpty)
          const Divider(height: 1),
        ...results.map(_contactTile),
      ],
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
