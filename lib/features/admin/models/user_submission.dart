import 'package:flutter/material.dart';

class UserSubmission {
  final String id;
  final String? userId;
  final String? barcode;
  final String? productName;
  final String? frontImageUrl;
  final String? ingredientsImageUrl;
  final String? nutritionImageUrl;
  final String? ocrText;
  final String status; // pending, approved, rejected, needs_more_info
  final String? adminNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserSubmission({
    required this.id,
    this.userId,
    this.barcode,
    this.productName,
    this.frontImageUrl,
    this.ingredientsImageUrl,
    this.nutritionImageUrl,
    this.ocrText,
    required this.status,
    this.adminNote,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserSubmission.fromJson(Map<String, dynamic> json) {
    return UserSubmission(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      barcode: json['barcode'] as String?,
      productName: json['product_name'] as String?,
      frontImageUrl: json['front_image_url'] as String?,
      ingredientsImageUrl: json['ingredients_image_url'] as String?,
      nutritionImageUrl: json['nutrition_image_url'] as String?,
      ocrText: json['ocr_text'] as String?,
      status: json['status'] as String? ?? 'pending',
      adminNote: json['admin_note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Beklemede';
      case 'approved':
        return 'Onaylandı';
      case 'rejected':
        return 'Reddedildi';
      case 'needs_more_info':
        return 'Ek Bilgi Gerekli';
      default:
        return status;
    }
  }

  Color get statusColor {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'needs_more_info':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  String toString() =>
      'UserSubmission(id=$id, productName=$productName, status=$status)';
}
