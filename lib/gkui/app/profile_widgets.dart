part of '../../main_gkui.dart';

/// Plex Home profiles as large tiles: names stay readable and every target
/// is easy to hit on the 800x480 head unit.
class ProfilePickerDialog extends StatelessWidget {
  const ProfilePickerDialog(
      {required this.users, required this.currentUuid, super.key});
  final List<PlexHomeUser> users;
  final String? currentUuid;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 14, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Row(children: <Widget>[
              const Expanded(
                child: Text('Switch profile',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              ),
              SizedBox(
                width: 56,
                height: 56,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 30),
                  tooltip: 'Close',
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 250,
                  mainAxisExtent: 84,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  return ProfileTile(
                    user: user,
                    current: user.uuid == currentUuid,
                    onTap: user.uuid == currentUuid
                        ? null
                        : () => Navigator.pop(context, user),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class ProfileTile extends StatelessWidget {
  const ProfileTile(
      {required this.user, required this.current, this.onTap, super.key});
  final PlexHomeUser user;
  final bool current;
  final VoidCallback? onTap;

  static const List<Color> _avatarColors = <Color>[
    Color(0xFFE5A00D),
    Color(0xFF4FA3E0),
    Color(0xFF6CC070),
    Color(0xFFE0706A),
    Color(0xFFB07FE0),
    Color(0xFF4DC0B5),
  ];

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final color = _avatarColors[name.hashCode.abs() % _avatarColors.length];
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: current ? const Color(0xFF3A2C10) : const Color(0xFF262626),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: current ? accent : const Color(0xFF3A3A3A), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: <Widget>[
            CircleAvatar(
              radius: 24,
              backgroundColor: color,
              child: Text(initial,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.black)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(name.isEmpty ? 'Profile' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w600)),
                    Text(
                        current
                            ? 'Watching now'
                            : user.admin
                                ? 'Home owner'
                                : user.guest
                                    ? 'Guest'
                                    : 'Managed user',
                        maxLines: 1,
                        style: TextStyle(
                            fontSize: 14,
                            color: current ? accent : Colors.white60)),
                  ]),
            ),
            if (current)
              Icon(Icons.check_circle, color: accent, size: 26)
            else if (user.protected)
              const Icon(Icons.lock_outline, size: 24, color: Colors.white70),
          ]),
        ),
      ),
    );
  }
}

/// A four-digit PIN entered on large on-screen keys. The system keyboard on
/// the head unit covers most of the screen and offers letters and symbols a
/// Plex Home PIN never contains. The PIN is tried as soon as it is complete;
/// a wrong one clears the dots and says so, without closing the pad.
class PinPadDialog extends StatefulWidget {
  const PinPadDialog(
      {required this.title,
      required this.onSubmit,
      this.length = 4,
      super.key});
  final String title;

  /// Tries a complete PIN. Returns null on success, or the message to show.
  final Future<String?> Function(String pin) onSubmit;
  final int length;

  @override
  State<PinPadDialog> createState() => _PinPadDialogState();
}

class _PinPadDialogState extends State<PinPadDialog> {
  String _pin = '';
  String? _message;
  bool _busy = false;

  Future<void> _press(String key) async {
    if (_busy) return;
    setState(() {
      _message = null;
      if (key == 'back') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (key == 'clear') {
        _pin = '';
      } else if (_pin.length < widget.length) {
        _pin += key;
      }
    });
    if (_pin.length < widget.length) return;
    setState(() => _busy = true);
    final error = await widget.onSubmit(_pin);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _pin = '';
      _message = error;
    });
  }

  Widget _key(String label, String value, {IconData? icon}) => Padding(
        padding: const EdgeInsets.all(5),
        child: SizedBox(
          width: 92,
          height: 64,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: const Color(0xFF262626),
              side: const BorderSide(color: Color(0xFF4A4A4A)),
            ),
            onPressed: _busy ? null : () => _press(value),
            child: icon != null
                ? Icon(icon, size: 30, semanticLabel: label)
                : Text(label,
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          SizedBox(
            width: 230,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  Row(children: <Widget>[
                    for (var i = 0; i < widget.length; i++)
                      Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.only(right: 14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _pin.length ? accent : null,
                          border: Border.all(color: accent, width: 2),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 48,
                    child: _busy
                        ? const Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                                width: 26,
                                height: 26,
                                child:
                                    CircularProgressIndicator(strokeWidth: 3)))
                        : Text(_message ?? '',
                            maxLines: 2,
                            style: const TextStyle(
                                fontSize: 16, color: Color(0xFFFF8A80))),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      onPressed:
                          _busy ? null : () => Navigator.pop(context, false),
                      child:
                          const Text('Cancel', style: TextStyle(fontSize: 19)),
                    ),
                  ),
                ]),
          ),
          const SizedBox(width: 16),
          Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            for (final row in const <List<String>>[
              <String>['1', '2', '3'],
              <String>['4', '5', '6'],
              <String>['7', '8', '9'],
            ])
              Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                for (final digit in row) _key(digit, digit),
              ]),
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              _key('Clear', 'clear', icon: Icons.close),
              _key('0', '0'),
              _key('Delete', 'back', icon: Icons.backspace_outlined),
            ]),
          ]),
        ]),
      ),
    );
  }
}

/// What to show on the PIN pad when switching profile fails.
String profileSwitchError(Object error, String fallback) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403 || status == 422) {
      return 'Wrong PIN. Try again.';
    }
  }
  return fallback;
}
