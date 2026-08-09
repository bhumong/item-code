import 'package:flutter/material.dart';

class DocumentDetailScreen extends StatelessWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Document')));
  }
}
