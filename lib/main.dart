import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MadouNfoApp());
}

class MadouNfoApp extends StatelessWidget {
  const MadouNfoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Madou NFO',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _queryController = TextEditingController();
  final _nfoNameController = TextEditingController();
  final _service = MadouquService();
  bool _loading = false;
  bool _downloadCover = true;
  String _status = '请输入视频名或番号后点击生成';
  VideoMetadata? _lastMeta;
  String? _lastPath;

  Future<void> _generate() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() => _status = '请输入视频名或番号');
      return;
    }

    setState(() {
      _loading = true;
      _status = '正在搜索并抓取...';
    });

    try {
      final metadata = await _service.fetchMetadata(query);
      final outputDir = await _resolveOutputDir();
      final customNfo = _nfoNameController.text.trim();
      final nfoName = customNfo.isEmpty ? '${_safeName(metadata.code.isNotEmpty ? metadata.code : metadata.title)}.nfo' : customNfo;
      final nfoFile = File('${outputDir.path}/$nfoName');
      await nfoFile.writeAsString(buildNfo(metadata), encoding: utf8);

      if (_downloadCover && metadata.coverUrl.isNotEmpty) {
        await _service.downloadCoverWithFallback(metadata.coverUrl, File('${outputDir.path}/poster.jpg'));
      }

      setState(() {
        _lastMeta = metadata;
        _lastPath = nfoFile.path;
        _status = '完成：${nfoFile.path}';
      });
    } catch (e) {
      setState(() => _status = '失败：$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<Directory> _resolveOutputDir() async {
    final external = await getExternalStorageDirectory();
    if (external != null) {
      final dir = Directory('${external.path}/nfo_output');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    final internal = await getApplicationDocumentsDirectory();
    final dir = Directory('${internal.path}/nfo_output');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Madou NFO 生成器')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _queryController,
              decoration: const InputDecoration(
                labelText: '视频名或番号',
                hintText: '例如：MD-0382',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nfoNameController,
              decoration: const InputDecoration(
                labelText: 'NFO 文件名（可选）',
                hintText: '例如：movie.nfo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('同时下载封面 poster.jpg'),
              value: _downloadCover,
              onChanged: _loading ? null : (v) => setState(() => _downloadCover = v),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loading ? null : _generate,
              child: Text(_loading ? '处理中...' : '生成 NFO'),
            ),
            const SizedBox(height: 16),
            SelectableText(_status),
            if (_lastPath != null) ...[
              const SizedBox(height: 8),
              SelectableText('输出路径：$_lastPath'),
            ],
            if (_lastMeta != null) ...[
              const SizedBox(height: 16),
              Text('标题：${_lastMeta!.title}'),
              Text('演员：${_lastMeta!.actors.join(", ")}'),
              Text('封面：${_lastMeta!.coverUrl}'),
              Text('来源：${_lastMeta!.sourceUrl}'),
            ],
          ],
        ),
      ),
    );
  }
}

class MadouquService {
  static const _base = 'https://madouqu.com';
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  Future<VideoMetadata> fetchMetadata(String query) async {
    final searchUri = Uri.parse('$_base/?s=${Uri.encodeQueryComponent(query)}');
    final searchResp = await http.get(searchUri, headers: _headers);
    if (searchResp.statusCode != 200) {
      throw Exception('搜索失败：HTTP ${searchResp.statusCode}');
    }

    final searchDoc = html_parser.parse(utf8.decode(searchResp.bodyBytes));
    final items = searchDoc.querySelectorAll('h2.entry-title a');
    if (items.isEmpty) {
      throw Exception('没有搜索到结果');
    }

    final candidate = _pickBestCandidate(query, items.map((e) {
      final href = e.attributes['href'] ?? '';
      final title = e.text.trim();
      return SearchCandidate(title: title, url: href);
    }).where((e) => e.url.isNotEmpty).toList());

    final detailResp = await http.get(Uri.parse(candidate.url), headers: _headers);
    if (detailResp.statusCode != 200) {
      throw Exception('详情页获取失败：HTTP ${detailResp.statusCode}');
    }
    return _parseDetail(utf8.decode(detailResp.bodyBytes), candidate.url);
  }

