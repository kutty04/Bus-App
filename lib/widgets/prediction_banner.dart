// lib/widgets/prediction_banner.dart
//
// Shows the crowd prediction for a route.
// Displayed at the top of the route screen when a route is selected.
// Also used in the feed screen's empty state.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/crowd_prediction_service.dart';

class PredictionBanner extends StatelessWidget {
  final String routeNo;
  final CrowdPrediction prediction;

  const PredictionBanner({
    super.key,
    required this.routeNo,
    required this.prediction,
  });

  Color get _color {
    switch (prediction.colorKey) {
      case 'green':
        return AppTheme.green;
      case 'red':
        return AppTheme.red;
      default:
        return AppTheme.yellow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // ── Gauge circle ────────────────────────────────────────────
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: prediction.predictedPercent / 100,
                  backgroundColor: _color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(_color),
                  strokeWidth: 4,
                ),
                Center(
                  child: Text(
                    '${prediction.predictedPercent}%',
                    style: TextStyle(
                      color: _color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          // ── Text block ──────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${prediction.emoji} ${prediction.label}',
                      style: TextStyle(
                        color: _color,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (prediction.hasLiveData)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.textDim.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PREDICTED',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Route $routeNo right now',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  prediction.contextLine,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}