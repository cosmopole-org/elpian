// demo_app.dart — a realistic, interactive Flutter app built entirely on the
// imported flutter.dart library. It uses StatelessWidget + StatefulWidget,
// custom reusable components, MaterialApp/Scaffold/AppBar, Cards, Rows/Columns
// with alignment, Expanded, an ElevatedButton pair, a live progress bar, and
// string interpolation with expressions — the sort of screen you'd actually
// write in Flutter. Tapping the +/- buttons runs setState and repaints.

import 'flutter.dart';

void main() => runApp(DashboardApp());

/// The application root: a Material app with a themed Scaffold + AppBar.
class DashboardApp extends StatelessWidget {
  const DashboardApp();

  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elpian Dashboard',
      home: Scaffold(
        backgroundColor: Color(0xFF12141C),
        appBar: AppBar(
          backgroundColor: Colors.indigo,
          title: Text(
            'Elpian Dashboard',
            style: TextStyle(fontSize: 22.0, color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: Padding(padding: EdgeInsets.all(16.0), child: CounterPanel()),
      ),
    );
  }
}

/// The interactive panel: a counter with +/- controls, a progress bar that
/// tracks the count, and a row of derived stat chips.
class CounterPanel extends StatefulWidget {
  State createState() => CounterPanelState();
}

class CounterPanelState extends State {
  int count = 0;

  void increment() {
    setState(() { count = count + 1; });
  }

  void decrement() {
    setState(() { if (count > 0) { count = count - 1; } });
  }

  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _counterCard(),
        SizedBox(height: 16.0),
        Text('Progress', style: TextStyle(fontSize: 14.0, color: Colors.grey)),
        SizedBox(height: 6.0),
        _progressBar(),
        SizedBox(height: 20.0),
        _statRow(),
      ],
    );
  }

  Widget _counterCard() {
    return Card(
      color: Color(0xFF1E2230),
      child: Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text('COUNTER', style: TextStyle(fontSize: 14.0, color: Colors.grey)),
            SizedBox(height: 8.0),
            Text('$count',
                style: TextStyle(fontSize: 52.0, color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(height: 18.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  color: Colors.red,
                  onPressed: () { decrement(); },
                  child: Text('-', style: TextStyle(fontSize: 26.0, color: Colors.white)),
                ),
                ElevatedButton(
                  color: Colors.green,
                  onPressed: () { increment(); },
                  child: Text('+', style: TextStyle(fontSize: 26.0, color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressBar() {
    return Container(
      height: 26.0,
      color: Color(0xFF2A2E3E),
      child: Align(
        alignment: Alignment.centerLeft(),
        child: Container(width: 8.0 + count * 22.0, height: 26.0, color: Colors.cyan),
      ),
    );
  }

  Widget _statRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        StatChip(label: 'TAPS', value: '$count', color: Colors.amber),
        StatChip(label: 'DOUBLE', value: '${count * 2}', color: Colors.teal),
        StatChip(label: 'SQUARE', value: '${count * count}', color: Colors.pink),
      ],
    );
  }
}

/// A small reusable stat card: a big value over a label, on a colored tile.
class StatChip extends StatelessWidget {
  var label;
  var value;
  var color;
  StatChip({this.label, this.value, this.color});

  Widget build(BuildContext context) {
    return Container(
      width: 100.0,
      color: color,
      padding: EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(fontSize: 24.0, color: Colors.black, fontWeight: FontWeight.bold)),
          SizedBox(height: 2.0),
          Text(label, style: TextStyle(fontSize: 11.0, color: Colors.black)),
        ],
      ),
    );
  }
}
