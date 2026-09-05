/// Search-engine-optimization (SEO) helpers for Jaspr web apps.
///
/// This library provides two main pieces:
///
/// 1. [Seo] - a wrapper widget that injects per-page `<title>`, meta tags,
///    OpenGraph, Twitter Card, and canonical link into `<head>` via
///    [jaspr.Document.head]. Works in client-only mode (DOM mutation),
///    server-side mode (pre-rendered HTML), and static mode (build-time HTML).
///
/// 2. [StructuredData] - a wrapper for emitting JSON-LD `<script>` tags so
///    crawlers can build rich snippets (sitelinks, breadcrumbs, articles,
///    etc.) for your pages.
///
/// ## Quick start
///
/// Wrap each screen in [Seo]:
///
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   return Seo(
///     title: 'About',
///     description: 'Learn more about ${AppConstants.appName} ...',
///     canonicalPath: AppRoutes.about,
///     structuredData: [
///       StructuredData.webPage(
///         name: 'About',
///         description: 'Learn more about ${AppConstants.appName}',
///         url: SeoConfig.absoluteUrl(AppRoutes.about),
///       ),
///     ],
///     child: const _AboutBody(),
///   );
/// }
/// ```
///
/// All values default to the site-wide settings in [SeoConfig], so you only
/// need to override the per-page bits (title, description, canonicalPath,
/// optional ogImage and structured data).
library;

import 'dart:convert';

import 'package:arcane_jaspr/arcane_jaspr.dart';
import 'package:jaspr/jaspr.dart' as jaspr;

import '../utils/constants.dart';

/// Wraps a [child] component and injects per-page SEO metadata into
/// the document `<head>`.
///
/// All values fall back to [SeoConfig] defaults when not provided. The
/// underlying [jaspr.Document.head] component supports nesting - tags from
/// deeper [Seo] widgets override shallower ones, so wrapping [App] in a
/// site-level [Seo] and then wrapping each screen in another [Seo] works
/// as expected.
class Seo extends StatelessWidget {
  /// Page title (will be combined with [SeoConfig.siteName]).
  /// If `null`, only [SeoConfig.siteName] is used as the `<title>`.
  final String? title;

  /// Page description, used for meta description and OG/Twitter description.
  final String? description;

  /// Path of the canonical URL (e.g. `'/about'`).
  /// Combined with [SeoConfig.siteUrl] to produce the absolute canonical URL.
  /// Defaults to `'/'`.
  final String? canonicalPath;

  /// Path or absolute URL of the OG/Twitter share image (1200x630 recommended).
  final String? ogImage;

  /// OpenGraph object type (e.g. `website`, `article`, `product`).
  final String ogType;

  /// Twitter card style (`summary` or `summary_large_image`).
  final String twitterCard;

  /// Robots policy override (e.g. `noindex, nofollow` for staging).
  final String? robots;

  /// Optional list of JSON-LD structured-data blocks emitted as
  /// `<script type="application/ld+json">` tags inside `<head>`.
  final List<StructuredData> structuredData;

  /// Additional raw `<head>` components for cases not covered above
  /// (preconnect, prefetch, alternate language links, etc.).
  final List<jaspr.Component> additionalHead;

  /// The page content rendered inside `<body>` as normal.
  final Widget child;

  const Seo({
    super.key,
    this.title,
    this.description,
    this.canonicalPath,
    this.ogImage,
    this.ogType = 'website',
    this.twitterCard = 'summary_large_image',
    this.robots,
    this.structuredData = const [],
    this.additionalHead = const [],
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final String fullTitle = title == null || title!.isEmpty
        ? SeoConfig.siteName
        : '$title  ·  ${SeoConfig.siteName}';
    final String desc = description ?? SeoConfig.defaultDescription;
    final String image = SeoConfig.absoluteUrl(
      ogImage ?? SeoConfig.defaultOgImage,
    );
    final String url = SeoConfig.absoluteUrl(canonicalPath ?? AppRoutes.home);

    final List<jaspr.Component> head = <jaspr.Component>[
      // Standard meta description + robots
      _meta(name: 'description', content: desc),
      _meta(name: 'robots', content: robots ?? SeoConfig.defaultRobots),
      // OpenGraph
      _meta(property: 'og:type', content: ogType),
      _meta(property: 'og:title', content: title ?? SeoConfig.siteName),
      _meta(property: 'og:description', content: desc),
      _meta(property: 'og:url', content: url),
      _meta(property: 'og:image', content: image),
      _meta(property: 'og:site_name', content: SeoConfig.siteName),
      _meta(property: 'og:locale', content: SeoConfig.ogLocale),
      // Twitter
      _meta(name: 'twitter:card', content: twitterCard),
      _meta(name: 'twitter:title', content: title ?? SeoConfig.siteName),
      _meta(name: 'twitter:description', content: desc),
      _meta(name: 'twitter:image', content: image),
      if (SeoConfig.twitterHandle.isNotEmpty)
        _meta(name: 'twitter:site', content: SeoConfig.twitterHandle),
      // Canonical link
      _link(rel: 'canonical', href: url),
      // Caller-supplied head extras + structured data
      ...additionalHead,
      ...structuredData,
    ];

    return jaspr.Component.fragment(<jaspr.Component>[
      jaspr.Document.head(title: fullTitle, children: head),
      child,
    ]);
  }

  static jaspr.Component _meta({
    String? name,
    String? property,
    required String content,
  }) {
    final Map<String, String> attrs = <String, String>{};
    if (name != null) attrs['name'] = name;
    if (property != null) attrs['property'] = property;
    attrs['content'] = content;
    return jaspr.Component.element(tag: 'meta', attributes: attrs);
  }

  static jaspr.Component _link({required String rel, required String href}) {
    return jaspr.Component.element(
      tag: 'link',
      attributes: <String, String>{'rel': rel, 'href': href},
    );
  }
}

/// Renders a JSON-LD `<script type="application/ld+json">` block inside the
/// document `<head>` for rich-snippet support.
///
/// Use the named constructors for common schema types, or pass arbitrary
/// JSON via the default constructor for custom schemas.
///
/// Reference: https://schema.org / https://developers.google.com/search/docs/appearance/structured-data
class StructuredData extends StatelessWidget {
  /// The raw JSON-LD payload (will be wrapped in a `<script>` tag).
  final Map<String, Object?> data;

  /// Build a structured-data block from arbitrary JSON.
  const StructuredData(this.data, {super.key});

  /// `WebSite` schema with optional sitelinks search-action.
  ///
  /// Use this once on the home page so Google can offer a search box for
  /// your site directly in the search results.
  factory StructuredData.website({
    String? name,
    String? url,
    String? searchUrlTemplate,
    Key? key,
  }) {
    final Map<String, Object?> json = <String, Object?>{
      '@context': 'https://schema.org',
      '@type': 'WebSite',
      'name': name ?? SeoConfig.siteName,
      'url': url ?? SeoConfig.siteUrl,
      if (searchUrlTemplate != null)
        'potentialAction': <String, Object?>{
          '@type': 'SearchAction',
          'target': <String, Object?>{
            '@type': 'EntryPoint',
            'urlTemplate': searchUrlTemplate,
          },
          'query-input': 'required name=search_term_string',
        },
    };
    return StructuredData(json, key: key);
  }

  /// `Organization` schema for the publisher of the site.
  factory StructuredData.organization({
    String? name,
    String? url,
    String? logo,
    List<String> sameAs = const <String>[],
    Key? key,
  }) {
    final Map<String, Object?> json = <String, Object?>{
      '@context': 'https://schema.org',
      '@type': 'Organization',
      'name': name ?? SeoConfig.organizationName,
      'url': url ?? SeoConfig.siteUrl,
      'logo': SeoConfig.absoluteUrl(logo ?? SeoConfig.organizationLogo),
      if (sameAs.isNotEmpty) 'sameAs': sameAs,
    };
    return StructuredData(json, key: key);
  }

  /// `WebPage` schema describing the current page.
  factory StructuredData.webPage({
    required String name,
    String? description,
    String? url,
    Key? key,
  }) {
    return StructuredData(<String, Object?>{
      '@context': 'https://schema.org',
      '@type': 'WebPage',
      'name': name,
      'description': ?description,
      'url': url ?? SeoConfig.siteUrl,
    }, key: key);
  }

  /// `Article` schema for blog posts and editorial content.
  factory StructuredData.article({
    required String headline,
    String? description,
    String? image,
    String? authorName,
    DateTime? datePublished,
    DateTime? dateModified,
    String? url,
    Key? key,
  }) {
    final Map<String, Object?> json = <String, Object?>{
      '@context': 'https://schema.org',
      '@type': 'Article',
      'headline': headline,
      'description': ?description,
      if (image != null) 'image': SeoConfig.absoluteUrl(image),
      if (authorName != null)
        'author': <String, Object?>{
          '@type': 'Person',
          'name': authorName,
        },
      'publisher': <String, Object?>{
        '@type': 'Organization',
        'name': SeoConfig.organizationName,
        'logo': <String, Object?>{
          '@type': 'ImageObject',
          'url': SeoConfig.absoluteUrl(SeoConfig.organizationLogo),
        },
      },
      if (datePublished != null)
        'datePublished': datePublished.toUtc().toIso8601String(),
      if (dateModified != null)
        'dateModified': dateModified.toUtc().toIso8601String(),
      'mainEntityOfPage': ?url,
    };
    return StructuredData(json, key: key);
  }

  /// `BreadcrumbList` schema enabling Google to show breadcrumb chips in
  /// search results.
  factory StructuredData.breadcrumbList(
    List<({String name, String url})> items, {
    Key? key,
  }) {
    int position = 0;
    final List<Map<String, Object?>> elements = items.map((item) {
      position += 1;
      return <String, Object?>{
        '@type': 'ListItem',
        'position': position,
        'name': item.name,
        'item': item.url,
      };
    }).toList();
    return StructuredData(<String, Object?>{
      '@context': 'https://schema.org',
      '@type': 'BreadcrumbList',
      'itemListElement': elements,
    }, key: key);
  }

  /// `FAQPage` schema for sitelinks rich result on FAQ-style pages.
  factory StructuredData.faqPage(
    List<({String question, String answer})> entries, {
    Key? key,
  }) {
    return StructuredData(<String, Object?>{
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      'mainEntity': entries
          .map(
            (e) => <String, Object?>{
              '@type': 'Question',
              'name': e.question,
              'acceptedAnswer': <String, Object?>{
                '@type': 'Answer',
                'text': e.answer,
              },
            },
          )
          .toList(),
    }, key: key);
  }

  @override
  Widget build(BuildContext context) {
    return jaspr.Component.element(
      tag: 'script',
      attributes: const <String, String>{'type': 'application/ld+json'},
      children: <jaspr.Component>[jaspr.Component.text(jsonEncode(data))],
    );
  }
}
