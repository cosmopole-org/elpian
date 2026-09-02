// A developer smoke tool: it drives a headless browser and reports what it
// found on stdout. `avoid_print` does not apply here.
// ignore_for_file: avoid_print
import 'package:puppeteer/puppeteer.dart';

Future<void> main(List<String> args) async {
  final url = args.isEmpty ? 'http://127.0.0.1:4173' : args.first;
  final chrome = await downloadChrome(cachePath: puppeteer.userCachePath);
  final browser = await puppeteer.launch(
    executablePath: chrome.executablePath,
    headless: true,
    noSandboxFlag: true,
  );
  final page = await browser.newPage();
  page.onConsole.listen((event) => print('console ${event.type.name}: ${event.text}'));
  page.onResponse.listen((response) {
    if (response.status >= 400) print('http ${response.status}: ${response.url}');
  });
  final response = await page.goto(url, wait: Until.networkIdle);
  await Future<void>.delayed(const Duration(seconds: 3));
  print('document: ${response.status} ${page.url}');
  print('body: ${(await page.evaluate<String>('document.body.innerText')).trim()}');
  await browser.close();
}
