import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/theme/colors.dart';

class _MixColors {
  _MixColors._();

  static const active = Color(0xFF0F6E56);
  static const expiring = Color(0xFFE0A93E);
  static const expired = Color(0xFFD9564C);
}

class MembershipMixCard extends StatelessWidget {
  const MembershipMixCard({
    super.key,
    required this.active,
    required this.expiring,
    required this.expired,
  });

  final int active;
  final int expiring;
  final int expired;

  @override
  Widget build(BuildContext context) {
    final total = active + expiring + expired;
    final activePct = total == 0 ? 0 : (active / total * 100).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Membership mix',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.fieldBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Total: $total',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        startDegreeOffset: -90,
                        sectionsSpace: 2,
                        centerSpaceRadius: 37,
                        sections: total == 0
                            ? [
                                PieChartSectionData(
                                  value: 1,
                                  color: AppColors.disabledBg,
                                  showTitle: false,
                                  radius: 16,
                                ),
                              ]
                            : [
                                PieChartSectionData(
                                  value: active.toDouble(),
                                  color: _MixColors.active,
                                  showTitle: false,
                                  radius: 16,
                                ),
                                PieChartSectionData(
                                  value: expiring.toDouble(),
                                  color: _MixColors.expiring,
                                  showTitle: false,
                                  radius: 16,
                                ),
                                PieChartSectionData(
                                  value: expired.toDouble(),
                                  color: _MixColors.expired,
                                  showTitle: false,
                                  radius: 16,
                                ),
                              ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$activePct%',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'ACTIVE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                            color: _MixColors.active,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 18),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MixRow(
                      color: _MixColors.active,
                      label: 'Active',
                      value: active,
                    ),
                    const SizedBox(height: 11),
                    _MixRow(
                      color: _MixColors.expiring,
                      label: 'Expiring soon',
                      value: expiring,
                    ),
                    const SizedBox(height: 11),
                    _MixRow(
                      color: _MixColors.expired,
                      label: 'Expired',
                      value: expired,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MixRow extends StatelessWidget {
  const _MixRow({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: AppColors.muted),
          ),
        ),
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}
