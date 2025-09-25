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

//--- Įtraukiame MA biblioteką
#include <MovingAverages.mqh>

//--- Įvesties parametrai vartotojui
input group           "ZigZag Settings"
input int             InpZigZagDepth        = 12;      // ZigZag gylis
input int             InpZigZagDeviation    = 5;       // ZigZag nuokrypis
input int             InpZigZagBackstep     = 3;       // ZigZag žingsnis atgal

//--- Istorijos ribojimo nustatymas
input group           "History Settings"
input int             InpLookbackBars       = 2000;    // Kiek žvakių atgal skaičiuoti ir piešti

//--- Indikatorių patvirtinimo parametrai
input group           "Confirmation Indicator Settings"
input int             InpRSI_Period         = 14;      // RSI Periodas
input int             InpMACD_Fast          = 12;      // MACD Fast EMA
input int             InpMACD_Slow          = 26;      // MACD Slow EMA
input int             InpMACD_Signal        = 9;       // MACD Signal SMA
input int             InpVolume_MA_Period   = 20;      // Apimties slankusis vidurkis
input bool            InpUseRSI             = true;    // Naudoti RSI patvirtinimą
input bool            InpUseVolume          = true;    // Naudoti apimties patvirtinimą

//--- Piešimo nustatymai
input group           "Drawing Settings"
input color           InpImpulseColor       = clrDodgerBlue; // Impulso bangų spalva
input color           InpCorrectionColor    = clrOrangeRed;  // Korekcijos bangų spalva
input color           InpTargetColor        = clrGoldenrod;  // Kainos prognozių spalva
input color           InpTimeZoneColor      = clrGray;       // Laiko zonų spalva
input ENUM_LINE_STYLE InpStyle              = STYLE_SOLID;   // Linijų stilius
input int             InpWidth              = 2;             // Linijų storis
input bool            InpForceDraw          = false;   // Priverstinai piešti paskutinius 6 pivot (testui)

//--- Formacijų atrankos / piešimo parametrai
input group           "Pattern Selection"
input bool            InpDrawAllPatterns    = true;    // Piešti kelias formacijas istorijoje
input double          InpMinScore           = 30.0;    // Min balas, kad būtų piešiama
input int             InpMinBarsBetween     = 50;      // Min barų tarp formacijų pradžios
input int             InpMaxPatterns        = 5;       // Maks. piešiamų formacijų skaičius

//--- Duomenų struktūros
struct PeakPoint
{
    double   price;
    datetime time;
    int      bar_index;
    bool     is_peak; // true = pikas, false = dugnas
};

struct WavePattern
{
    PeakPoint points[9]; // 0-1-2-3-4-5-A-B-C
    int       point_count;
    double    score;
    bool      is_bullish;
};

//--- Globalūs kintamieji ir indikatorių handle
int h_rsi, h_macd, h_atr, h_volume;
string indicator_prefix;

//+------------------------------------------------------------------+
//| Indikatoriaus inicializacija                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Unikalus prefiksas grafiniams objektams
    indicator_prefix = "EWA_" + IntegerToString(ChartID()) + "_";

    //--- Indikatorių handle sukūrimas
    h_atr = iATR(_Symbol, _Period, 14);
    h_rsi = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_CLOSE);
    h_macd = iMACD(_Symbol, _Period, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);
    h_volume = iVolumes(_Symbol, _Period, VOLUME_TICK);

    if(h_rsi == INVALID_HANDLE || h_macd == INVALID_HANDLE || h_atr == INVALID_HANDLE || h_volume == INVALID_HANDLE)
    {
        Print("Nepavyko sukurti indikatorių handle. Klaidos kodas: ", GetLastError());
        return(INIT_FAILED);
    }

    IndicatorSetString(INDICATOR_SHORTNAME, "ElliottWaveAdvanced");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Indikatoriaus deinicializacija                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Atlaisviname handle
    IndicatorRelease(h_rsi);
    IndicatorRelease(h_macd);
    IndicatorRelease(h_atr);
    IndicatorRelease(h_volume);

    //--- Išvalome visus grafinius objektus
    ObjectsDeleteAll(0, indicator_prefix);
}