  Future<void> downloadCoverWithFallback(String url, File target) async {
    final candidates = _buildCoverFallbackUrls(url);
    Object? lastErr;
    for (final item in candidates) {
      try {
        final resp = await http.get(Uri.parse(item), headers: _headers);
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          await target.writeAsBytes(resp.bodyBytes);
          return;
        }
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('封面下载失败: ${lastErr ?? "全部地址返回非200"}');
  }

  List<String> _buildCoverFallbackUrls(String url) {
    final out = <String>[url];
    final uri = Uri.parse(url);
    final q = Map<String, String>.from(uri.queryParameters);
    q.remove('resize');
    q.remove('fit');
    q.remove('x-oss-process');
    final cleaned = uri.replace(queryParameters: q.isEmpty ? null : q).toString();
    if (!out.contains(cleaned)) out.add(cleaned);
    final noQuery = uri.replace(query: '').toString();
    if (!out.contains(noQuery)) out.add(noQuery);
    if (uri.host.endsWith('wp.com') && uri.path.startsWith('/madouqu.com/')) {
      final origin = Uri.parse('https://madouqu.com/${uri.path.substring('/madouqu.com/'.length)}').toString();
      if (!out.contains(origin)) out.add(origin);
    }
    return out;
  }

  VideoMetadata _parseDetail(String html, String sourceUrl) {
    final doc = html_parser.parse(html);
    final title = doc.querySelector('h1.entry-title')?.text.trim() ?? '';
    final datetime = doc.querySelector('span.meta-date time')?.attributes['datetime'] ?? '';
    final premiered = datetime.contains('T') ? datetime.split('T').first : datetime;
    final studio = doc.querySelector('span.meta-category a')?.text.trim() ?? '麻豆区';

    final content = doc.querySelector('div.entry-content');
    final coverUrl = content?.querySelector('img')?.attributes['src']?.trim() ?? '';

    String code = '';
    String name = '';
    String actressLine = '';
    final pList = content?.querySelectorAll('p') ?? const [];
    for (final p in pList) {
      final t = p.text.trim();
      if (t.startsWith('麻豆番号：') || t.startsWith('麻豆番号:')) {
        code = t.split(RegExp(r'[：:]')).skip(1).join(':').trim().replaceAll(RegExp(r'\s+'), '');
      } else if (t.startsWith('麻豆片名：') || t.startsWith('麻豆片名:')) {
        name = t.split(RegExp(r'[：:]')).skip(1).join(':').trim();
      } else if (t.startsWith('麻豆女郎：') || t.startsWith('麻豆女郎:')) {
        actressLine = t.split(RegExp(r'[：:]')).skip(1).join(':').trim();
      }
    }

    if (code.isEmpty) {
      final m = RegExp(r'^([A-Za-z]{2,5}-?\d{2,5})').firstMatch(title);
      code = m?.group(1)?.toUpperCase() ?? '';
    }
    if (name.isEmpty) {
      name = title;
    }

    final tags = (doc.querySelectorAll('div.entry-tags a').map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList());
    final actors = <String>[];
    if (actressLine.isNotEmpty) {
      for (final x in actressLine.split(RegExp(r'[、,，/\s]+'))) {
        if (x.isNotEmpty && !actors.contains(x)) actors.add(x);
      }
    }
    for (final t in tags) {
      if (!actors.contains(t)) actors.add(t);
    }

    return VideoMetadata(
      title: title,
      originalTitle: title,
      code: code,
      studio: studio,
      premiered: premiered,
      coverUrl: coverUrl,
      actors: actors,
      tags: tags,
      sourceUrl: sourceUrl,
      plot: code.isNotEmpty ? '$code $name' : name,
    );
  }

  SearchCandidate _pickBestCandidate(String query, List<SearchCandidate> candidates) {
    final q = _norm(query);
    SearchCandidate best = candidates.first;
    var bestScore = -1 << 30;
    for (final c in candidates) {
      final t = _norm(c.title);
      var score = 0;
      if (t == q) score += 100;
      if (t.contains(q)) score += 50;
      if (q.contains(t) && t.isNotEmpty) score += 20;
      score -= (t.length - q.length).abs();
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');
}

class SearchCandidate {
  final String title;
  final String url;
  SearchCandidate({required this.title, required this.url});
}

class VideoMetadata {
  final String title;
  final String originalTitle;
  final String code;
  final String studio;
  final String premiered;
  final String coverUrl;
  final List<String> actors;
  final List<String> tags;
  final String sourceUrl;
  final String plot;

  VideoMetadata({
    required this.title,
    required this.originalTitle,
    required this.code,
    required this.studio,
    required this.premiered,
    required this.coverUrl,
    required this.actors,
    required this.tags,
    required this.sourceUrl,
    required this.plot,
  });
}

String buildNfo(VideoMetadata m) {
  final b = StringBuffer();
  b.writeln("<?xml version='1.0' encoding='utf-8'?>");
  b.writeln('<movie>');
  b.writeln('  <title>${_xml(m.title)}</title>');
  b.writeln('  <originaltitle>${_xml(m.originalTitle)}</originaltitle>');
  b.writeln('  <sorttitle>${_xml(m.code.isNotEmpty ? m.code : m.title)}</sorttitle>');
  b.writeln('  <plot>${_xml(m.plot)}</plot>');
  b.writeln('  <studio>${_xml(m.studio)}</studio>');
  b.writeln('  <premiered>${_xml(m.premiered)}</premiered>');
  b.writeln('  <year>${_xml(m.premiered.length >= 4 ? m.premiered.substring(0, 4) : "")}</year>');
  b.writeln('  <id>${_xml(m.code)}</id>');
  b.writeln('  <num>${_xml(m.code)}</num>');
  b.writeln('  <thumb>${_xml(m.coverUrl)}</thumb>');
  b.writeln('  <source>${_xml(m.sourceUrl)}</source>');
  for (final t in m.tags) {
    b.writeln('  <tag>${_xml(t)}</tag>');
  }
  if (m.studio.isNotEmpty) {
    b.writeln('  <genre>${_xml(m.studio)}</genre>');
  }
  for (final a in m.actors) {
    b.writeln('  <actor>');
    b.writeln('    <name>${_xml(a)}</name>');
    b.writeln('    <type>Actor</type>');
    b.writeln('  </actor>');
  }
  b.writeln('</movie>');
  return b.toString();
}

String _xml(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _safeName(String input) => input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
