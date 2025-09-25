//+------------------------------------------------------------------+
//|                                           Trinity_Eliot.mq5 |
//|                             Copyright 2025, Gemini AI Labs      |
//|                                     Version 1.53 (Final Fix)     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Gemini AI Labs"
#property link      "https"
#property version   "1.53"
#property description "Advanced Elliott Wave indicator with a scoring system."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Include MA library
#include <MovingAverages.mqh>

//--- User Input Parameters
input group           "Peak Detection Settings"
input int             InpPeakSearchPeriod   = 5;       // Period for peak search (bars to the left/right)
input double          InpPeakProminenceATR  = 1.5;     // Peak prominence coefficient (in ATR units)

//--- History Limit Setting
input group           "History Settings"
input int             InpLookbackBars       = 1000;    // How many bars back to calculate and draw

//--- Confirmation Indicator Parameters
input group           "Confirmation Indicator Settings"
input int             InpRSI_Period         = 14;      // RSI Period
input int             InpMACD_Fast          = 12;      // MACD Fast EMA
input int             InpMACD_Slow          = 26;      // MACD Slow EMA
input int             InpMACD_Signal        = 9;       // MACD Signal SMA
input int             InpVolume_MA_Period   = 20;      // Volume Moving Average
input bool            InpUseRSI             = true;    // Use RSI for confirmation
input bool            InpUseVolume          = true;    // Use Volume for confirmation

//--- Drawing Settings
input group           "Drawing Settings"
input color           InpImpulseColor       = clrDodgerBlue; // Impulse wave color
input color           InpCorrectionColor    = clrOrangeRed;  // Correction wave color
input color           InpTargetColor        = clrGoldenrod;  // Price projection color
input color           InpTimeZoneColor      = clrGray;       // Time zone color
input ENUM_LINE_STYLE InpStyle              = STYLE_SOLID;   // Line style
input int             InpWidth              = 2;             // Line width
input bool            InpForceDraw          = false;   // Force draw last 6 pivots (for testing)

//--- Pattern Selection / Drawing Parameters
input group           "Pattern Selection"
input bool            InpDrawAllPatterns    = true;    // Draw multiple patterns in history
input double          InpMinScore           = 30.0;    // Minimum score to be drawn
input int             InpMinBarsBetween     = 50;      // Minimum bars between pattern starts
input int             InpMaxPatterns        = 5;       // Maximum number of patterns to draw

//--- Data Structures
/**
 * @struct PeakPoint
 * @brief Represents a significant price peak or trough (pivot point).
 *
 * This structure stores all the necessary information about a detected
 * high or low point in the price series.
 */
struct PeakPoint
{
    double   price;     ///< The price level of the peak (high) or trough (low).
    datetime time;      ///< The timestamp of the bar where the peak/trough occurred.
    int      bar_index; ///< The index of the bar in the history.
    bool     is_peak;   ///< True if it's a peak (high), false if it's a trough (low).
};

/**
 * @struct WavePattern
 * @brief Represents a potential Elliott Wave pattern.
 *
 * This structure holds an array of PeakPoints that form a potential
 * Elliott Wave pattern (5 impulse waves + 3 corrective waves), along with
 * its calculated quality score and direction.
 */
struct WavePattern
{
    PeakPoint points[9];  ///< Array of points forming the pattern (0-1-2-3-4-5-A-B-C).
    int       point_count;///< The number of points currently in the pattern.
    double    score;      ///< The calculated quality score of the pattern.
    bool      is_bullish; ///< True if the pattern is bullish, false if bearish.
};

//--- Global variables and indicator handles
int h_rsi, h_macd, h_atr, h_volume;
string indicator_prefix;

