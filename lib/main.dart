import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Audio service – one AudioPlayer per note, reused to prevent memory leaks
// ---------------------------------------------------------------------------
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  final Map<String, AudioPlayer> _players = {};

  static const Map<String, String> _noteFiles = {
    'C': 'C',
    'D': 'D',
    'E': 'E',
    'F': 'F',
    'G': 'G',
    'A': 'A',
    'B': 'B',
    "C'": 'C2',
  };

  Future<void> play(String note) async {
    final filename = _noteFiles[note];
    if (filename == null) return;
    final player = _players.putIfAbsent(note, () => AudioPlayer());
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.stop();
    await player.setReleaseMode(ReleaseMode.release);
    await player.play(AssetSource('notes/$filename.mp3'));
  }

  Future<void> startLooping(String note) async {
    final filename = _noteFiles[note];
    if (filename == null) return;
    final player = _players.putIfAbsent(note, () => AudioPlayer());
    if (player.state == PlayerState.playing) {
      await player.stop();
    }
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(AssetSource('notes/$filename.mp3'));
  }

  Future<void> stopNote(String note) async {
    final player = _players[note];
    if (player == null) return;
    if (player.state == PlayerState.playing) {
      await player.setReleaseMode(ReleaseMode.release);
    } else {
      await player.setReleaseMode(ReleaseMode.release);
      await player.stop();
    }
  }

  Future<void> stopAll() async {
    for (final entry in _players.entries) {
      await entry.value.stop();
    }
  }

  Future<void> disposeAll() async {
    for (final p in _players.values) {
      await p.dispose();
    }
    _players.clear();
  }
}

// ---------------------------------------------------------------------------
// App entry
// ---------------------------------------------------------------------------
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const AngklungApp());
}

class AngklungApp extends StatelessWidget {
  const AngklungApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Angklung IoT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF48FB1),
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
      ),
      home: const SetupGate(),
    );
  }
}

// ---------------------------------------------------------------------------
// Setup gate
// ---------------------------------------------------------------------------
class SetupGate extends StatefulWidget {
  const SetupGate({super.key});
  @override
  State<SetupGate> createState() => _SetupGateState();
}

class _SetupGateState extends State<SetupGate> {
  bool? _configured;

  @override
  void initState() {
    super.initState();
    _checkConfig();
  }

  Future<void> _checkConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('firebase_db_url') ?? '';
    setState(() => _configured = url.isNotEmpty);
  }

  void _onConfigured() => setState(() => _configured = true);

  @override
  Widget build(BuildContext context) {
    if (_configured == null) return const SizedBox.shrink();
    if (!_configured!) return SetupScreen(onDone: _onConfigured);
    return const MainPage();
  }
}

