import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

class ParameterTuningSheet extends StatefulWidget {
  final GenerationParams initialParams;
  final Function(GenerationParams updatedParams) onSave;

  const ParameterTuningSheet({
    super.key,
    required this.initialParams,
    required this.onSave,
  });

  @override
  State<ParameterTuningSheet> createState() => _ParameterTuningSheetState();
}

class _ParameterTuningSheetState extends State<ParameterTuningSheet> {
  late double _temperature;
  late double _topP;
  late int _topK;
  late double _minP;
  late double _repeatPenalty;
  late int _maxTokens;
  late int _contextSize;
  late TextEditingController _contextSizeController;
  late TextEditingController _maxTokensController;

  @override
  void initState() {
    super.initState();
    _temperature = widget.initialParams.temperature;
    _topP = widget.initialParams.topP;
    _topK = widget.initialParams.topK;
    _minP = widget.initialParams.minP;
    _repeatPenalty = widget.initialParams.repeatPenalty;
    _maxTokens = widget.initialParams.maxTokens;
    _contextSize = widget.initialParams.contextSize;
    _maxTokensController = TextEditingController(text: _maxTokens.toString());
    _contextSizeController = TextEditingController(text: _contextSize.toString());
  }

  @override
  void dispose() {
    _maxTokensController.dispose();
    _contextSizeController.dispose();
    super.dispose();
  }

  void _resetDefaults() {
    setState(() {
      _temperature = 0.7;
      _topP = 0.9;
      _topK = 40;
      _minP = 0.05;
      _repeatPenalty = 1.1;
      _maxTokens = 4096;
      _contextSize = 4096;
      _maxTokensController.text = '4096';
      _contextSizeController.text = '4096';
    });
  }

  void _handleSave() {
    // Parse context size from controller (allows arbitrary values)
    int parsedContext = _contextSize;
    final parsed = int.tryParse(_contextSizeController.text.trim());
    if (parsed != null && parsed >= 128 && parsed <= 1000000) {
      parsedContext = parsed;
    }

    // Parse max tokens from controller
    int parsedMaxTokens = _maxTokens;
    final parsedMax = int.tryParse(_maxTokensController.text.trim());
    if (parsedMax != null && parsedMax >= 0 && parsedMax <= 8192) {
      parsedMaxTokens = parsedMax;
    }

    final updated = widget.initialParams.copyWith(
      temperature: _temperature,
      topP: _topP,
      topK: _topK,
      minP: _minP,
      repeatPenalty: _repeatPenalty,
      maxTokens: parsedMaxTokens,
      contextSize: parsedContext,
    );
    widget.onSave(updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.only(top: 16, left: 20, right: 20, bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle Pill
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title and Reset
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Generation Parameters',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: _resetDefaults,
                    child: const Text('Reset Defaults'),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Max Tokens Input
              _buildNumberInput(
                title: 'Max Generation Tokens',
                subtitle: 'Max tokens per response (0 = unlimited)',
                controller: _maxTokensController,
                value: _maxTokens,
                min: 0,
                max: 8192,
                onChanged: (v) => setState(() => _maxTokens = v),
              ),

              // Context Window Size with custom input
              _buildContextSizeInput(
                title: 'Context Window (n_ctx)',
                subtitle: 'Max tokens the model can process (up to 1,000,000)',
                value: _contextSize,
                controller: _contextSizeController,
                onChanged: (v) => setState(() => _contextSize = v),
              ),

              const SizedBox(height: 12),

              // Temperature Slider
              _buildSlider(
                title: 'Temperature',
                subtitle: 'Controls randomness (lower = more deterministic)',
                value: _temperature,
                min: 0.0,
                max: 2.0,
                displayValue: _temperature.toStringAsFixed(2),
                onChanged: (v) => setState(() => _temperature = v),
              ),

              // Top-P Slider
              _buildSlider(
                title: 'Top-P (Nucleus Sampling)',
                subtitle: 'Considers tokens with top_p probability mass',
                value: _topP,
                min: 0.0,
                max: 1.0,
                displayValue: _topP.toStringAsFixed(2),
                onChanged: (v) => setState(() => _topP = v),
              ),

              // Min-P Slider
              _buildSlider(
                title: 'Min-P Sampling',
                subtitle: 'Minimum base probability cutoff relative to top token',
                value: _minP,
                min: 0.0,
                max: 0.5,
                displayValue: _minP.toStringAsFixed(2),
                onChanged: (v) => setState(() => _minP = v),
              ),

              // Repeat Penalty Slider
              _buildSlider(
                title: 'Repeat Penalty',
                subtitle: 'Penalizes repetition of previously generated tokens',
                value: _repeatPenalty,
                min: 1.0,
                max: 1.5,
                displayValue: _repeatPenalty.toStringAsFixed(2),
                onChanged: (v) => setState(() => _repeatPenalty = v),
              ),

              // Top-K Slider
              _buildSlider(
                title: 'Top-K',
                subtitle: 'Limits pool to K most likely tokens',
                value: _topK.toDouble(),
                min: 0,
                max: 100,
                displayValue: _topK.toString(),
                onChanged: (v) => setState(() => _topK = v.round()),
              ),

              const SizedBox(height: 16),

              // Save Action Button
              FilledButton(
                onPressed: _handleSave,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Apply Parameters', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  displayValue,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.accentPrimary,
              thumbColor: AppTheme.accentPrimary,
              inactiveTrackColor: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberInput({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppTheme.accentPrimary),
                    ),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    final parsed = int.tryParse(val);
                    if (parsed != null && parsed >= min && parsed <= max) {
                      onChanged(parsed);
                    }
                  },
                ),
              ),
            ],
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextSizeInput({
    required String title,
    required String subtitle,
    required int value,
    required TextEditingController controller,
    required ValueChanged<int> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: '1000000',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppTheme.accentPrimary),
                    ),
                    isDense: true,
                    suffixText: 'tokens',
                    suffixStyle: TextStyle(
                      fontSize: 10,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                  onChanged: (val) {
                    final parsed = int.tryParse(val);
                    if (parsed != null && parsed >= 128 && parsed <= 1000000) {
                      onChanged(parsed);
                    }
                  },
                ),
              ),
            ],
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
          ),
        ],
      ),
    );
  }
}