//+------------------------------------------------------------------+
/**
 * @brief Indicator initialization function.
 * @return int Initialization status (INIT_SUCCEEDED or INIT_FAILED).
 *
 * This function is called once when the indicator is first loaded. It sets up
 * a unique prefix for graphical objects to avoid conflicts and creates handles
 * for the ATR, RSI, MACD, and Volume indicators.
 */
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Unique prefix for graphical objects
    indicator_prefix = "EWA_" + IntegerToString(ChartID()) + "_";

    //--- Create indicator handles
    h_atr = iATR(_Symbol, _Period, 14);
    h_rsi = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_CLOSE);
    h_macd = iMACD(_Symbol, _Period, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);
    h_volume = iVolumes(_Symbol, _Period, VOLUME_TICK);
    
    if(h_rsi == INVALID_HANDLE || h_macd == INVALID_HANDLE || h_atr == INVALID_HANDLE || h_volume == INVALID_HANDLE)
    {
        Print("Failed to create indicator handles. Error code: ", GetLastError());
        return(INIT_FAILED);
    }
    
    IndicatorSetString(INDICATOR_SHORTNAME, "ElliottWaveAdvanced");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
/**
 * @brief Indicator deinitialization function.
 * @param reason The reason for deinitialization.
 *
 * This function is called when the indicator is being removed from the chart.
 * It releases all previously created indicator handles and cleans up all
 * graphical objects drawn by this indicator instance.
 */
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Release handles
    IndicatorRelease(h_rsi);
    IndicatorRelease(h_macd);
    IndicatorRelease(h_atr);
    IndicatorRelease(h_volume);

    //--- Clean up all graphical objects
    ObjectsDeleteAll(0, indicator_prefix);
}

//+------------------------------------------------------------------+
/**
 * @brief Main indicator calculation function.
 * @param rates_total     Total bars available on the chart.
 * @param prev_calculated Bars calculated in the previous call.
 * @param time            Array of bar timestamps.
 * @param open            Array of open prices.
 * @param high            Array of high prices.
 * @param low             Array of low prices.
 * @param close           Array of close prices.
 * @param tick_volume     Array of tick volumes.
 * @param volume          Array of real volumes.
 * @param spread          Array of spreads.
 * @return int            Number of bars calculated.
 *
 * This function is the core of the indicator, executed on every new tick.
 * It orchestrates the process of finding peaks, validating patterns,
 * scoring them, and drawing the results on the chart.
 */
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    //--- Clear old objects
    ObjectsDeleteAll(0, indicator_prefix);

    // 1. Get reliable peaks and troughs
    PeakPoint peaks[];
    // Limit calculation to the selected history depth (safeguards and limits)
    int lookback = InpLookbackBars;
    if(lookback <= 0 || lookback > rates_total)
        lookback = rates_total;
    int start_bar = MathMax(InpPeakSearchPeriod, rates_total - lookback);
    int end_bar   = rates_total - InpPeakSearchPeriod - 1;
    if(end_bar <= start_bar) return(rates_total);

    int peaks_found = FindAdvancedPeaks(peaks, rates_total, high, low, time, start_bar, end_bar);
    if(peaks_found < 6) return(rates_total);

    // 2. Find and evaluate all possible patterns
    WavePattern candidates[];
    int candidates_count = 0;

    for(int i = peaks_found - 6; i >= 0; i--)
    {
        WavePattern current_pattern;
        current_pattern.point_count = 6;
        for(int j=0; j<6; j++) current_pattern.points[j] = peaks[i+j];

        // Check basic rules
        if(ValidateElliottRules(current_pattern))
        {
            // If rules are good, calculate quality score
            current_pattern.score = CalculatePatternScore(current_pattern, rates_total, tick_volume);
            ArrayResize(candidates, candidates_count + 1);
            candidates[candidates_count] = current_pattern;
            candidates_count++;
        }
    }
    
    if(candidates_count == 0 && !InpForceDraw) return(rates_total);

    // 3. Draw: all or the best
    if(InpDrawAllPatterns)
    {
        int drawn = 0;
        int last_start_bar = -InpMinBarsBetween - 1;
        // Sort by score in descending order (simple selection sort)
        for(int pass=0; pass<candidates_count-1; pass++)
        {
            int max_idx = pass;
            for(int k=pass+1; k<candidates_count; k++) if(candidates[k].score > candidates[max_idx].score) max_idx = k;
            if(max_idx!=pass)
            {
                WavePattern tmp = candidates[pass];
                candidates[pass] = candidates[max_idx];
                candidates[max_idx] = tmp;
            }
        }
        
        for(int i=0; i<candidates_count && drawn < InpMaxPatterns; i++)
        {
            WavePattern p = candidates[i];
            if(!InpForceDraw && p.score < InpMinScore) continue;
            if(p.points[0].bar_index - last_start_bar < InpMinBarsBetween) continue;
            DrawWavePattern(p);
            DrawPriceTargets(p);
            DrawTimeZones(p);
            last_start_bar = p.points[0].bar_index;
            drawn++;
        }
    }
    else
    {
        WavePattern best_pattern;
        best_pattern.score = -1.0;
        for(int i = 0; i < candidates_count; i++)
            if(candidates[i].score > best_pattern.score)
                best_pattern = candidates[i];

        if(best_pattern.score >= 0 && (InpForceDraw || best_pattern.score >= InpMinScore))
        {
            DrawWavePattern(best_pattern);
            DrawPriceTargets(best_pattern);
            DrawTimeZones(best_pattern);
        }
    }

    return(rates_total);
}