// ---------------------------------------------------------------------------
// Setup / Settings screen
// ---------------------------------------------------------------------------
class SetupScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SetupScreen({super.key, required this.onDone});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _fbController = TextEditingController();
  final _aiController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _fbController.text = prefs.getString('firebase_db_url') ?? '';
    _aiController.text = prefs.getString('gemini_api_key') ?? '';
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('firebase_db_url', _fbController.text.trim());
      await prefs.setString('gemini_api_key', _aiController.text.trim());
      widget.onDone();
    }
  }

  @override
  void dispose() {
    _fbController.dispose();
    _aiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCE4EC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.music_note, size: 42, color: Color(0xFFAD1457)),
                  const SizedBox(height: 8),
                  const Text(
                    'Angklung IoT',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Configure your connections',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _fbController,
                    decoration: const InputDecoration(
                      labelText: 'Firebase Realtime Database URL *',
                      hintText: 'https://your-project.firebaseio.com',
                      prefixIcon: Icon(Icons.cloud_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _aiController,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: 'Gemini API Key (for Song Converter)',
                      hintText: 'AIzaSy...',
                      prefixIcon: const Icon(Icons.auto_awesome_outlined),
                      helperText: 'Optional – needed for YouTube → Sequence conversion',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscureKey ? Icons.visibility_off : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Save & Continue'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(200, 44),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main navigation – 6 tabs (added Games)
// ---------------------------------------------------------------------------
class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _pageIndex = 0;

  static const _pages = [
    AngklungSimulator(),
    RemoteController(),
    MusicPage(),
    RecorderPage(),
    SongConverterPage(),
    GamesPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF0F5), Color(0xFFF3E5F5)],
          ),
        ),
        child: Column(
          children: [
            _AppBar(
              onSettings: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SetupScreen(onDone: () => Navigator.pop(context)),
                ),
              ),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: IndexedStack(index: _pageIndex, children: _pages),
              ),
            ),
            _BottomNav(
              selectedIndex: _pageIndex,
              onTap: (i) {
                if (_pageIndex == 0 && i != 0) {
                  AudioService.instance.stopAll();
                }
                setState(() => _pageIndex = i);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom AppBar
// ---------------------------------------------------------------------------
class _AppBar extends StatelessWidget {
  final VoidCallback onSettings;
  const _AppBar({required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF8BBD0), Color(0xFFE1BEE7)],
        ),
        boxShadow: [
          BoxShadow(color: Color(0x18000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          const Text('🎵', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          const Text(
            'Angklung IoT',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF880E4F),
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onSettings,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.settings_outlined, size: 14, color: Color(0xFF880E4F)),
                  SizedBox(width: 4),
                  Text(
                    'Settings',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF880E4F)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom Bottom Nav – 6 tabs
// ---------------------------------------------------------------------------
class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onTap;

  const _BottomNav({required this.selectedIndex, required this.onTap});

  static const _items = [
    _NavItem(Icons.piano_outlined, Icons.piano, 'Simulator'),
    _NavItem(Icons.settings_remote_outlined, Icons.settings_remote, 'Remote'),
    _NavItem(Icons.music_note_outlined, Icons.music_note, 'Music'),
    _NavItem(Icons.fiber_manual_record_outlined, Icons.fiber_manual_record, 'Record'),
    _NavItem(Icons.auto_awesome_outlined, Icons.auto_awesome, 'Convert'),
    _NavItem(Icons.sports_esports_outlined, Icons.sports_esports, 'Games'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        children: List.generate(_items.length, (i) {
          final item = _items[i];
          final isSelected = selectedIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (i == 5
                          ? const Color(0xFFE8F5E9).withOpacity(0.8)
                          : const Color(0xFFF8BBD0).withOpacity(0.6))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        isSelected ? item.selectedIcon : item.icon,
                        key: ValueKey(isSelected),
                        size: 20,
                        color: isSelected
                            ? (i == 5
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFAD1457))
                            : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.normal,
                        color: isSelected
                            ? (i == 5
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFAD1457))
                            : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.icon, this.selectedIcon, this.label);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
Future<String> getDatabaseUrl() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('firebase_db_url') ?? '';
}

Future<String> getGeminiKey() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('gemini_api_key') ?? '';
}

const Map<String, String> kNoteFirebaseKeys = {
  'C': 'note1',
  'D': 'note2',
  'E': 'note3',
  'F': 'note4',
  'G': 'note5',
  'A': 'note6',
  'B': 'note7',
  "C'": 'note8',
};

const List<String> kNotes = ['C', 'D', 'E', 'F', 'G', 'A', 'B', "C'"];
const List<String> kNoteSymbols = ['♩', '♪', '♫', '♬', '♩', '♪', '♫', '♬'];

const List<List<Color>> kNoteGradients = [
  [Color(0xFFF8BBD0), Color(0xFFF48FB1)],
  [Color(0xFFE1BEE7), Color(0xFFCE93D8)],
  [Color(0xFFBBDEFB), Color(0xFF90CAF9)],
  [Color(0xFFC8E6C9), Color(0xFFA5D6A7)],
  [Color(0xFFFFF9C4), Color(0xFFFFF176)],
  [Color(0xFFFFE0B2), Color(0xFFFFCC80)],
  [Color(0xFFFFCDD2), Color(0xFFEF9A9A)],
  [Color(0xFFD1C4E9), Color(0xFFB39DDB)],
];

// ---------------------------------------------------------------------------
// NoteButton
// ---------------------------------------------------------------------------
class NoteButton extends StatefulWidget {
  final String note;
  final int noteIndex;
  final VoidCallback? onTap;
  final void Function(bool pressed)? onPressedChanged;

  const NoteButton({
    super.key,
    required this.note,
    required this.noteIndex,
    this.onTap,
    this.onPressedChanged,
  });

  @override
  State<NoteButton> createState() => _NoteButtonState();
}

class _NoteButtonState extends State<NoteButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _setPressed(bool v) {
    setState(() => _pressed = v);
    if (v) {
      _scaleCtrl.animateTo(0.0);
    } else {
      _scaleCtrl.animateTo(1.0);
    }
    widget.onPressedChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final gradColors = kNoteGradients[widget.noteIndex];
    final symbol = kNoteSymbols[widget.noteIndex];

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap?.call();
      },
      onTapCancel: () => _setPressed(false),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _pressed
                  ? [
                      gradColors[1],
                      HSLColor.fromColor(gradColors[1])
                          .withLightness(
                            (HSLColor.fromColor(gradColors[1]).lightness - 0.1)
                                .clamp(0.0, 1.0))
                          .toColor(),
                    ]
                  : gradColors,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _pressed
                ? [
                    BoxShadow(
                      color: gradColors[1].withOpacity(0.55),
                      blurRadius: 12,
                      spreadRadius: 2,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                    BoxShadow(
                      color: gradColors[1].withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 1),
                    ),
                  ],
            border: _pressed
                ? Border.all(color: gradColors[1].withOpacity(0.7), width: 2)
                : Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 3,
                right: 6,
                child: Text(
                  symbol,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(_pressed ? 0.75 : 0.45),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.note,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF4A148C).withOpacity(0.85),
                        height: 1,
                        shadows: [
                          Shadow(
                            color: Colors.white.withOpacity(0.7),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _solfege(widget.noteIndex),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6A1B9A).withOpacity(0.6),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (_pressed)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(0.25),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _solfege(int i) {
    const names = ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si', 'Do\''];
    return names[i];
  }
}

// ---------------------------------------------------------------------------
// Note grid
// ---------------------------------------------------------------------------
class NoteGrid extends StatelessWidget {
  final void Function(String note)? onTap;
  final void Function(String note, bool pressed)? onPressedChanged;

  const NoteGrid({super.key, this.onTap, this.onPressedChanged});

  @override
  Widget build(BuildContext context) {
    final topRow = kNotes.sublist(0, 4);
    final bottomRow = kNotes.sublist(4);

    Widget buildRow(List<String> rowNotes, int colorOffset) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rowNotes.asMap().entries.map((e) {
          final note = e.value;
          final idx = e.key + colorOffset;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: NoteButton(
                note: note,
                noteIndex: idx,
                onTap: onTap != null ? () => onTap!(note) : null,
                onPressedChanged: onPressedChanged != null
                    ? (p) => onPressedChanged!(note, p)
                    : null,
              ),
            ),
          );
        }).toList(),
      );
    }

    return Column(
      children: [
        Expanded(child: buildRow(topRow, 0)),
        const SizedBox(height: 10),
        Expanded(child: buildRow(bottomRow, 4)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 1. SIMULATOR
// ---------------------------------------------------------------------------
class AngklungSimulator extends StatefulWidget {
  const AngklungSimulator({super.key});
  @override
  State<AngklungSimulator> createState() => _AngklungSimulatorState();
}

class _AngklungSimulatorState extends State<AngklungSimulator> {
  final Set<String> _heldNotes = {};

  void _onPressChanged(String note, bool pressed) {
    if (pressed) {
      setState(() => _heldNotes.add(note));
      AudioService.instance.startLooping(note);
    } else {
      setState(() => _heldNotes.remove(note));
      AudioService.instance.stopNote(note);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SimulatorHintBar(heldNotes: _heldNotes),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: NoteGrid(onPressedChanged: _onPressChanged),
          ),
        ),
      ],
    );
  }
}

class _SimulatorHintBar extends StatelessWidget {
  final Set<String> heldNotes;
  const _SimulatorHintBar({required this.heldNotes});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 34,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: heldNotes.isNotEmpty
              ? [const Color(0xFFF8BBD0), const Color(0xFFE1BEE7)]
              : [const Color(0xFFFCE4EC), const Color(0xFFF3E5F5)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.pinkAccent.withOpacity(0.1),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (heldNotes.isEmpty) ...[
            const Icon(Icons.touch_app_outlined, size: 14, color: Color(0xFFAD1457)),
            const SizedBox(width: 6),
            const Text(
              'Press & hold a note to play  •  Release to stop',
              style: TextStyle(
                  fontSize: 11, color: Color(0xFFAD1457), fontWeight: FontWeight.w500),
            ),
          ] else ...[
            const Icon(Icons.graphic_eq, size: 14, color: Color(0xFFAD1457)),
            const SizedBox(width: 6),
            Text(
              'Playing:  ${heldNotes.join('  +  ')}',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFFAD1457), fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. REMOTE
// ---------------------------------------------------------------------------
class RemoteController extends StatefulWidget {
  const RemoteController({super.key});
  @override
  State<RemoteController> createState() => _RemoteControllerState();
}

class _RemoteControllerState extends State<RemoteController> {
  String? _lastSent;
  bool _sending = false;

  Future<void> _sendNote(String note) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _lastSent = note;
    });
    try {
      final baseUrl = await getDatabaseUrl();
      if (baseUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Firebase URL not configured')),
          );
        }
        return;
      }
      final firebaseKey = kNoteFirebaseKeys[note]!;
      await http.put(
        Uri.parse('$baseUrl/angklung/$firebaseKey.json'),
        headers: {'Content-Type': 'application/json'},
        body: 'true',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Send failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings_remote, size: 15, color: Color(0xFFAD1457)),
                const SizedBox(width: 6),
                const Text('Remote → ESP32',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                if (_sending)
                  const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                if (_lastSent != null && !_sending) ...[
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      key: ValueKey(_lastSent),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8BBD0),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '✓ Sent: $_lastSent  →  ${kNoteFirebaseKeys[_lastSent!]}',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text('Sets true → ESP32 resets',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: NoteGrid(onTap: _sendNote),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. MUSIC PAGE
// ---------------------------------------------------------------------------
class MusicPage extends StatefulWidget {
  const MusicPage({super.key});
  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  String? _activeSong;
  bool _sending = false;

  static const List<Map<String, dynamic>> _songs = [
    {
      'key': 'playPusaka',
      'label': 'Pusaka',
      'subtitle': 'Tanah Airku',
      'emoji': '🇮🇩',
      'gradient': [Color(0xFFFFCDD2), Color(0xFFEF9A9A)],
    },
    {
      'key': 'playRaya',
      'label': 'Raya',
      'subtitle': 'Indonesia Raya',
      'emoji': '🎌',
      'gradient': [Color(0xFFF8BBD0), Color(0xFFF48FB1)],
    },
    {
      'key': 'playHalo',
      'label': 'Halo-Halo',
      'subtitle': 'Halo-Halo Bandung',
      'emoji': '🌆',
      'gradient': [Color(0xFFE1BEE7), Color(0xFFCE93D8)],
    },
    {
      'key': 'playKartini',
      'label': 'Kartini',
      'subtitle': 'Ibu Kita Kartini',
      'emoji': '👗',
      'gradient': [Color(0xFFBBDEFB), Color(0xFF90CAF9)],
    },
    {
      'key': 'playKetut',
      'label': 'Ketut',
      'subtitle': 'Custom song',
      'emoji': '🎵',
      'gradient': [Color(0xFFC8E6C9), Color(0xFFA5D6A7)],
    },
  ];

  Future<void> _triggerSong(String songKey) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _activeSong = songKey;
    });
    try {
      final baseUrl = await getDatabaseUrl();
      if (baseUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Firebase URL not configured')),
          );
        }
        return;
      }
      await http.put(
        Uri.parse('$baseUrl/angklung/$songKey.json'),
        headers: {'Content-Type': 'application/json'},
        body: 'true',
      );
      final song = _songs.firstWhere((s) => s['key'] == songKey);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('▶ Playing ${song['label']}…'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _stop() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _activeSong = null;
    });
    try {
      final baseUrl = await getDatabaseUrl();
      if (baseUrl.isEmpty) return;
      await http.put(
        Uri.parse('$baseUrl/angklung/stop.json'),
        headers: {'Content-Type': 'application/json'},
        body: 'true',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('⏹ Stop sent'), duration: Duration(seconds: 1)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, size: 16, color: Color(0xFFAD1457)),
              const SizedBox(width: 6),
              const Text('Play Music on ESP32',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _sending ? null : _stop,
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                label: const Text('Stop', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  backgroundColor: Colors.red.shade50,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (_sending) ...[
                const SizedBox(width: 8),
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.8,
              ),
              itemCount: _songs.length,
              itemBuilder: (context, i) {
                final song = _songs[i];
                final key = song['key'] as String;
                final isActive = _activeSong == key;
                final gradColors = song['gradient'] as List<Color>;
                return GestureDetector(
                  onTap: _sending ? null : () => _triggerSong(key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isActive
                            ? [gradColors[1], gradColors[0]]
                            : gradColors,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: isActive
                          ? Border.all(color: Colors.deepOrange.shade400, width: 2)
                          : Border.all(
                              color: Colors.white.withOpacity(0.6), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: gradColors[1].withOpacity(isActive ? 0.4 : 0.25),
                          blurRadius: isActive ? 10 : 5,
                          offset: Offset(0, isActive ? 2 : 3),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Text(song['emoji'] as String,
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(song['label'] as String,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF4A148C))),
                                Text(song['subtitle'] as String,
                                    style: const TextStyle(
                                        fontSize: 10, color: Color(0xFF6A1B9A))),
                              ],
                            ),
                          ),
                          if (isActive)
                            const Icon(Icons.graphic_eq,
                                size: 16, color: Colors.deepOrange),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. RECORDER
// ---------------------------------------------------------------------------
class RecorderPage extends StatefulWidget {
  const RecorderPage({super.key});
  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  bool _recording = false;
  bool _paused = false;
  Timer? _timer;
  Timer? _countdownTimer;
  int _elapsedMs = 0;
  int _countdown = 0;
  DateTime? _recordingStartTime;
  DateTime? _lastEventEndTime;
  List<List<dynamic>> _sequence = [];
  String? _pressedNote;
  DateTime? _pressTime;
  static const double _minDurationSec = 0.3;

  void _startCountdown() {
    setState(() => _countdown = 3);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        t.cancel();
        _beginRecording();
      }
    });
  }

  void _beginRecording() {
    final now = DateTime.now();
    setState(() {
      _recording = true;
      _paused = false;
      _elapsedMs = 0;
      _countdown = 0;
      _sequence = [];
      _pressedNote = null;
      _recordingStartTime = now;
      _lastEventEndTime = now;
    });
    _startElapsedTimer();
  }

  void _startElapsedTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_paused && _recordingStartTime != null) {
        setState(() {
          _elapsedMs =
              DateTime.now().difference(_recordingStartTime!).inMilliseconds;
        });
      }
    });
  }

  void _pauseResume() {
    if (_paused) {
      _recordingStartTime =
          DateTime.now().subtract(Duration(milliseconds: _elapsedMs));
      _startElapsedTimer();
      setState(() => _paused = false);
    } else {
      _timer?.cancel();
      setState(() => _paused = true);
    }
  }

  void _reset() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    setState(() {
      _recording = false;
      _paused = false;
      _elapsedMs = 0;
      _countdown = 0;
      _sequence = [];
      _pressedNote = null;
    });
  }

  Future<void> _stopAndSend() async {
    if (_pressedNote != null) _finaliseCurrentNote();
    _timer?.cancel();
    setState(() {
      _recording = false;
      _paused = false;
    });
    if (_sequence.isEmpty) return;
    final url = await getDatabaseUrl();
    if (url.isNotEmpty) {
      final uri = Uri.parse('$url/recordings.json');
      await http.post(uri, body: jsonEncode(_sequence));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording sent to Firebase')),
        );
      }
    }
  }

  void _onNotePressState(String note, bool pressed) {
    if (!_recording || _paused) {
      if (pressed) AudioService.instance.play(note);
      return;
    }
    if (pressed) {
      if (_pressedNote != null && _pressedNote != note) {
        _finaliseCurrentNote();
      }
      _pressedNote = note;
      _pressTime = DateTime.now();
      AudioService.instance.play(note);
    } else {
      if (_pressedNote == note) {
        _finaliseCurrentNote();
        _pressedNote = null;
      }
    }
  }

  void _finaliseCurrentNote() {
    if (_pressedNote == null || _pressTime == null) return;
    final noteIndex = kNotes.indexOf(_pressedNote!) + 1;
    final pressTime = _pressTime!;
    final now = DateTime.now();
    double durationSec = now.difference(pressTime).inMilliseconds / 1000.0;
    if (durationSec < _minDurationSec) durationSec = _minDurationSec;
    final gapSec =
        pressTime.difference(_lastEventEndTime!).inMilliseconds / 1000.0;
    if (gapSec > 0.01) {
      _sequence.add([0, double.parse(gapSec.toStringAsFixed(2))]);
    }
    _sequence
        .add([noteIndex, double.parse(durationSec.toStringAsFixed(2))]);
    _lastEventEndTime = pressTime
        .add(Duration(milliseconds: (durationSec * 1000).round()));
    setState(() {});
  }

  String _formatMs(int ms) {
    final sec = ms ~/ 1000;
    final min = sec ~/ 60;
    return '${min.toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCountingDown = _countdown > 0;
    return Column(
      children: [
        Container(
          height: 40,
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _recording && !_paused
                  ? [Colors.red.shade50, Colors.pink.shade50]
                  : [const Color(0xFFFCE4EC), const Color(0xFFF3E5F5)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  isCountingDown ? '$_countdown' : _formatMs(_elapsedMs),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isCountingDown ? 34 : 22,
                    fontWeight: FontWeight.bold,
                    color: _recording && !_paused
                        ? Colors.redAccent
                        : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!_recording && !isCountingDown)
                _CtrlButton(
                  icon: Icons.fiber_manual_record,
                  label: 'Record',
                  color: Colors.redAccent,
                  onPressed: _startCountdown,
                )
              else if (_recording) ...[
                _CtrlButton(
                  icon: _paused ? Icons.play_arrow : Icons.pause,
                  label: _paused ? 'Resume' : 'Pause',
                  onPressed: _pauseResume,
                ),
                const SizedBox(width: 6),
                _CtrlButton(
                    icon: Icons.refresh, label: 'Reset', onPressed: _reset),
                const SizedBox(width: 6),
                _CtrlButton(
                  icon: Icons.stop_circle,
                  label: 'Stop & Send',
                  color: Colors.deepOrange,
                  onPressed: _stopAndSend,
                ),
              ],
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8BBD0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_sequence.length} events',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: NoteGrid(onPressedChanged: _onNotePressState),
          ),
        ),
      ],
    );
  }
}

