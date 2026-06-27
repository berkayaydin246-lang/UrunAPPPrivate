import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/admin/models/user_submission.dart';

class SubmissionReviewRepository {
  const SubmissionReviewRepository();

  Future<List<UserSubmission>> fetchPendingSubmissions() async {
    try {
      final response = await SupabaseService.client
          .from('user_submissions')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      return (response as List<dynamic>)
          .map<UserSubmission>(
            (json) => UserSubmission.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      throw Exception('Başvurular yüklenirken hata oluştu: $e');
    }
  }

  Future<void> updateStatus(
    String id,
    String newStatus, {
    String? adminNote,
  }) async {
    try {
      final payload = <String, dynamic>{'status': newStatus};
      if (adminNote != null && adminNote.trim().isNotEmpty) {
        payload['admin_note'] = adminNote.trim();
      }

      await SupabaseService.client
          .from('user_submissions')
          .update(payload)
          .eq('id', id);
    } catch (e) {
      throw Exception('Durum güncellenirken hata oluştu: $e');
    }
  }
}