//+------------------------------------------------------------------+
/**
 * @brief Advanced peak and trough detection function.
 * @param[out] peaks         An array to be filled with the found PeakPoint structures.
 * @param rates_total       Total number of bars available.
 * @param high              Array of high prices.
 * @param low               Array of low prices.
 * @param time              Array of bar timestamps.
 * @param start_index       The starting bar index for the search.
 * @param end_index         The ending bar index for the search.
 * @return int              The number of peaks found.
 *
 * This function identifies significant price pivots (peaks and troughs)
 * using a two-stage process. First, it finds all local highs and lows.
 * Second, it filters them based on "prominence," requiring a minimum
 * price change (measured in ATR multiples) between consecutive pivots.
 */
//+------------------------------------------------------------------+
int FindAdvancedPeaks(PeakPoint &peaks[], const int rates_total, const double &high[], const double &low[], const datetime &time[], const int start_index, const int end_index)
{
    // --- Get ATR values
    double atr_buffer[];
    if(CopyBuffer(h_atr, 0, 0, rates_total, atr_buffer) <= 0) return 0;

    PeakPoint all_pivots[];
    int pivots_count = 0;
    
    // --- Stage 1: Find all potential pivot points
    int left  = MathMax(InpPeakSearchPeriod, start_index);
    int right = MathMin(rates_total - InpPeakSearchPeriod - 1, end_index);
    for(int i = left; i <= right; i++)
    {
        bool is_peak = true;
        bool is_trough = true;
        for(int j = 1; j <= InpPeakSearchPeriod; j++)
        {
            if(high[i] < high[i-j] || high[i] <= high[i+j]) is_peak = false;
            if(low[i] > low[i-j] || low[i] >= low[i+j]) is_trough = false;
        }

        if(is_peak || is_trough)
        {
            if (pivots_count > 0 && all_pivots[pivots_count-1].is_peak == is_peak) continue;

            ArrayResize(all_pivots, pivots_count + 1);
            all_pivots[pivots_count].bar_index = i;
            all_pivots[pivots_count].time = time[i];
            all_pivots[pivots_count].is_peak = is_peak;
            all_pivots[pivots_count].price = is_peak ? high[i] : low[i];
            pivots_count++;
        }
    }
    
    // --- Stage 2: Filter by "prominence"
    int filtered_count = 0;
    if(pivots_count > 0)
    {
       ArrayResize(peaks, 1);
       peaks[0] = all_pivots[0];
       filtered_count = 1;
    }
    
    for(int i=1; i < pivots_count; i++)
    {
        double price_diff = MathAbs(all_pivots[i].price - peaks[filtered_count-1].price);
        
        if (price_diff > atr_buffer[all_pivots[i].bar_index] * InpPeakProminenceATR)
        {
             ArrayResize(peaks, filtered_count + 1);
             peaks[filtered_count] = all_pivots[i];
             filtered_count++;
        }
    }

    return filtered_count;
}


