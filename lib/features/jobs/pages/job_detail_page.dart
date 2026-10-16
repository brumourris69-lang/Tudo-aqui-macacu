import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/public_job.dart';
import '../repositories/public_job_details_repository.dart';

/// Job detail is resolved from the original document through the local,
/// authenticated callable; search-index fields are never used as authority.
class JobDetailPage extends StatefulWidget {
  const JobDetailPage({super.key, required this.jobId, this.resolveJob});

  final String jobId;
  final Future<PublicJob?> Function(String id)? resolveJob;

  @override
  State<JobDetailPage> createState() => _JobDetailPageState();
}

class _JobDetailPageState extends State<JobDetailPage> {
  late Future<PublicJob?> _job;

  @override
  void initState() {
    super.initState();
    _job = _load();
  }

  Future<PublicJob?> _load() =>
      widget.resolveJob?.call(widget.jobId) ??
      PublicJobDetailsRepository().resolveById(widget.jobId);

  void _retry() {
    setState(() {
      _job = _load();
    });
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
      title: const Text('Detalhes da vaga'),
    ),
    body: FutureBuilder<PublicJob?>(
      future: _job,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.sky),
          );
        }
        if (snapshot.hasError) {
          return _status(
            icon: Icons.wifi_off_rounded,
            title: 'Não foi possível carregar esta vaga.',
            detail: 'Verifique a conexão local e tente novamente.',
            action: FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          );
        }
        final job = snapshot.data;
        if (job == null) {
          return _status(
            icon: Icons.work_off_outlined,
            title: 'Esta vaga não está mais disponível.',
          );
        }
        return _content(job);
      },
    ),
  );

  Widget _content(PublicJob job) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 112,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0056D6), Color(0xFF007BFF)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.work_outline_rounded,
                  color: Colors.white,
                  size: 46,
                ),
              ),
              const SizedBox(height: 20),
              if (job.category.isNotEmpty)
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
                    job.category,
                    style: const TextStyle(
                      color: AppColors.ocean,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                job.title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              if (job.company.isNotEmpty) ...[
                const SizedBox(height: 12),
                _metadata(Icons.business_outlined, job.company),
              ],
              if (job.location.isNotEmpty) ...[
                const SizedBox(height: 10),
                _metadata(Icons.location_on_outlined, job.location),
              ],
              if (job.employmentType.isNotEmpty) ...[
                const SizedBox(height: 10),
                _metadata(Icons.schedule_outlined, job.employmentType),
              ],
              if (job.description.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  job.description,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 16,
                    height: 1.7,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ],
  );

  Widget _metadata(IconData icon, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppColors.orange),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );

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
