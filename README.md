# Trinity Elliott Wave Indicator for MetaTrader 5

## 1. Overview

The **Trinity Elliott Wave Indicator** is an advanced, automated analysis tool for MetaTrader 5 (MT5). It is designed to identify high-probability Elliott Wave patterns on any financial instrument and timeframe.

Unlike basic wave counters, this indicator uses a sophisticated scoring system to validate and rank potential wave patterns. By combining classic Elliott Wave theory with confirmation from key indicators like RSI and Volume, it filters out low-quality signals and highlights only the most promising setups.

This tool is intended for both experienced Elliott Wave practitioners seeking to automate their analysis and for traders new to the methodology who want a reliable guide to identifying powerful market structures.

## 2. Features

- **Automated 5-Wave Pattern Detection:** Automatically scans historical price data to identify and draw 5-wave impulse patterns.
- **Advanced Scoring System:** Each identified pattern is assigned a quality score based on:
    - **Fibonacci Ratios:** Checks for ideal Fibonacci retracement and extension levels within the wave structure.
    - **Volume Confirmation:** Awards points when trading volume supports the direction of the impulse waves.
    - **Momentum Analysis:** Uses the Relative Strength Index (RSI) to detect momentum convergence and divergence, a key confirmation signal.
- **Customizable Parameters:** Provides a full set of input parameters to tailor the indicator's sensitivity and appearance to your trading style.
- **Visual Clarity:** Draws and labels wave patterns, price targets, and Fibonacci time zones directly on the chart.
- **Multi-Pattern Display:** Option to display multiple high-scoring patterns across the chart's history, providing a broader market context.

## 3. Installation

1.  **Open MetaTrader 5.**
2.  Go to `File` -> `Open Data Folder`. The MT5 data directory will open in a new window.
3.  Navigate to the `MQL5` -> `Indicators` folder.
4.  Copy the `Trinity_Eliot.mq5` file into this `Indicators` folder.
5.  Return to MetaTrader 5. In the `Navigator` panel (usually on the left), right-click on `Indicators` and select `Refresh`.
6.  The `Trinity Elliott Wave` indicator will now appear in your list of indicators. You can drag it onto a chart or double-click it to apply.

## 4. Configuration Parameters

The indicator's behavior is controlled by a comprehensive set of input parameters, accessible in the `Inputs` tab when you add the indicator to a chart.

### Peak Detection Settings
- **`InpPeakSearchPeriod`**: The number of bars to the left and right of a candle to check for it to be considered a local peak or trough. Higher values find more significant, longer-term pivots.
- **`InpPeakProminenceATR`**: The minimum required price move (in multiples of the Average True Range) between two consecutive pivots for them to be considered distinct. This filters out minor "noise".

### History Settings
- **`InpLookbackBars`**: The maximum number of historical bars to analyze. Limiting this can improve performance on very large charts.

### Confirmation Indicator Settings
- **`InpRSI_Period`**: The lookback period for the RSI calculation.
- **`InpMACD_Fast` / `InpMACD_Slow` / `InpMACD_Signal`**: Standard MACD indicator parameters.
- **`InpVolume_MA_Period`**: The lookback period for the moving average applied to volume, used for volume spike detection.
- **`InpUseRSI` / `InpUseVolume`**: Toggles whether to include RSI and Volume analysis in the pattern scoring.

### Drawing Settings
- **`InpImpulseColor` / `InpCorrectionColor`**: Colors for the impulse and corrective wave lines.
- **`InpTargetColor` / `InpTimeZoneColor`**: Colors for the projected price targets and Fibonacci time zones.
- **`InpStyle` / `InpWidth`**: The style (e.g., solid, dashed) and thickness of the drawn lines.

### Pattern Selection
- **`InpDrawAllPatterns`**: If `true`, the indicator will draw multiple high-scoring patterns from history. If `false`, it will only show the single best pattern found.
- **`InpMinScore`**: The minimum quality score a pattern must achieve to be drawn on the chart.
- **`InpMinBarsBetween`**: The minimum number of bars that must separate the starting points of two different patterns when `InpDrawAllPatterns` is active.
- **`InpMaxPatterns`**: The maximum number of patterns to display on the chart at one time.

## 5. Usage and Interpretation

1.  **Apply the Indicator:** Add the indicator to your chart and configure the settings. For most major markets, the default settings are a good starting point.
2.  **Identify High-Scoring Patterns:** Look for wave patterns drawn on the chart. A higher score (viewable by hovering over the pattern elements, though not explicitly displayed) indicates a higher-quality setup that adheres more closely to ideal Elliott Wave principles and is confirmed by volume and momentum.
3.  **Interpret the Pattern:**
    - A **bullish pattern** (blue lines by default) is an upward-moving 5-wave sequence, suggesting the primary trend is up. It implies a potential buying opportunity.
    - A **bearish pattern** (red lines by default) is a downward-moving 5-wave sequence, suggesting the primary trend is down. It implies a potential selling opportunity.
4.  **Use the Targets:**
    - **Price Target (Goldenrod Dotted Line):** This horizontal line suggests a probable price level where the 5th wave might end. It is calculated using Fibonacci relationships.
    - **Time Zones (Gray Dotted Lines):** These vertical lines project future dates where a trend change or significant price action might occur, based on the Fibonacci time sequence.
5.  **Confirmation:** Always use the patterns generated by this indicator in conjunction with your own trading strategy and risk management rules. It is a powerful analysis tool, not a standalone trading signal generator. Look for confirmation from other sources, such as support/resistance levels, price action, or other indicators you trust.