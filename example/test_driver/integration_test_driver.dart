import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (Map<String, dynamic>? data) async {
        if (data == null) return;
        final outFile = File('${Directory.current.path}/benchmarks/reports/elpian_raw_results.json');
        await outFile.parent.create(recursive: true);
        await outFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(data),
        );
        stdout.writeln('[DRIVER] Results written to ${outFile.path}');
      },
    );
