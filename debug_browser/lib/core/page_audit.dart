import 'package:flutter/foundation.dart';

/// One checked item in the audit report.
@immutable
class AuditCheck {
  final String title;
  final bool passed;
  final String? detail;

  /// Points removed from the category score when it fails.
  final int weight;
  const AuditCheck(this.title, this.passed, {this.detail, this.weight = 10});
}

@immutable
class AuditCategory {
  final String name;
  final int score; // 0..100
  final List<AuditCheck> checks;
  const AuditCategory(this.name, this.score, this.checks);
}

int _scoreFrom(List<AuditCheck> checks) {
  final lost = checks.where((c) => !c.passed).fold<int>(0, (a, c) => a + c.weight);
  return (100 - lost).clamp(0, 100);
}

/// Score for a timing metric: 100 at/below [good], 0 at/above [poor].
int metricScore(num? value, num good, num poor) {
  if (value == null) return 100;
  if (value <= good) return 100;
  if (value >= poor) return 0;
  return (100 * (poor - value) / (poor - good)).round();
}

/// Builds the four Lighthouse-style categories from what the page reported.
List<AuditCategory> scorePage({
  required Map<String, dynamic> seo,
  Map<String, dynamic>? vitals,
  Map<String, dynamic>? a11y,
  int consoleErrors = 0,
}) {
  num? v(String k) => (vitals?['vitals'] as Map?)?[k] as num?;
  final resources = vitals?['resources'] as Map?;
  final totalBytes = (resources?['totalBytes'] as num?) ?? 0;
  final reqCount = (resources?['count'] as num?) ?? 0;

  // Performance: weighted metric scores (Lighthouse-like weights).
  final perfParts = <(String, int, int, String)>[
    ('Largest Contentful Paint', metricScore(v('lcp'), 2500, 4000), 30, v('lcp') == null ? 'not measured' : '${v('lcp')} ms'),
    ('Cumulative Layout Shift', metricScore(v('cls'), 0.1, 0.25), 25, '${v('cls') ?? 'not measured'}'),
    ('First Contentful Paint', metricScore(v('fcp'), 1800, 3000), 15, v('fcp') == null ? 'not measured' : '${v('fcp')} ms'),
    ('Time to First Byte', metricScore(v('ttfb'), 800, 1800), 15, v('ttfb') == null ? 'not measured' : '${v('ttfb')} ms'),
    ('Page weight', metricScore(totalBytes / 1024, 1600, 6000), 15,
        '${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB in $reqCount requests'),
  ];
  final perfScore = (perfParts.fold<int>(0, (a, p) => a + p.$2 * p.$3) / 100).round();
  final perfChecks = [for (final p in perfParts) AuditCheck(p.$1, p.$2 >= 90, detail: p.$4, weight: 0)];

  // Accessibility: penalties by severity from the a11y audit.
  final counts = (a11y?['counts'] as Map?) ?? const {};
  int c(String k) => (counts[k] as num?)?.toInt() ?? 0;
  final a11yChecks = [
    AuditCheck('No critical issues', c('critical') == 0, detail: '${c('critical')} found', weight: (c('critical') * 8).clamp(0, 40)),
    AuditCheck('No serious issues', c('serious') == 0, detail: '${c('serious')} found', weight: (c('serious') * 4).clamp(0, 30)),
    AuditCheck('No moderate issues', c('moderate') == 0, detail: '${c('moderate')} found', weight: (c('moderate') * 2).clamp(0, 20)),
    AuditCheck('No minor issues', c('minor') == 0, detail: '${c('minor')} found', weight: c('minor').clamp(0, 10)),
  ];

  // SEO.
  final title = '${seo['title'] ?? ''}';
  final desc = '${seo['description'] ?? ''}';
  int n(String k) => (seo[k] as num?)?.toInt() ?? 0;
  final seoChecks = [
    AuditCheck('Has a title', title.isNotEmpty, detail: title.isEmpty ? null : '${title.length} characters', weight: 20),
    AuditCheck('Title is a good length (10–70)', title.length >= 10 && title.length <= 70, weight: 5),
    AuditCheck('Has a meta description', desc.isNotEmpty, weight: 15),
    AuditCheck('Exactly one <h1>', n('h1Count') == 1, detail: '${n('h1Count')} found', weight: 10),
    AuditCheck('Mobile viewport set', '${seo['viewport']}'.contains('width'), weight: 15),
    AuditCheck('Page language declared', '${seo['lang']}'.isNotEmpty, weight: 5),
    AuditCheck('Not blocked from search engines', seo['noindex'] != true, weight: 25),
    AuditCheck('Canonical URL', seo['canonical'] == true, weight: 5),
    AuditCheck('Images have alt text', n('imagesMissingAlt') == 0, detail: '${n('imagesMissingAlt')} of ${n('images')} missing', weight: 10),
    AuditCheck('Descriptive link text', n('genericLinks') == 0, detail: '${n('genericLinks')} "click here"-style links', weight: 5),
    AuditCheck('Social preview tags (Open Graph)', n('ogTags') > 0, weight: 3),
    AuditCheck('Structured data', n('structuredData') > 0, weight: 2),
  ];

  // Best practices.
  final small = (seo['fontSizeSmall'] as num?)?.toDouble() ?? 0;
  final bpChecks = [
    AuditCheck('Uses HTTPS', seo['https'] == true, weight: 30),
    AuditCheck('No insecure (http) resources', n('mixedContent') == 0, detail: '${n('mixedContent')} found', weight: 15),
    AuditCheck('No console errors', consoleErrors == 0, detail: '$consoleErrors logged', weight: (consoleErrors * 5).clamp(0, 20)),
    AuditCheck('Has a <!doctype>', seo['doctype'] == true, weight: 10),
    AuditCheck('Character set declared', seo['charset'] == true, weight: 5),
    AuditCheck('Reasonable DOM size (< 1,500 nodes)', n('domNodes') < 1500, detail: '${n('domNodes')} nodes', weight: 10),
    AuditCheck('Legible font sizes', small < 0.4, detail: '${(small * 100).round()}% of text under 12px', weight: 10),
  ];

  return [
    AuditCategory('Performance', perfScore.clamp(0, 100), perfChecks),
    AuditCategory('Accessibility', _scoreFrom(a11yChecks), a11yChecks),
    AuditCategory('Best practices', _scoreFrom(bpChecks), bpChecks),
    AuditCategory('SEO', _scoreFrom(seoChecks), seoChecks),
  ];
}