//+------------------------------------------------------------------+
//| Pagrindinė skaičiavimo funkcija                                  |
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
    //--- Valome senus objektus
    ObjectsDeleteAll(0, indicator_prefix);

    // 1. Gauname patikimus pikus ir dugnus
    PeakPoint peaks[];
    int peaks_found = FindZigZag(peaks, rates_total, high, low, time);
    if(peaks_found < 6) return(rates_total);

    // 2. Ieškome ir įvertiname visus galimus modelius
    WavePattern candidates[];
    int candidates_count = 0;

    for(int i = 0; i < peaks_found - 5; i++)
    {
        WavePattern current_pattern;
        current_pattern.point_count = 0;

        for(int j=0; j<6; j++)
        {
            current_pattern.points[j] = peaks[i+j];
        }
        current_pattern.point_count = 6;

        // Patikriname pagrindines taisykles
        if(ValidateElliottRules(current_pattern))
        {
            // Jei taisyklės geros, apskaičiuojame kokybės balą
            current_pattern.score = CalculatePatternScore(current_pattern, rates_total, tick_volume);
            ArrayResize(candidates, candidates_count + 1);
            candidates[candidates_count] = current_pattern;
            candidates_count++;
        }
    }

    if(candidates_count == 0 && !InpForceDraw) return(rates_total);

    // 3. Piešiame: visus arba geriausią
    if(InpDrawAllPatterns)
    {
        int drawn = 0;
        int last_start_bar = -InpMinBarsBetween - 1;
        // Rūšiuojame pagal score mažėjančia tvarka (paprastas selection)
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
            CalculateABCProjection(p);
            DrawWavePattern(p);
            DrawABCProjection(p);
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
            CalculateABCProjection(best_pattern);
            DrawWavePattern(best_pattern);
            DrawABCProjection(best_pattern);
            DrawPriceTargets(best_pattern);
            DrawTimeZones(best_pattern);
        }
    }

    return(rates_total);
}

//+------------------------------------------------------------------+
//| Standartinė ZigZag implementacija                                |
//+------------------------------------------------------------------+
int FindZigZag(PeakPoint &peaks[], const int rates_total, const double &high[], const double &low[], const datetime &time[])
{
    ArrayFree(peaks);
    if(rates_total < InpZigZagDepth) return 0;

    int limit = rates_total - InpLookbackBars;
    if(limit < 0) limit = 0;

    double high_buffer[], low_buffer[];
    ArrayResize(high_buffer, rates_total); ArrayInitialize(high_buffer, 0.0);
    ArrayResize(low_buffer, rates_total);  ArrayInitialize(low_buffer, 0.0);

    for(int i = rates_total - InpZigZagDepth - 1; i >= limit; i--)
    {
        double d_high = high[iHighest(NULL, _Period, MODE_HIGH, InpZigZagDepth, i)];
        if(d_high == high[i]) high_buffer[i] = d_high;

        double d_low = low[iLowest(NULL, _Period, MODE_LOW, InpZigZagDepth, i)];
        if(d_low == low[i]) low_buffer[i] = d_low;
    }

    double zigzag_buffer[];
    ArrayResize(zigzag_buffer, rates_total); ArrayInitialize(zigzag_buffer, 0.0);

    int what = 0;
    int last_pivot_pos = 0;
    double last_pivot_val = 0.0;
    int last_confirmed_pos = 0;

    for(int i = limit; i < rates_total; i++)
    {
        if(what == 0)
        {
            if(high_buffer[i] != 0.0) { what = 1; last_pivot_pos = i; last_pivot_val = high_buffer[i]; }
            else if(low_buffer[i] != 0.0) { what = -1; last_pivot_pos = i; last_pivot_val = low_buffer[i]; }
            continue;
        }

        if(what == 1)
        {
            if(low_buffer[i] != 0.0 && high_buffer[i] == 0.0 && low_buffer[i] < last_pivot_val)
            {
                if(last_pivot_val - low_buffer[i] > InpZigZagDeviation * _Point && i - last_pivot_pos >= InpZigZagBackstep)
                {
                    zigzag_buffer[last_pivot_pos] = last_pivot_val;
                    last_confirmed_pos = last_pivot_pos;
                    what = -1; last_pivot_pos = i; last_pivot_val = low_buffer[i];
                }
            }
            if(high_buffer[i] != 0.0 && high_buffer[i] > last_pivot_val && i > last_confirmed_pos)
            {
                last_pivot_pos = i; last_pivot_val = high_buffer[i];
            }
        }
        else
        {
            if(high_buffer[i] != 0.0 && low_buffer[i] == 0.0 && high_buffer[i] > last_pivot_val)
            {
                if(high_buffer[i] - last_pivot_val > InpZigZagDeviation * _Point && i - last_pivot_pos >= InpZigZagBackstep)
                {
                    zigzag_buffer[last_pivot_pos] = last_pivot_val;
                    last_confirmed_pos = last_pivot_pos;
                    what = 1; last_pivot_pos = i; last_pivot_val = high_buffer[i];
                }
            }
            if(low_buffer[i] != 0.0 && low_buffer[i] < last_pivot_val && i > last_confirmed_pos)
            {
                last_pivot_pos = i; last_pivot_val = low_buffer[i];
            }
        }
    }

    if(last_pivot_val != 0.0) zigzag_buffer[last_pivot_pos] = last_pivot_val;

    int count = 0;
    for(int i = limit; i < rates_total; i++)
    {
        if(zigzag_buffer[i] != 0.0)
        {
            ArrayResize(peaks, count+1);
            peaks[count].price = zigzag_buffer[i];
            peaks[count].bar_index = i;
            peaks[count].time = time[i];

            // Nustatome ar pikas ar dugnas
            if(count > 0)
            {
                peaks[count].is_peak = (peaks[count].price > peaks[count-1].price);
            } else {
                // Pirmajam taškui negalime nustatyti, bet tai nėra kritiška
                peaks[count].is_peak = false;
            }
            count++;
        }
    }

    // Patiksliname pirmojo taško tipą
    if(count > 1)
    {
        peaks[0].is_peak = !peaks[1].is_peak;
    }

    return count;
}


