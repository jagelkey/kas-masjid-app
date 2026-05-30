import 'package:equatable/equatable.dart';

class MosqueProfile extends Equatable {
  final int? id;
  final String name;
  final String? address;
  final String? logoPath;
  final String? logoUrl;

  const MosqueProfile({
    this.id,
    required this.name,
    this.address,
    this.logoPath,
    this.logoUrl,
  });

  @override
  List<Object?> get props => [id, name, address, logoPath, logoUrl];
}
