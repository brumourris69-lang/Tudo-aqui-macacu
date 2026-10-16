import 'package:flutter/material.dart';

/// Visible, persistent environment marker; never shown in normal/demo builds.
class StagingEnvironmentBanner extends StatelessWidget {
  const StagingEnvironmentBanner({super.key});

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF28C28),
    child: SizedBox(
      height: 26,
      width: double.infinity,
      child: Center(
        child: Text(
          'HOMOLOGAÇÃO · DADOS DE TESTE',
          semanticsLabel: 'Aplicativo conectado ao ambiente de homologação',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
      ),
    ),
  );
}
