import 'package:flutter/material.dart';

import '../../../core/services/external_link_service.dart';
import '../models/city_news_item.dart';
import '../services/city_news_repository.dart';

class PrefeituraNewsCarousel extends StatefulWidget {
  const PrefeituraNewsCarousel({super.key, this.repository});

  final CityNewsRepository? repository;

  @override
  State<PrefeituraNewsCarousel> createState() => _PrefeituraNewsCarouselState();
}

class _PrefeituraNewsCarouselState extends State<PrefeituraNewsCarousel> {
  late final CityNewsRepository _repository;
  Future<CityNewsSnapshot>? _future;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PrefeituraRssNewsRepository();
    if (_repository.isAvailable) _future = _repository.load();
  }

  Future<void> _open(Uri uri, String label) async {
    if (uri.scheme != 'https' || uri.host != 'www.prefeituracachoeiras.com') {
      return;
    }
    await openUrl(context, uri.toString(), label);
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    if (future == null) {
      return _profileCard(context, 'Feed de notícias indisponível no momento.');
    }
    return FutureBuilder<CityNewsSnapshot>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 184,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final data = snapshot.data;
        if (snapshot.hasError || data == null || data.posts.isEmpty) {
          return _profileCard(
            context,
            'Não foi possível carregar as notícias.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 206,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: data.posts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _postCard(data.posts[index]),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(
                    Icons.newspaper_outlined,
                    size: 16,
                    color: Color(0xFF1769AA),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Notícias oficiais da Prefeitura',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Color(0xFF62788D)),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        _open(data.profileUrl, 'Notícias da Prefeitura'),
                    child: const Text('Ver todas'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _postCard(CityNewsItem post) => SizedBox(
    width: 250,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(post.permalink, 'Notícia da Prefeitura'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (post.imageUrl case final imageUrl?)
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xFFEAF2FA),
                        child: Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: Color(0xFF7990A5),
                          ),
                        ),
                      ),
                    )
                  else
                    const ColoredBox(
                      color: Color(0xFFEAF2FA),
                      child: Center(
                        child: Icon(
                          Icons.newspaper_outlined,
                          color: Color(0xFF7990A5),
                        ),
                      ),
                    ),
                  if (post.title.isNotEmpty)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xD9000000)],
                          ),
                        ),
                        child: Text(
                          post.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  const Positioned(
                    top: 10,
                    right: 10,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xCCFFFFFF),
                      child: Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: Color(0xFF1769AA),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  const Icon(
                    Icons.newspaper_outlined,
                    size: 15,
                    color: Color(0xFF1769AA),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      post.publishedAt == null
                          ? post.caption
                          : _shortDate(post.publishedAt!) +
                                (post.caption.isEmpty
                                    ? ''
                                    : ' · ${post.caption}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _profileCard(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFEAF2FA),
              child: Icon(Icons.newspaper_outlined, color: Color(0xFF1769AA)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Notícias da Prefeitura',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF62788D),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Abrir notícias da Prefeitura',
              onPressed: () => _open(
                Uri.https('www.prefeituracachoeiras.com', '/noticias'),
                'Notícias da Prefeitura',
              ),
              icon: const Icon(
                Icons.arrow_outward_rounded,
                color: Color(0xFF1769AA),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static String _shortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}