class _CtrlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  const _CtrlButton(
      {required this.icon,
      required this.label,
      required this.onPressed,
      this.color});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: color,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. SONG CONVERTER
// ---------------------------------------------------------------------------
class SongConverterPage extends StatefulWidget {
  const SongConverterPage({super.key});
  @override
  State<SongConverterPage> createState() => _SongConverterPageState();
}

class _SongConverterPageState extends State<SongConverterPage> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  bool _converting = false;
  bool _saving = false;
  String? _error;
  String? _statusMessage;
  List<List<dynamic>>? _sequence;
  String? _savedId;

  Future<void> _convert() async {
    final ytUrl = _urlController.text.trim();
    if (ytUrl.isEmpty) {
      setState(() => _error = 'Please enter a YouTube URL');
      return;
    }
    setState(() {
      _converting = true;
      _error = null;
      _sequence = null;
      _savedId = null;
      _statusMessage = 'Identifying song via Gemini…';
    });
    try {
      final apiKey = await getGeminiKey();
      if (apiKey.isEmpty) {
        setState(() {
          _error =
              'Gemini API key not configured.\nGo to ⚙ Settings and add your AIza... key.';
        });
        return;
      }
      final response = await http.post(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {
                  'text':
                      '''You are an expert angklung music transcriber.\n\nYouTube URL: $ytUrl\n\nYour task:\n1. Identify the song title and artist from this YouTube URL (search the video ID or URL).\n2. Look up the melody/notes of this song.\n3. Transcribe the MAIN MELODY (verse or chorus) into angklung notation.\n\nAngklung note mapping:\n  0 = rest/silence\n  1 = C  (Do)\n  2 = D  (Re)\n  3 = E  (Mi)\n  4 = F  (Fa)\n  5 = G  (Sol)\n  6 = A  (La)\n  7 = B  (Si)\n  8 = C\' (High Do)\n\nDuration values (in seconds): 0.25, 0.5, 0.75, 1.0, 1.5, 2.0\n\nRules:\n- Only use notes 0–8 (diatonic C major scale)\n- Aim for 16 to 60 events\n- Include rests (0) where appropriate for rhythm\n- Transpose as needed to stay within the 1–8 range\n\nIMPORTANT: Your final response must contain ONLY a valid JSON array.\nDo not include any explanation, markdown backticks, or text outside the array.\n\nFormat:\n[[noteIndex, durationSeconds], [noteIndex, durationSeconds], ...]\n\nExample:\n[[3,0.5],[3,0.5],[5,1.0],[3,1.0],[4,0.5],[2,2.0],[0,0.5],[1,0.5],[2,0.5],[3,1.0]]'''
                }
              ]
            }
          ],
          'tools': [
            {'googleSearch': {}}
          ]
        }),
      );
      setState(() => _statusMessage = 'Processing response…');
      if (response.statusCode != 200) {
        final errBody = utf8.decode(response.bodyBytes);
        Map<String, dynamic>? errJson;
        try {
          errJson = jsonDecode(errBody) as Map<String, dynamic>;
        } catch (_) {}
        final msg =
            errJson?['error']?['message'] ?? 'HTTP ${response.statusCode}';
        setState(() => _error = 'API error: $msg');
        return;
      }
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      String? rawText;
      try {
        rawText =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
      } catch (e) {
        setState(() => _error = 'No valid text response from AI.');
        return;
      }
      if (rawText.isEmpty) {
        setState(() => _error = 'No text response from AI.');
        return;
      }
      final cleaned =
          rawText.replaceAll('```json', '').replaceAll('```', '').trim();
      final match = RegExp(r'\[[\s\S]*\]').firstMatch(cleaned);
      if (match == null) {
        setState(
            () => _error =
                'Could not parse JSON array from response:\n\n$rawText');
        return;
      }
      List<List<dynamic>> parsed;
      try {
        final raw = jsonDecode(match.group(0)!) as List<dynamic>;
        parsed = raw
            .map((e) => (e as List<dynamic>)
                .map((v) => v is num ? v : num.parse(v.toString()))
                .toList())
            .toList();
      } catch (e) {
        setState(
            () => _error = 'JSON parse error: $e\n\n${match.group(0)}');
        return;
      }
      if (_nameController.text.isEmpty) {
        final before = cleaned.substring(0, match.start).trim();
        if (before.isNotEmpty && before.length < 120) {
          _nameController.text = before
              .replaceAll(RegExp(r'\n+'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
        }
      }
      setState(() {
        _sequence = parsed;
        _statusMessage = null;
      });
    } catch (e) {
      setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  Future<void> _saveToFirebase() async {
    if (_sequence == null) return;
    setState(() {
      _saving = true;
      _savedId = null;
    });
    try {
      final baseUrl = await getDatabaseUrl();
      if (baseUrl.isEmpty) {
        setState(() => _error = 'Firebase URL not configured');
        return;
      }
      final String flatSequence =
          _sequence!.map((e) => '{${e[0]},${e[1]}}').join(',');
      final payload = jsonEncode({
        'name': _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : 'Unknown Song',
        'source': _urlController.text.trim(),
        'sequence': flatSequence,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      final response = await http.post(
        Uri.parse('$baseUrl/songs.json'),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );
      if (response.statusCode == 200) {
        final responseData =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final newId = responseData['name'] as String;
        setState(() => _savedId = newId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Saved as songs/$newId'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        setState(
            () => _error = 'Firebase save failed: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _error = 'Save error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _buildPreview(List<List<dynamic>> seq) {
    const noteNames = ['—', 'C', 'D', 'E', 'F', 'G', 'A', 'B', "C'"];
    return seq.map((e) {
      final idx = (e[0] as num).toInt().clamp(0, 8);
      final dur = (e[1] as num).toDouble();
      return '${noteNames[idx]}(${dur}s)';
    }).join('  ');
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFAD1457)),
              const SizedBox(width: 6),
              const Text('YouTube → Angklung Sequence',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('Saves to  songs/<id>',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _urlController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'YouTube URL',
                    labelStyle: const TextStyle(fontSize: 13),
                    hintText: 'https://youtube.com/watch?v=...',
                    prefixIcon: const Icon(Icons.link, size: 18),
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _nameController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Song name',
                    labelStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.music_note, size: 18),
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _converting ? null : _convert,
                icon: _converting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(_converting ? 'Converting…' : 'Convert',
                    style: const TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (_statusMessage != null && _converting) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text(_statusMessage!,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(_error!,
                  style:
                      TextStyle(fontSize: 12, color: Colors.red.shade800)),
            ),
          ],
          if (_sequence != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8BBD0).withOpacity(0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF8BBD0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, size: 15, color: Colors.green),
                      const SizedBox(width: 4),
                      Text('${_sequence!.length} events generated',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      Text(
                        'Total: ${_sequence!.fold<double>(0.0, (sum, e) => sum + (e[1] as num).toDouble()).toStringAsFixed(1)}s',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 56),
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: Text(_buildPreview(_sequence!),
                          style: const TextStyle(
                              fontSize: 11, fontFamily: 'monospace')),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 42),
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: Text(jsonEncode(_sequence),
                          style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: Colors.black54)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveToFirebase,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload, size: 16),
                    label: Text(_saving ? 'Saving…' : 'Save to Firebase  (songs/)',
                        style: const TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade50,
                      foregroundColor: Colors.green.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                if (_savedId != null) ...[
                  const SizedBox(width: 10),
                  Row(
                    children: [
                      const Icon(Icons.check_circle, size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text('songs/$_savedId',
                          style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.green,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// 6. GAMES PAGE
// ===========================================================================
class GamesPage extends StatefulWidget {
  const GamesPage({super.key});
  @override
  State<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends State<GamesPage> {
  int? _selectedGame;

  static const _games = [
    {
      'title': 'Flappy Bird',
      'emoji': '🐦',
      'desc': 'Tap to fly through pipes',
      'colors': [Color(0xFF80DEEA), Color(0xFF00ACC1)],
    },
    {
      'title': 'Note Catcher',
      'emoji': '🎵',
      'desc': 'Catch the falling notes!',
      'colors': [Color(0xFFF8BBD0), Color(0xFFF06292)],
    },
    {
      'title': 'Memory Match',
      'emoji': '🃏',
      'desc': 'Find matching note pairs',
      'colors': [Color(0xFFC8E6C9), Color(0xFF4CAF50)],
    },
    {
      'title': 'Rhythm Tap',
      'emoji': '🥁',
      'desc': 'Tap notes on the beat',
      'colors': [Color(0xFFFFE0B2), Color(0xFFFF9800)],
    },
  ];

  @override
  Widget build(BuildContext context) {
    if (_selectedGame == null) return _buildSelector();
    return _buildGame(_selectedGame!);
  }

  Widget _buildSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_esports, size: 16, color: Color(0xFF2E7D32)),
              const SizedBox(width: 6),
              const Text('Mini Games',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFC8E6C9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('4 games',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E7D32))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 3.0,
              ),
              itemCount: 4,
              itemBuilder: (context, i) {
                final g = _games[i];
                final colors = g['colors'] as List<Color>;
                return GestureDetector(
                  onTap: () => setState(() => _selectedGame = i),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [colors[0], colors[1]],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: colors[1].withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4)),
                      ],
                      border:
                          Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(g['emoji'] as String,
                                  style: const TextStyle(fontSize: 22)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(g['title'] as String,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        shadows: [
                                          Shadow(
                                              color:
                                                  colors[1].withOpacity(0.5),
                                              blurRadius: 4)
                                        ])),
                                const SizedBox(height: 2),
                                Text(g['desc'] as String,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white.withOpacity(0.85))),
                              ],
                            ),
                          ),
                          Icon(Icons.play_circle_fill,
                              size: 26, color: Colors.white.withOpacity(0.8)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGame(int index) {
    final g = _games[index];
    final colors = g['colors'] as List<Color>;
    final Widget game = switch (index) {
      0 => const FlappyBirdGame(),
      1 => const NoteCatcherGame(),
      2 => const MemoryMatchGame(),
      _ => const RhythmTapGame(),
    };
    return Column(
      children: [
        Container(
          height: 36,
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          padding: const EdgeInsets.only(left: 4, right: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [colors[0], colors[1]]),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: colors[1].withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              IconButton(
                icon:
                    const Icon(Icons.arrow_back_ios, size: 14, color: Colors.white),
                onPressed: () => setState(() => _selectedGame = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              Text(
                '${g['emoji']}  ${g['title']}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(child: game),
      ],
    );
  }
}

// ===========================================================================
// GAME 1: FLAPPY BIRD
// ===========================================================================
class _FlappyPipe {
  double x;
  final double gapTop;
  bool scored = false;
  _FlappyPipe({required this.x, required this.gapTop});
}

class FlappyBirdGame extends StatefulWidget {
  const FlappyBirdGame({super.key});
  @override
  State<FlappyBirdGame> createState() => _FlappyBirdGameState();
}

class _FlappyBirdGameState extends State<FlappyBirdGame>
    with TickerProviderStateMixin {
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  double _w = 1, _h = 1;
  bool _sizedReady = false;

  // Bird
  double _birdY = 100;
  double _vy = 0;
  static const double _birdX = 90;
  static const double _birdR = 13;

  // Pipes
  final List<_FlappyPipe> _pipes = [];
  static const double _pipeW = 46;
  static const double _pipeGap = 110;
  static const double _pipeSpeed = 2.8;

  bool _started = false;
  bool _dead = false;
  int _score = 0;

  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _initGame() {
    _birdY = _h / 2;
    _vy = 0;
    _pipes.clear();
    _score = 0;
    _dead = false;
    _started = false;
    _spawnPipe(_w + 40);
    _spawnPipe(_w + 40 + 200);
  }

  void _spawnPipe(double x) {
    final gapTop = 50.0 + _rng.nextDouble() * (_h - _pipeGap - 100);
    _pipes.add(_FlappyPipe(x: x, gapTop: gapTop));
  }

  void _onTick(Duration elapsed) {
    if (!_sizedReady) {
      _lastElapsed = elapsed;
      return;
    }
    if (!_started || _dead) {
      _lastElapsed = elapsed;
      return;
    }
    final dtMs = (elapsed - _lastElapsed).inMilliseconds.clamp(0, 50);
    _lastElapsed = elapsed;
    final dt = dtMs / 16.0;

    setState(() {
      _vy += 0.52 * dt;
      _birdY += _vy * dt;
      for (final p in _pipes) {
        p.x -= _pipeSpeed * dt;
      }
      // Score
      for (final p in _pipes) {
        if (!p.scored && p.x + _pipeW < _birdX - _birdR) {
          p.scored = true;
          _score++;
        }
      }
      // Spawn new pipe
      if (_pipes.last.x < _w - 180) _spawnPipe(_w + 40);
      // Remove old
      _pipes.removeWhere((p) => p.x + _pipeW < -10);
      _checkCollision();
    });
  }

  void _checkCollision() {
    if (_birdY - _birdR < 0 || _birdY + _birdR > _h - 18) {
      _dead = true;
      return;
    }
    for (final p in _pipes) {
      if (_birdX + _birdR > p.x && _birdX - _birdR < p.x + _pipeW) {
        if (_birdY - _birdR < p.gapTop || _birdY + _birdR > p.gapTop + _pipeGap) {
          _dead = true;
          return;
        }
      }
    }
  }

  void _onTap() {
    if (_dead) {
      setState(_initGame);
      return;
    }
    if (!_started) {
      setState(() {
        _started = true;
        _lastElapsed = Duration.zero;
      });
      return;
    }
    setState(() => _vy = -8.5);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      if (!_sizedReady &&
          constraints.maxWidth > 1 &&
          constraints.maxHeight > 1) {
        _w = constraints.maxWidth;
        _h = constraints.maxHeight;
        _sizedReady = true;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => setState(_initGame));
      }
      return GestureDetector(
        onTap: _onTap,
        child: ClipRect(
          child: CustomPaint(
            size: Size(_w, _h),
            painter: _FlappyPainter(
              birdY: _birdY,
              pipes: _pipes,
              pipeW: _pipeW,
              pipeGap: _pipeGap,
              score: _score,
              started: _started,
              dead: _dead,
              w: _w,
              h: _h,
            ),
          ),
        ),
      );
    });
  }
}

class _FlappyPainter extends CustomPainter {
  final double birdY, pipeW, pipeGap, w, h;
  final List<_FlappyPipe> pipes;
  final int score;
  final bool started, dead;

  static const double birdX = 90;
  static const double birdR = 13;

  _FlappyPainter({
    required this.birdY,
    required this.pipes,
    required this.pipeW,
    required this.pipeGap,
    required this.score,
    required this.started,
    required this.dead,
    required this.w,
    required this.h,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Sky
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4FC3F7), Color(0xFFB3E5FC)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), skyPaint);

    // Clouds (decorative)
    _drawCloud(canvas, w * 0.15, h * 0.18, 28);
    _drawCloud(canvas, w * 0.45, h * 0.12, 22);
    _drawCloud(canvas, w * 0.75, h * 0.22, 25);

    // Ground
    canvas.drawRect(Rect.fromLTWH(0, h - 18, w, 18),
        Paint()..color = const Color(0xFF8BC34A));
    canvas.drawRect(Rect.fromLTWH(0, h - 18, w, 5),
        Paint()..color = const Color(0xFF558B2F));

    // Pipes
    final pipeFill = Paint()..color = const Color(0xFF4CAF50);
    final pipeDark = Paint()..color = const Color(0xFF388E3C);
    final pipeLight = Paint()..color = const Color(0xFF81C784);
    for (final p in pipes) {
      // Top pipe body
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(p.x, 0, pipeW, p.gapTop), const Radius.circular(0)),
          pipeFill);
      // Top pipe cap
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(p.x - 4, p.gapTop - 16, pipeW + 8, 16),
              const Radius.circular(3)),
          pipeFill);
      // Shading
      canvas.drawRect(Rect.fromLTWH(p.x + 6, 0, 5, p.gapTop), pipeLight);
      canvas.drawRect(Rect.fromLTWH(p.x + pipeW - 6, 0, 4, p.gapTop), pipeDark);
      canvas.drawRect(
          Rect.fromLTWH(p.x + 6, p.gapTop - 16, 5, 16), pipeLight);

      // Bottom pipe body
      final bot = p.gapTop + pipeGap;
      canvas.drawRect(Rect.fromLTWH(p.x, bot, pipeW, h - bot), pipeFill);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(p.x - 4, bot, pipeW + 8, 16),
              const Radius.circular(3)),
          pipeFill);
      canvas.drawRect(Rect.fromLTWH(p.x + 6, bot, 5, h - bot), pipeLight);
      canvas.drawRect(
          Rect.fromLTWH(p.x + pipeW - 6, bot, 4, h - bot), pipeDark);
      canvas.drawRect(Rect.fromLTWH(p.x + 6, bot, 5, 16), pipeLight);
    }

    // Bird shadow
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(birdX, birdY + birdR + 3),
            width: birdR * 1.4,
            height: 5),
        Paint()..color = Colors.black.withOpacity(0.15));

    // Bird body
    canvas.drawCircle(
        Offset(birdX, birdY), birdR, Paint()..color = const Color(0xFFFFEB3B));
    canvas.drawCircle(
        Offset(birdX, birdY),
        birdR,
        Paint()
          ..color = const Color(0xFFF9A825)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Wing
    final wingPath = Path()
      ..moveTo(birdX - 2, birdY + 2)
      ..quadraticBezierTo(birdX - 12, birdY + 8, birdX - 8, birdY + 13)
      ..quadraticBezierTo(birdX - 2, birdY + 8, birdX + 4, birdY + 6)
      ..close();
    canvas.drawPath(wingPath, Paint()..color = const Color(0xFFFBC02D));

    // Eye white
    canvas.drawCircle(Offset(birdX + 4, birdY - 3), 4,
        Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(birdX + 5, birdY - 3), 2.2, Paint()..color = Colors.black);
    canvas.drawCircle(
        Offset(birdX + 5.7, birdY - 3.8), 0.8, Paint()..color = Colors.white);

    // Beak
    final beakPath = Path()
      ..moveTo(birdX + birdR - 1, birdY - 1)
      ..lineTo(birdX + birdR + 7, birdY + 2)
      ..lineTo(birdX + birdR - 1, birdY + 5)
      ..close();
    canvas.drawPath(beakPath, Paint()..color = const Color(0xFFFF9800));

    // Score
    _paintText(canvas, '$score', 28, Colors.white,
        Offset(w / 2, 20), bold: true, shadow: true);

    if (!started && !dead) {
      _paintText(canvas, '🐦 TAP TO START', 16, Colors.white,
          Offset(w / 2, h / 2 - 20), shadow: true);
      _paintText(canvas, 'Tap to flap!', 12, Colors.white70,
          Offset(w / 2, h / 2 + 4));
    }
    if (dead) {
      canvas.drawRect(
          Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.black45);
      _paintText(canvas, 'GAME OVER', 24, Colors.redAccent,
          Offset(w / 2, h / 2 - 24), bold: true, shadow: true);
      _paintText(canvas, 'Score: $score', 16, Colors.white,
          Offset(w / 2, h / 2 + 6), shadow: true);
      _paintText(canvas, 'Tap to retry', 13, Colors.white70,
          Offset(w / 2, h / 2 + 26));
    }
  }

  void _drawCloud(Canvas canvas, double x, double y, double r) {
    final p = Paint()..color = Colors.white.withOpacity(0.75);
    canvas.drawCircle(Offset(x, y), r, p);
    canvas.drawCircle(Offset(x + r * 0.8, y + r * 0.15), r * 0.75, p);
    canvas.drawCircle(Offset(x - r * 0.7, y + r * 0.2), r * 0.7, p);
    canvas.drawCircle(Offset(x + r * 0.15, y + r * 0.35), r * 0.65, p);
  }

  void _paintText(Canvas canvas, String text, double fontSize, Color color,
      Offset center,
      {bool bold = false, bool shadow = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: color,
          shadows: shadow
              ? [const Shadow(color: Colors.black54, blurRadius: 6)]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_FlappyPainter old) => true;
}

// ===========================================================================
// GAME 2: NOTE CATCHER
// ===========================================================================
class _FallingNote {
  double x, y;
  final int noteIndex;
  _FallingNote({required this.x, required this.y, required this.noteIndex});
}

class NoteCatcherGame extends StatefulWidget {
  const NoteCatcherGame({super.key});
  @override
  State<NoteCatcherGame> createState() => _NoteCatcherGameState();
}

class _NoteCatcherGameState extends State<NoteCatcherGame>
    with TickerProviderStateMixin {
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  double _w = 1, _h = 1;
  bool _sizedReady = false;

  double _catcherX = 200;
  static const double _catcherW = 72;
  static const double _catcherH = 12;
  static const double _noteR = 17;
  static const double _noteSpeed = 2.2;
  static const int _maxLives = 5;

  final List<_FallingNote> _notes = [];
  int _score = 0;
  int _lives = _maxLives;
  bool _started = false;
  bool _dead = false;

  Timer? _spawnTimer;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _startGame() {
    _spawnTimer?.cancel();
    setState(() {
      _notes.clear();
      _score = 0;
      _lives = _maxLives;
      _dead = false;
      _started = true;
    });
    _spawnTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted || _dead) return;
      setState(() {
        _notes.add(_FallingNote(
          x: _noteR + _rng.nextDouble() * (_w - _noteR * 2),
          y: -_noteR,
          noteIndex: _rng.nextInt(8),
        ));
      });
    });
  }

  void _onTick(Duration elapsed) {
    if (!_sizedReady || !_started || _dead) {
      _lastElapsed = elapsed;
      return;
    }
    final dtMs = (elapsed - _lastElapsed).inMilliseconds.clamp(0, 50);
    _lastElapsed = elapsed;
    final dt = dtMs / 16.0;

    setState(() {
      final catchTop = _h - 42;
      for (final n in _notes) {
        n.y += _noteSpeed * dt;
      }
      _notes.removeWhere((n) {
        // Catch?
        if (n.y + _noteR >= catchTop &&
            n.y - _noteR <= catchTop + _catcherH &&
            n.x > _catcherX - _catcherW / 2 - _noteR &&
            n.x < _catcherX + _catcherW / 2 + _noteR) {
          _score++;
          AudioService.instance.play(kNotes[n.noteIndex]);
          return true;
        }
        // Missed
        if (n.y > _h + _noteR) {
          _lives--;
          if (_lives <= 0) {
            _dead = true;
            _spawnTimer?.cancel();
          }
          return true;
        }
        return false;
      });
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _spawnTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      if (!_sizedReady &&
          constraints.maxWidth > 1 &&
          constraints.maxHeight > 1) {
        _w = constraints.maxWidth;
        _h = constraints.maxHeight;
        _catcherX = _w / 2;
        _sizedReady = true;
      }

      return GestureDetector(
        onHorizontalDragUpdate: (d) {
          if (!_started || _dead) return;
          setState(() {
            _catcherX =
                (_catcherX + d.delta.dx).clamp(_catcherW / 2, _w - _catcherW / 2);
          });
        },
        onTapDown: (_) {
          if (!_started || _dead) _startGame();
        },
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A237E), Color(0xFF283593)],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Stars
              CustomPaint(
                  size: Size(_w, _h),
                  painter: _StarfieldPainter(w: _w, h: _h)),

              // Falling notes
              for (final n in _notes) ...[
                Positioned(
                  left: n.x - _noteR,
                  top: n.y - _noteR,
                  child: Container(
                    width: _noteR * 2,
                    height: _noteR * 2,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          kNoteGradients[n.noteIndex][0],
                          kNoteGradients[n.noteIndex][1],
                        ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kNoteGradients[n.noteIndex][1].withOpacity(0.7),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        kNotes[n.noteIndex],
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // Ground line
              Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: Container(
                  height: 1,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),

              // Catcher
              Positioned(
                left: _catcherX - _catcherW / 2,
                top: _h - 42,
                child: Container(
                  width: _catcherW,
                  height: _catcherH,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF8BBD0), Color(0xFFF06292)],
                    ),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF06292).withOpacity(0.6),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),

              // HUD – score
              Positioned(
                top: 8,
                left: 12,
                child: _GameHudChip(
                    label: '✨  $_score', color: const Color(0xFFF8BBD0)),
              ),

              // HUD – lives
              Positioned(
                top: 8,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    _maxLives,
                    (i) => Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Icon(
                        i < _lives ? Icons.favorite : Icons.favorite_border,
                        color: const Color(0xFFF06292),
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),

              // Start overlay
              if (!_started)
                _GameOverlay(
                  title: '🎵 Note Catcher',
                  body: 'Drag to move the catcher\nCatch all the falling notes!',
                  buttonLabel: 'START',
                  onButton: _startGame,
                ),

              // Game over overlay
              if (_dead)
                _GameOverlay(
                  title: 'GAME OVER',
                  body: 'You caught  $_score  notes!',
                  buttonLabel: 'PLAY AGAIN',
                  onButton: _startGame,
                  isGameOver: true,
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _StarfieldPainter extends CustomPainter {
  final double w, h;
  _StarfieldPainter({required this.w, required this.h});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white54;
    final p2 = Paint()..color = Colors.white24;
    final positions = [
      [0.08, 0.1], [0.18, 0.4], [0.28, 0.15], [0.42, 0.55],
      [0.53, 0.08], [0.61, 0.35], [0.72, 0.62], [0.82, 0.2],
      [0.9, 0.48], [0.95, 0.12], [0.35, 0.7], [0.65, 0.8],
      [0.15, 0.65], [0.5, 0.3], [0.78, 0.85],
    ];
    for (int i = 0; i < positions.length; i++) {
      final x = positions[i][0] * w;
      final y = positions[i][1] * h;
      canvas.drawCircle(Offset(x, y), i.isEven ? 1.5 : 1.0, i % 3 == 0 ? p2 : p);
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) => false;
}

// ===========================================================================
// GAME 3: MEMORY MATCH
// ===========================================================================
class MemoryMatchGame extends StatefulWidget {
  const MemoryMatchGame({super.key});
  @override
  State<MemoryMatchGame> createState() => _MemoryMatchGameState();
}

class _MemoryMatchGameState extends State<MemoryMatchGame> {
  static const int _pairs = 8;
  late List<int> _cards;
  late List<bool> _faceUp;
  late List<bool> _matched;
  int? _first;
  bool _checking = false;
  int _moves = 0;
  int _matches = 0;
  bool _won = false;
  Stopwatch _sw = Stopwatch();
  Timer? _timer;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  void _newGame() {
    final deck = [...List.generate(_pairs, (i) => i), ...List.generate(_pairs, (i) => i)];
    deck.shuffle(Random());
    _timer?.cancel();
    _sw = Stopwatch()..start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed = _sw.elapsed.inSeconds);
    });
    setState(() {
      _cards = deck;
      _faceUp = List.filled(_pairs * 2, false);
      _matched = List.filled(_pairs * 2, false);
      _first = null;
      _checking = false;
      _moves = 0;
      _matches = 0;
      _won = false;
      _elapsed = 0;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sw.stop();
    super.dispose();
  }

  void _onCardTap(int i) {
    if (_checking || _faceUp[i] || _matched[i] || _won) return;
    setState(() => _faceUp[i] = true);

    if (_first == null) {
      _first = i;
    } else {
      final first = _first!;
      _first = null;
      _checking = true;
      _moves++;
      Future.delayed(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        setState(() {
          if (_cards[first] == _cards[i]) {
            _matched[first] = true;
            _matched[i] = true;
            _matches++;
            AudioService.instance.play(kNotes[_cards[first]]);
            if (_matches == _pairs) {
              _won = true;
              _sw.stop();
              _timer?.cancel();
            }
          } else {
            _faceUp[first] = false;
            _faceUp[i] = false;
          }
          _checking = false;
        });
      });
    }
  }

  String _fmtTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8F5E9), Color(0xFFF9FBE7)],
        ),
      ),
      child: Column(
        children: [
          // HUD bar
          Container(
            height: 38,
            margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.green.withOpacity(0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Row(
              children: [
                _GameHudChip(label: '🃏 Moves: $_moves', color: const Color(0xFFC8E6C9)),
                const SizedBox(width: 8),
                _GameHudChip(
                    label: '✅ $_matches / $_pairs',
                    color: const Color(0xFFA5D6A7)),
                const SizedBox(width: 8),
                _GameHudChip(label: '⏱ ${_fmtTime(_elapsed)}', color: const Color(0xFFFFF9C4)),
                const Spacer(),
                GestureDetector(
                  onTap: _newGame,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 13, color: Colors.white),
                        SizedBox(width: 4),
                        Text('New Game',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Card grid
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Stack(
                children: [
                  LayoutBuilder(builder: (_, constraints) {
                    final cardW =
                        (constraints.maxWidth - 7 * 6) / 8; // 8 cols
                    final cardH =
                        (constraints.maxHeight - 6) / 2; // 2 rows
                    final ar = cardW / cardH.clamp(0.01, double.infinity);
                    return GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 8,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                        childAspectRatio: ar,
                      ),
                      itemCount: 16,
                      itemBuilder: (_, i) => _buildCard(i),
                    );
                  }),
                  if (_won)
                    _GameOverlay(
                      title: '🎉 You Won!',
                      body:
                          '$_moves moves  •  ${_fmtTime(_elapsed)}',
                      buttonLabel: 'PLAY AGAIN',
                      onButton: _newGame,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(int i) {
    final up = _faceUp[i] || _matched[i];
    final noteIdx = _cards[i];
    final colors = kNoteGradients[noteIdx];
    final isMatched = _matched[i];

    return GestureDetector(
      onTap: () => _onCardTap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: up
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors)
              : const LinearGradient(colors: [Color(0xFF5C6BC0), Color(0xFF3949AB)]),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: up
                  ? colors[1].withOpacity(isMatched ? 0.5 : 0.3)
                  : Colors.indigo.withOpacity(0.3),
              blurRadius: isMatched ? 10 : 5,
              offset: const Offset(0, 3),
            ),
          ],
          border: isMatched
              ? Border.all(color: Colors.green.shade400, width: 2)
              : Border.all(
                  color: Colors.white.withOpacity(up ? 0.5 : 0.25),
                  width: 1),
        ),
        child: Center(
          child: up
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kNotes[noteIdx],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF4A148C),
                        height: 1,
                      ),
                    ),
                    Text(
                      kNoteSymbols[noteIdx],
                      style: TextStyle(
                          fontSize: 9,
                          color: const Color(0xFF6A1B9A).withOpacity(0.7)),
                    ),
                  ],
                )
              : Text(
                  '?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
        ),
      ),
    );
  }
}

