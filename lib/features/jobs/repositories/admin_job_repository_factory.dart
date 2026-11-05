import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_job_repository.dart';
import 'spark_admin_job_repository.dart';

/// Selects the existing job persistence path for the current app variant.
/// Beta uses Firestore directly under the Spark Rules; other variants retain
/// the callable transport. Firestore is lazy so callable variants do not
/// initialize or access a Firestore instance as a side effect.
AdminJobRepository createAdminJobRepository({
  required bool sparkBeta,
  FirebaseFirestore Function()? firestore,
}) {
  if (!sparkBeta) return CallableAdminJobRepository();
  return SparkAdminJobRepository(
    (firestore ?? () => FirebaseFirestore.instance)(),
  );
}