//+------------------------------------------------------------------+
//| Pagrindinių Elioto taisyklių tikrinimas                          |
//+------------------------------------------------------------------+
bool ValidateElliottRules(WavePattern &pattern)
{
    PeakPoint p0 = pattern.points[0], p1 = pattern.points[1], p2 = pattern.points[2],
              p3 = pattern.points[3], p4 = pattern.points[4], p5 = pattern.points[5];

    pattern.is_bullish = p1.price > p0.price;

    if(pattern.is_bullish && p2.price < p0.price) return false;
    if(!pattern.is_bullish && p2.price > p0.price) return false;

    if(pattern.is_bullish && p4.price < p1.price) return false;
    if(!pattern.is_bullish && p4.price > p1.price) return false;

    double w1_len = MathAbs(p1.price - p0.price);
    double w3_len = MathAbs(p3.price - p2.price);
    double w5_len = MathAbs(p5.price - p4.price);

    if(w3_len < w1_len && w3_len < w5_len) return false;

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
//| Kokybės balo apskaičiavimas                                      |
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

//--- Balų skaičiavimo sub-funkcijos ---

double ScoreFibonacci(const WavePattern &pattern)
{
    double score = 0;
    PeakPoint p0=pattern.points[0], p1=pattern.points[1], p2=pattern.points[2], p3=pattern.points[3], p4=pattern.points[4], p5=pattern.points[5];

    double w1_len = MathAbs(p1.price - p0.price);
    if(w1_len == 0) return 0;

    double w2_retracement = MathAbs(p2.price - p1.price) / w1_len;
    if(w2_retracement >= 0.5 && w2_retracement <= 0.618) score += 35;

    double w3_extension = MathAbs(p3.price - p2.price) / w1_len;
    if(w3_extension >= 1.618) score += 30;

    double w3_len = MathAbs(p3.price - p2.price);
    if(w3_len > 0)
    {
        double w4_retracement = MathAbs(p4.price - p3.price) / w3_len;
        if(w4_retracement >= 0.382 && w4_retracement <= 0.5) score += 20;
    }

    return score;
}

double ScoreVolume(const WavePattern &pattern, const int rates_total, const long &volume[])
{
    double score = 0;
    double volume_ma[];
    double volume_double[];
    ArrayResize(volume_double, rates_total);

    // Konvertuojame long į double MA skaičiavimui
    for(int i=0; i<rates_total; i++) volume_double[i] = (double)volume[i];

    // PATAISYMAS: Naudojame SimpleMAOnBuffer
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

    if(w3_vol_ma_count > 0) score += 25;
    if(w3_vol > w1_vol && w3_vol > w5_vol) score += 20;
    if(w5_vol < w3_vol) score += 15;

    return score;
}

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
        if(rsi_p3 > 70 && rsi_p3 > rsi_p1) score += 20;
        if(pattern.points[5].price > pattern.points[3].price && rsi_p5 < rsi_p3) score += 40;
    }
    else // Bearish
    {
        if(rsi_p3 < 30 && rsi_p3 < rsi_p1) score += 20;
        if(pattern.points[5].price < pattern.points[3].price && rsi_p5 > rsi_p3) score += 40;
    }

    return score;
}