// ===========================================================================
// GAME 4: RHYTHM TAP
// ===========================================================================
class _RhythmNoteObj {
  double x;
  final double y;
  final int noteIndex;
  bool hit = false;
  double fadeOut = 1.0;
  _RhythmNoteObj({required this.x, required this.y, required this.noteIndex});
}

class _HitFeedback {
  double x, y;
  String label;
  Color color;
  double age = 0;
  _HitFeedback({
    required this.x,
    required this.y,
    required this.label,
    required this.color,
  });
}

class RhythmTapGame extends StatefulWidget {
  const RhythmTapGame({super.key});
  @override
  State<RhythmTapGame> createState() => _RhythmTapGameState();
}

class _RhythmTapGameState extends State<RhythmTapGame>
    with TickerProviderStateMixin {
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  double _w = 1, _h = 1;
  bool _sizedReady = false;

  static const double _noteR = 18;
  static const double _noteSpeed = 2.8;
  static const double _hitX = 68.0;
  static const double _hitR = 24.0;
  static const double _perfectW = 18.0;
  static const double _goodW = 38.0;

  // 3 lanes
  static const int _numLanes = 3;
  final List<_RhythmNoteObj> _notes = [];
  final List<_HitFeedback> _feedbacks = [];

  int _score = 0;
  int _combo = 0;
  int _perfect = 0, _good = 0, _miss = 0;
  bool _started = false;
  bool _done = false;
  int _notesLeft = 0;

  Timer? _spawnTimer;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  List<double> get _laneYs => List.generate(
      _numLanes, (i) => _h * (0.2 + 0.3 * i + 0.15));

  void _startGame() {
    _spawnTimer?.cancel();
    setState(() {
      _notes.clear();
      _feedbacks.clear();
      _score = 0;
      _combo = 0;
      _perfect = 0;
      _good = 0;
      _miss = 0;
      _done = false;
      _started = true;
      _notesLeft = 24;
    });

    int spawned = 0;
    _spawnTimer = Timer.periodic(const Duration(milliseconds: 1100), (t) {
      if (!mounted || _done) {
        t.cancel();
        return;
      }
      final lane = _rng.nextInt(_numLanes);
      final laneY = _laneYs[lane];
      setState(() {
        _notes.add(_RhythmNoteObj(
          x: _w + _noteR,
          y: laneY,
          noteIndex: _rng.nextInt(8),
        ));
        _notesLeft--;
      });
      spawned++;
      if (spawned >= 24) t.cancel();
    });
  }

  void _onTick(Duration elapsed) {
    if (!_sizedReady || !_started || _done) {
      _lastElapsed = elapsed;
      return;
    }
    final dtMs = (elapsed - _lastElapsed).inMilliseconds.clamp(0, 50);
    _lastElapsed = elapsed;
    final dt = dtMs / 16.0;

    setState(() {
      for (final n in _notes) {
        if (!n.hit) n.x -= _noteSpeed * dt;
        if (n.hit) n.fadeOut -= 0.08 * dt;
      }
      // Miss notes that passed the hit zone
      _notes.removeWhere((n) {
        if (!n.hit && n.x < _hitX - _goodW - _noteR) {
          _miss++;
          _combo = 0;
          _feedbacks.add(_HitFeedback(
            x: _hitX, y: n.y, label: 'MISS', color: Colors.red.shade300));
          return true;
        }
        if (n.hit && n.fadeOut <= 0) return true;
        if (n.x < -_noteR * 3) return true;
        return false;
      });
      // Fade feedbacks
      for (final f in _feedbacks) {
        f.age += 0.04 * dt;
      }
      _feedbacks.removeWhere((f) => f.age >= 1.0);
      // Check done
      if (_notesLeft <= 0 && _notes.isEmpty && !_done) {
        _done = true;
        _spawnTimer?.cancel();
      }
    });
  }

  void _onTapLane(int lane) {
    if (!_started || _done) {
      _startGame();
      return;
    }
    final laneY = _laneYs[lane];
    // Find closest note in this lane
    _RhythmNoteObj? best;
    double bestDist = double.infinity;
    for (final n in _notes) {
      if (n.hit) continue;
      if ((n.y - laneY).abs() > 30) continue;
      final dist = (n.x - _hitX).abs();
      if (dist < _goodW + _noteR && dist < bestDist) {
        bestDist = dist;
        best = n;
      }
    }
    if (best == null) return;

    best.hit = true;
    final dist = (best.x - _hitX).abs();
    String label;
    Color color;
    int pts;
    if (dist < _perfectW) {
      label = '✨ PERFECT';
      color = Colors.amber;
      pts = 100;
      _perfect++;
    } else {
      label = '👍 GOOD';
      color = Colors.greenAccent;
      pts = 50;
      _good++;
    }
    _combo++;
    final bonus = _combo > 3 ? 2 : 1;
    setState(() {
      _score += pts * bonus;
      _feedbacks.add(_HitFeedback(
          x: best!.x, y: best.y, label: label, color: color));
    });
    AudioService.instance.play(kNotes[best.noteIndex]);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _spawnTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      if (!_sizedReady &&
          constraints.maxWidth > 1 &&
          constraints.maxHeight > 1) {
        _w = constraints.maxWidth;
        _h = constraints.maxHeight;
        _sizedReady = true;
      }
      final laneYs = _sizedReady ? _laneYs : [_h * 0.35, _h * 0.65, _h * 0.85];

      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF212121), Color(0xFF37474F)],
          ),
        ),
        child: Stack(
          children: [
            // Track painter (hit zone + lanes + notes)
            CustomPaint(
              size: Size(_w, _h),
              painter: _RhythmPainter(
                notes: _notes,
                feedbacks: _feedbacks,
                laneYs: laneYs,
                hitX: _hitX,
                hitR: _hitR,
                noteR: _noteR,
                w: _w,
                h: _h,
              ),
            ),

            // Lane tap targets (invisible but tappable)
            for (int lane = 0; lane < _numLanes; lane++)
              Positioned(
                left: 0,
                top: laneYs[lane] - _h * 0.13,
                right: 0,
                height: _h * 0.26,
                child: GestureDetector(
                  onTapDown: (_) => _onTapLane(lane),
                  behavior: HitTestBehavior.translucent,
                  child: Container(color: Colors.transparent),
                ),
              ),

            // HUD
            Positioned(
              top: 8,
              left: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GameHudChip(
                      label: '  $_score pts',
                      color: const Color(0xFFFFE0B2)),
                  if (_combo > 1) ...[
                    const SizedBox(height: 4),
                    _GameHudChip(
                        label: '🔥 ×$_combo combo',
                        color: Colors.orange.shade100),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _GameHudChip(
                      label: '✨ $_perfect',
                      color: Colors.amber.shade100),
                  const SizedBox(height: 3),
                  _GameHudChip(
                      label: '👍 $_good',
                      color: Colors.green.shade100),
                  const SizedBox(height: 3),
                  _GameHudChip(
                      label: '💔 $_miss',
                      color: Colors.red.shade100),
                ],
              ),
            ),

            // Lane labels on left
            for (int lane = 0; lane < _numLanes; lane++)
              Positioned(
                left: 8,
                top: laneYs[lane] - 8,
                child: Text(
                  'Lane ${lane + 1}',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.white.withOpacity(0.3),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            if (!_started)
              _GameOverlay(
                title: '🥁 Rhythm Tap',
                body: 'Tap a lane when a note hits\nthe glowing circle!',
                buttonLabel: 'START',
                onButton: _startGame,
              ),

            if (_done)
              _GameOverlay(
                title: '🎶 Done!',
                body: 'Score: $_score\n✨$_perfect   👍$_good   💔$_miss',
                buttonLabel: 'PLAY AGAIN',
                onButton: _startGame,
              ),
          ],
        ),
      );
    });
  }
}