//+------------------------------------------------------------------+
/**
 * @brief Validates a pattern against core Elliott Wave rules.
 * @param[in,out] pattern The WavePattern to validate. The is_bullish flag is set here.
 * @return bool           True if the pattern is valid, false otherwise.
 *
 * This function checks a sequence of 6 points (forming 5 waves) against
 * the fundamental rules of an Elliott Wave impulse pattern:
 * 1. Wave 2 does not retrace more than 100% of Wave 1.
 * 2. Wave 4 does not retrace more than 100% of Wave 3 (and does not enter the territory of Wave 1).
 * 3. Wave 3 is never the shortest of the three impulse waves (1, 3, and 5).
 */
//+------------------------------------------------------------------+
bool ValidateElliottRules(WavePattern &pattern)
{
    PeakPoint p0 = pattern.points[0], p1 = pattern.points[1], p2 = pattern.points[2], 
              p3 = pattern.points[3], p4 = pattern.points[4], p5 = pattern.points[5];
    
    pattern.is_bullish = p1.price > p0.price;

    // Rule: Wave 2 cannot retrace beyond the start of Wave 1.
    if(pattern.is_bullish && p2.price < p0.price) return false;
    if(!pattern.is_bullish && p2.price > p0.price) return false;
    
    // Rule: Wave 4 cannot enter the price territory of Wave 1.
    if(pattern.is_bullish && p4.price < p1.price) return false;
    if(!pattern.is_bullish && p4.price > p1.price) return false;
    
    double w1_len = MathAbs(p1.price - p0.price);
    double w3_len = MathAbs(p3.price - p2.price);
    double w5_len = MathAbs(p5.price - p4.price);
    
    // Rule: Wave 3 is never the shortest impulse wave.
    if(w3_len < w1_len && w3_len < w5_len) return false;
    
    // Basic progression check
    if(pattern.is_bullish)
    {
        if(!(p1.price > p0.price && p2.price < p1.price && p3.price > p1.price && p4.price < p3.price && p5.price > p3.price))
            return false;
    }
    else // Bearish
    {
        if(!(p1.price < p0.price && p2.price > p1.price && p3.price < p1.price && p4.price > p3.price && p5.price < p3.price))
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
/**
 * @brief Calculates the total quality score for a given pattern.
 * @param pattern        The validated WavePattern to score.
 * @param rates_total    Total number of bars available.
 * @param tick_volume    Array of tick volumes.
 * @return double        The calculated total score.
 *
 * This function aggregates scores from different analysis dimensions:
 * Fibonacci relationships, volume dynamics, and momentum (RSI).
 */
//+------------------------------------------------------------------+
double CalculatePatternScore(const WavePattern &pattern, const int rates_total, const long &tick_volume[])
{
    double score = 0;
    score += ScoreFibonacci(pattern);
    if(InpUseVolume)
        score += ScoreVolume(pattern, rates_total, tick_volume);
    if(InpUseRSI)
        score += ScoreMomentum(pattern, rates_total);
    return score;
}

//--- Scoring Sub-functions ---

/**
 * @brief Scores the pattern based on Fibonacci relationships.
 * @param pattern The WavePattern to score.
 * @return double The score based on Fibonacci levels.
 *
 * Awards points if Wave 2 and Wave 4 are common Fibonacci retracements
 * of the preceding waves, and if Wave 3 is a common extension of Wave 1.
 */
double ScoreFibonacci(const WavePattern &pattern)
{
    double score = 0;
    PeakPoint p0=pattern.points[0], p1=pattern.points[1], p2=pattern.points[2], p3=pattern.points[3], p4=pattern.points[4], p5=pattern.points[5];
    
    double w1_len = MathAbs(p1.price - p0.price);
    if(w1_len == 0) return 0;
    
    // Ideal Wave 2 retracement
    double w2_retracement = MathAbs(p2.price - p1.price) / w1_len;
    if(w2_retracement >= 0.5 && w2_retracement <= 0.618) score += 35;

    // Ideal Wave 3 extension
    double w3_extension = MathAbs(p3.price - p2.price) / w1_len;
    if(w3_extension >= 1.618) score += 30;

    double w3_len = MathAbs(p3.price - p2.price);
    if(w3_len > 0)
    {
        // Ideal Wave 4 retracement
        double w4_retracement = MathAbs(p4.price - p3.price) / w3_len;
        if(w4_retracement >= 0.382 && w4_retracement <= 0.5) score += 20;
    }
    
    return score;
}

/**
 * @brief Scores the pattern based on volume dynamics.
 * @param pattern     The WavePattern to score.
 * @param rates_total Total number of bars available.
 * @param volume      Array of real volumes.
 * @return double     The score based on volume confirmation.
 *
 * Awards points if volume confirms the impulse waves. Typically, Wave 3
 * should have the highest volume, and volume should diminish in corrective waves
 * and the final Wave 5.
 */
double ScoreVolume(const WavePattern &pattern, const int rates_total, const long &volume[])
{
    double score = 0;
    double volume_ma[];
    double volume_double[];
    ArrayResize(volume_double, rates_total);
    
    // Convert long to double for MA calculation
    for(int i=0; i<rates_total; i++) volume_double[i] = (double)volume[i];
    
    // FIX: Use SimpleMAOnBuffer
    if(SimpleMAOnBuffer(rates_total, 0, 0, InpVolume_MA_Period, volume_double, volume_ma) < 0) return 0;

    long w1_vol=0, w3_vol=0, w5_vol=0;
    long w3_vol_ma_count = 0;
    
    for(int i=pattern.points[0].bar_index; i<=pattern.points[1].bar_index; i++) w1_vol += volume[i];
    for(int i=pattern.points[2].bar_index; i<=pattern.points[3].bar_index; i++)
    {
         w3_vol += volume[i];
         if(volume[i] > volume_ma[i] * 1.5) w3_vol_ma_count++;
    }
    for(int i=pattern.points[4].bar_index; i<=pattern.points[5].bar_index; i++) w5_vol += volume[i];
    
    if(w3_vol_ma_count > 0) score += 25; // Volume spikes in wave 3
    if(w3_vol > w1_vol && w3_vol > w5_vol) score += 20; // Wave 3 has highest volume
    if(w5_vol < w3_vol) score += 15; // Volume diminishes in wave 5
    
    return score;
}

/**
 * @brief Scores the pattern based on momentum (RSI).
 * @param pattern     The WavePattern to score.
 * @param rates_total Total number of bars available.
 * @return double     The score based on momentum confirmation.
 *
 * Awards points for classic momentum behavior:
 * 1. RSI should be strong during Wave 3 (overbought in uptrend, oversold in downtrend).
 * 2. Awards a high score for RSI divergence between Wave 3 and Wave 5, a classic sign
 *    of a pending reversal.
 */
double ScoreMomentum(const WavePattern &pattern, const int rates_total)
{
    double score = 0;
    double rsi_buffer[];
    
    if(CopyBuffer(h_rsi, 0, 0, rates_total, rsi_buffer) <= 0) return 0;
    
    double rsi_p1 = rsi_buffer[pattern.points[1].bar_index];
    double rsi_p3 = rsi_buffer[pattern.points[3].bar_index];
    double rsi_p5 = rsi_buffer[pattern.points[5].bar_index];

    if(pattern.is_bullish)
    {
        if(rsi_p3 > 70 && rsi_p3 > rsi_p1) score += 20; // Strong momentum in Wave 3
        // Divergence: higher high in price, lower high in RSI
        if(pattern.points[5].price > pattern.points[3].price && rsi_p5 < rsi_p3) score += 40;
    }
    else // Bearish
    {
        if(rsi_p3 < 30 && rsi_p3 < rsi_p1) score += 20; // Strong momentum in Wave 3
        // Divergence: lower low in price, higher low in RSI
        if(pattern.points[5].price < pattern.points[3].price && rsi_p5 > rsi_p3) score += 40;
    }

    return score;
}

//+------------------------------------------------------------------+
/**
 * @brief Draws the Elliott Wave pattern on the chart.
 * @param pattern The WavePattern to draw.
 *
 * This function draws the trend lines connecting the pivot points of the
 * pattern and adds text labels (1, 2, 3, 4, 5) at each point.
 */
//+------------------------------------------------------------------+
void DrawWavePattern(const WavePattern &pattern)
{
    for(int i=0; i<pattern.point_count - 1; i++)
    {
        string name = indicator_prefix + "Line_" + IntegerToString(i);
        string label = (i < 5) ? IntegerToString(i+1) : ShortToString((ushort)(65 + i - 5));
        
        ObjectCreate(0, name, OBJ_TREND, 0, pattern.points[i].time, pattern.points[i].price, pattern.points[i+1].time, pattern.points[i+1].price);
        ObjectSetInteger(0, name, OBJPROP_COLOR, InpImpulseColor);
        ObjectSetInteger(0, name, OBJPROP_STYLE, InpStyle);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, InpWidth);

        string label_name = indicator_prefix + "Label_" + IntegerToString(i+1);
        ObjectCreate(0, label_name, OBJ_TEXT, 0, pattern.points[i+1].time, pattern.points[i+1].price);
        ObjectSetString(0, label_name, OBJPROP_TEXT, label);
        ObjectSetInteger(0, label_name, OBJPROP_COLOR, InpImpulseColor);
        ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, pattern.points[i+1].is_peak ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
    }
}

/**
 * @brief Draws price target projections on the chart.
 * @param pattern The WavePattern used for projection.
 *
 * This function calculates and draws a potential price target for the end of
 * Wave 5, typically based on a Fibonacci relationship with a previous wave.
 * Here, it projects 61.8% of the length of Wave 3 from the end of Wave 4.
 */
void DrawPriceTargets(const WavePattern &pattern)
{
    if(pattern.point_count < 5) return;
    PeakPoint p2 = pattern.points[2], p3 = pattern.points[3], p4 = pattern.points[4];
    
    double w3_len = MathAbs(p3.price - p2.price);
    double target_price = pattern.is_bullish ? p4.price + w3_len * 0.618 : p4.price - w3_len * 0.618;

    string name = indicator_prefix + "Target_5";
    
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, target_price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, InpTargetColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetString(0, name, OBJPROP_TEXT, "5? " + DoubleToString(target_price, _Digits));
}

/**
 * @brief Draws Fibonacci Time Zones on the chart.
 * @param pattern The WavePattern used for the time analysis.
 *
 * This function draws vertical lines at future time intervals based on the
 * Fibonacci number sequence (13, 21, 34, ...), starting from the beginning
 * of the pattern. These lines suggest potential future dates for significant
 * trend changes.
 */
void DrawTimeZones(const WavePattern &pattern)
{
    int fib_numbers[] = {13, 21, 34, 55, 89, 144};
    datetime start_time = pattern.points[0].time;

    for(int i=0; i < ArraySize(fib_numbers); i++)
    {
        datetime target_time = start_time + (datetime)(fib_numbers[i] * PeriodSeconds(_Period));
        string name = indicator_prefix + "TimeZone_" + IntegerToString(fib_numbers[i]);
        
        ObjectCreate(0, name, OBJ_VLINE, 0, target_time, 0);
        ObjectSetInteger(0, name, OBJPROP_COLOR, InpTimeZoneColor);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
    }
}
//+------------------------------------------------------------------+