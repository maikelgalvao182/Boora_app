import 'package:partiu/features/profile/presentation/widgets/profile_visits_chip.dart';
import 'package:flutter/material.dart';

class ProfileInfoChips extends StatelessWidget {
  const ProfileInfoChips({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Visits chip
          ProfileVisitsChip(),
        ],
      ),
    );
  }
}