class _RhythmPainter extends CustomPainter {
  final List<_RhythmNoteObj> notes;
  final List<_HitFeedback> feedbacks;
  final List<double> laneYs;
  final double hitX, hitR, noteR, w, h;

  _RhythmPainter({
    required this.notes,
    required this.feedbacks,
    required this.laneYs,
    required this.hitX,
    required this.hitR,
    required this.noteR,
    required this.w,
    required this.h,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Lane tracks
    for (final y in laneYs) {
      final dashPaint = Paint()
        ..color = Colors.white.withOpacity(0.06)
        ..strokeWidth = 1;
      double x = hitX + hitR;
      while (x < w) {
        canvas.drawLine(Offset(x, y), Offset(x + 14, y), dashPaint);
        x += 22;
      }
    }

    // Hit zones per lane
    for (final y in laneYs) {
      // Glow
      canvas.drawCircle(
          Offset(hitX, y),
          hitR * 1.8,
          Paint()
            ..color = const Color(0xFFFF9800).withOpacity(0.15)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
      // Ring
      canvas.drawCircle(
          Offset(hitX, y),
          hitR,
          Paint()
            ..color = const Color(0xFFFF9800)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
      // Fill
      canvas.drawCircle(
          Offset(hitX, y),
          hitR,
          Paint()..color = const Color(0xFFFF9800).withOpacity(0.12));
    }

    // Notes
    for (final n in notes) {
      final opacity = n.hit ? n.fadeOut.clamp(0.0, 1.0) : 1.0;
      if (opacity <= 0) continue;
      final colors = kNoteGradients[n.noteIndex];

      // Glow
      canvas.drawCircle(
          Offset(n.x, n.y),
          noteR + 5,
          Paint()
            ..color = colors[1].withOpacity(0.25 * opacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

      // Body gradient
      final gradient =
          RadialGradient(colors: [colors[0], colors[1]]);
      canvas.drawCircle(
          Offset(n.x, n.y),
          noteR,
          Paint()
            ..shader = gradient.createShader(
                Rect.fromCircle(center: Offset(n.x, n.y), radius: noteR))
            ..color = colors[0].withOpacity(opacity));

      // Border
      canvas.drawCircle(
          Offset(n.x, n.y),
          noteR,
          Paint()
            ..color = colors[1].withOpacity(0.7 * opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);

      // Label
      if (!n.hit) {
        final tp = TextPainter(
          text: TextSpan(
            text: kNotes[n.noteIndex],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A237E).withOpacity(opacity),
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas,
            Offset(n.x - tp.width / 2, n.y - tp.height / 2));
      }
    }

    // Hit feedbacks
    for (final f in feedbacks) {
      final alpha = (1.0 - f.age).clamp(0.0, 1.0);
      final yOff = -f.age * 30;
      final tp = TextPainter(
        text: TextSpan(
          text: f.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: f.color.withOpacity(alpha),
            shadows: [
              Shadow(
                  color: Colors.black.withOpacity(0.5 * alpha),
                  blurRadius: 6)
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(f.x - tp.width / 2, f.y - 10 + yOff));
    }
  }

  @override
  bool shouldRepaint(_RhythmPainter old) => true;
}

// ===========================================================================
// SHARED GAME WIDGETS
// ===========================================================================
class _GameHudChip extends StatelessWidget {
  final String label;
  final Color color;
  const _GameHudChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 4,
              offset: const Offset(0, 1))
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A237E),
        ),
      ),
    );
  }
}

class _GameOverlay extends StatelessWidget {
  final String title, body, buttonLabel;
  final VoidCallback onButton;
  final bool isGameOver;

  const _GameOverlay({
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.onButton,
    this.isGameOver = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.62),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E).withOpacity(0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.white.withOpacity(0.12), width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 4)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isGameOver ? Colors.redAccent : Colors.white,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 8)
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: Colors.white60, height: 1.5),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onButton,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  elevation: 4,
                ),
                child: Text(
                  buttonLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
