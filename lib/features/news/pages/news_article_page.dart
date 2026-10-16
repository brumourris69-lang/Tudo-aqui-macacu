import 'package:flutter/material.dart';

import '../../../core/config/local_search_environment.dart';
import '../../../core/config/local_network_isolation.dart';
import '../../../core/media/media_url_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/search/repositories/local_universal_search_repository.dart';
import '../models/public_news_article.dart';

/// Reusable detail surface. The default resolver is deliberately local-only;
/// other callers can provide an authorized repository when one is prepared.
class NewsArticlePage extends StatefulWidget {
  const NewsArticlePage({super.key, required this.newsId, this.resolveArticle});

  final String newsId;
  final Future<PublicNewsArticle?> Function(String id)? resolveArticle;

  @override
  State<NewsArticlePage> createState() => _NewsArticlePageState();
}

class _NewsArticlePageState extends State<NewsArticlePage> {
  late Future<PublicNewsArticle?> _article;

  @override
  void initState() {
    super.initState();
    _article = _load();
  }

  Future<PublicNewsArticle?> _load() {
    if (widget.resolveArticle != null) {
      return widget.resolveArticle!(widget.newsId);
    }
    return LocalUniversalSearchRepository.resolveNewsArticle(widget.newsId);
  }

  void _retry() => setState(() => _article = _load());

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  bool _canLoadImage(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return false;
    if (LocalSearchEnvironment.enabled) return isLocalEmulatorEndpoint(uri);
    return uri.scheme == 'https' && uri.userInfo.isEmpty;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.soft,
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Voltar',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Notícia'),
    ),
    body: FutureBuilder<PublicNewsArticle?>(
      future: _article,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.sky),
          );
        }
        if (snapshot.hasError) {
          return _status(
            icon: Icons.wifi_off_rounded,
            title: 'Não foi possível carregar esta notícia.',
            detail: 'Verifique a conexão local e tente novamente.',
            action: FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          );
        }
        final article = snapshot.data;
        if (article == null) {
          return _status(
            icon: Icons.article_outlined,
            title: 'Esta notícia não está mais disponível.',
          );
        }
        return _content(article);
      },
    ),
  );

  Widget _content(PublicNewsArticle article) {
    final showImage = _canLoadImage(article.imageUrl);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showImage) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        cloudinaryOptimizedImageUrl(article.imageUrl),
                        fit: BoxFit.cover,
                        frameBuilder: (context, child, frame, syncLoaded) =>
                            frame != null || syncLoaded
                            ? child
                            : const ColoredBox(
                                color: Color(0xFFEAF3FD),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.sky,
                                  ),
                                ),
                              ),
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xFFEAF3FD),
                          child: Center(
                            child: Icon(
                              Icons.newspaper_rounded,
                              size: 42,
                              color: AppColors.sky,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
                if (article.category.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FD),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      article.category,
                      style: const TextStyle(
                        color: AppColors.ocean,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  article.title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                if (article.date != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 15,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _formatDate(article.date!),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                if (article.description.isNotEmpty)
                  Text(
                    article.description,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      height: 1.7,
                    ),
                  ),
                if (article.additionalInfo.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE6EDF5)),
                    ),
                    child: Text(
                      article.additionalInfo,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _status({
    required IconData icon,
    required String title,
    String? detail,
    Widget? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.sky, size: 42),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    ),
  );
}
