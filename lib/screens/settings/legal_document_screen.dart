import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';

/// A single section of a legal document: a heading followed by a body.
class LegalSection {
  final String heading;
  final String body;

  const LegalSection({required this.heading, required this.body});
}

/// Generic, reusable screen for rendering a long-form legal document
/// (Privacy Policy, Terms of Service, etc.) as a scrollable list of
/// titled sections. Both legal screens share this so the visual style
/// stays consistent and future edits only happen in one place.
class LegalDocumentScreen extends StatelessWidget {
  final String title;
  final String lastUpdated;
  final String intro;
  final List<LegalSection> sections;

  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.lastUpdated,
    required this.intro,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.dark,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.dark),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'Last updated: $lastUpdated',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              intro,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 24),
            for (int i = 0; i < sections.length; i++) ...[
              _SectionBlock(index: i + 1, section: sections[i]),
              if (i != sections.length - 1) const SizedBox(height: 22),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  final int index;
  final LegalSection section;

  const _SectionBlock({required this.index, required this.section});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$index. ${section.heading}',
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: AppColors.dark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          section.body,
          style: const TextStyle(
            fontSize: 14.5,
            height: 1.55,
            color: AppColors.dark,
          ),
        ),
      ],
    );
  }
}