//+------------------------------------------------------------------+
//| Piešimo funkcijos                                                |
//+------------------------------------------------------------------+
void DrawWavePattern(const WavePattern &pattern)
{
    // Piešiame tik impulsines bangas (0-5)
    for(int i=0; i<5; i++)
    {
        string name = indicator_prefix + "Line_" + IntegerToString(i);
        string label = IntegerToString(i+1);

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
//| ABC Prognozės skaičiavimas ir piešimas                           |
//+------------------------------------------------------------------+
void CalculateABCProjection(WavePattern &pattern)
{
    if(pattern.point_count < 6) return;

    PeakPoint p4 = pattern.points[4];
    PeakPoint p5 = pattern.points[5];

    double wave_5_len = MathAbs(p5.price - p4.price);

    // Prognozuojame A tašką
    pattern.points[6].price = pattern.is_bullish ? p5.price - wave_5_len * 0.618 : p5.price + wave_5_len * 0.618;
    pattern.points[6].bar_index = p5.bar_index + (p5.bar_index - p4.bar_index);
    pattern.points[6].time = p5.time + (p5.time - p4.time);
    pattern.points[6].is_peak = !pattern.is_bullish;

    // Prognozuojame B tašką
    double wave_A_len = MathAbs(pattern.points[6].price - p5.price);
    pattern.points[7].price = pattern.is_bullish ? pattern.points[6].price + wave_A_len * 0.5 : pattern.points[6].price - wave_A_len * 0.5;
    pattern.points[7].bar_index = pattern.points[6].bar_index + (pattern.points[6].bar_index - p5.bar_index);
    pattern.points[7].time = pattern.points[6].time + (pattern.points[6].time - p5.time);
    pattern.points[7].is_peak = pattern.is_bullish;

    // Prognozuojame C tašką
    pattern.points[8].price = pattern.is_bullish ? pattern.points[7].price - wave_A_len : pattern.points[7].price + wave_A_len;
    pattern.points[8].bar_index = pattern.points[7].bar_index + (pattern.points[7].bar_index - pattern.points[6].bar_index);
    pattern.points[8].time = pattern.points[7].time + (pattern.points[7].time - pattern.points[6].time);
    pattern.points[8].is_peak = !pattern.is_bullish;

    pattern.point_count = 9;
}

void DrawABCProjection(const WavePattern &pattern)
{
    if(pattern.point_count < 9) return;

    string abc[] = {"A", "B", "C"};

    // Linija nuo 5 iki A
    ObjectCreate(0, indicator_prefix + "Line_5A", OBJ_TREND, 0, pattern.points[5].time, pattern.points[5].price, pattern.points[6].time, pattern.points[6].price);
    ObjectSetInteger(0, indicator_prefix + "Line_5A", OBJPROP_COLOR, InpCorrectionColor);
    ObjectSetInteger(0, indicator_prefix + "Line_5A", OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, indicator_prefix + "Line_5A", OBJPROP_WIDTH, InpWidth);

    for(int i=6; i<8; i++)
    {
        string name = indicator_prefix + "Line_" + abc[i-5] + abc[i-4];
        ObjectCreate(0, name, OBJ_TREND, 0, pattern.points[i].time, pattern.points[i].price, pattern.points[i+1].time, pattern.points[i+1].price);
        ObjectSetInteger(0, name, OBJPROP_COLOR, InpCorrectionColor);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, InpWidth);
    }

    for(int i=6; i<9; i++)
    {
        string label_name = indicator_prefix + "Label_" + abc[i-6];
        ObjectCreate(0, label_name, OBJ_TEXT, 0, pattern.points[i].time, pattern.points[i].price);
        ObjectSetString(0, label_name, OBJPROP_TEXT, abc[i-6]);
        ObjectSetInteger(0, label_name, OBJPROP_COLOR, InpCorrectionColor);
        ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, pattern.points[i].is_peak ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
    }
}
//+------------------------------------------------------------------+