//+------------------------------------------------------------------+
//|                                     Trinity_Eliot_Pro.mq5 |
//|                             Copyright 2025, Gemini AI Labs      |
//|                                     Version 3.2 (Final Corrected)|
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Gemini AI Labs"
#property link      "https"
#property version   "3.2"
#property description "Profesionalus Elioto Bangų indikatorius su ZigZag, balų sistema ir ABC prognoze."

#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Įtraukiame reikalingas bibliotekas
#include <Object.mqh>
#include <Arrays\ArrayObj.mqh>

//--- Indikatoriaus Įvesties Parametrai ---
input group "ZigZag Settings"
input int    InpZigZagDepth      = 12;     // Periodas piko/dugno paieškai
input int    InpZigZagDeviation  = 5;      // Minimalus piko/dugno dydis (punktais)
input int    InpZigZagBackstep   = 3;      // Minimalus atstumas tarp pikų/dugnų

input group "History & Performance"
input int    InpMaxBars          = 2000;   // Kiek žvakių analizuoti atgal

input group "Pattern Scoring Weights"
input double InpWeightFib        = 1.0;    // Fibonacci santykių svoris
input double InpWeightRSI        = 1.5;    // RSI divergencijos svoris
input int    InpRSI_Period       = 14;     // RSI periodas

input group "Drawing & Filtering"
input color  InpImpulseColor     = clrDodgerBlue;
input color  InpCorrectionColor  = clrOrangeRed;
input ENUM_LINE_STYLE InpStyle   = STYLE_SOLID;
input int    InpWidth            = 2;
input double InpMinScore         = 40.0;   // Minimalus balas modeliui piešti
input int    InpMaxPatterns      = 3;      // Kiek daugiausiai modelių piešti


//+------------------------------------------------------------------+
//| Klasė, aprašanti vieną piko/dugno tašką (ekstremumą)             |
//+------------------------------------------------------------------+
class CPoint : public CObject
{
public:
    int      bar;
    datetime time;
    double   price;

             CPoint(int b=0, datetime t=0, double p=0) : bar(b), time(t), price(p) {}
};

//+------------------------------------------------------------------+
//| Klasė, aprašanti visą Elioto bangų modelį (5+3 bangos)           |
//+------------------------------------------------------------------+
class CWavePattern : public CObject
{
public:
    CPoint   *p0, *p1, *p2, *p3, *p4, *p5, *p6, *p7, *p8;
    bool     is_bullish;
    double   score;
    int      pattern_id;

             CWavePattern(void) { Initialize(); }
            ~CWavePattern(void) { Cleanup(); }

    void Initialize()
    {
        p0 = p1 = p2 = p3 = p4 = p5 = p6 = p7 = p8 = NULL;
        score = 0; is_bullish = false; pattern_id = 0;
    }

    void Cleanup()
    {
        if(CheckPointer(p0)==POINTER_DYNAMIC) delete p0;
        if(CheckPointer(p1)==POINTER_DYNAMIC) delete p1;
        if(CheckPointer(p2)==POINTER_DYNAMIC) delete p2;
        if(CheckPointer(p3)==POINTER_DYNAMIC) delete p3;
        if(CheckPointer(p4)==POINTER_DYNAMIC) delete p4;
        if(CheckPointer(p5)==POINTER_DYNAMIC) delete p5;
        if(CheckPointer(p6)==POINTER_DYNAMIC) delete p6;
        if(CheckPointer(p7)==POINTER_DYNAMIC) delete p7;
        if(CheckPointer(p8)==POINTER_DYNAMIC) delete p8;
    }

    virtual int Compare(const CObject *node, const int mode=0) const
    {
        const CWavePattern *other = (const CWavePattern*)node;
        if(other == NULL) return 0;
        if(score < other->score) return -1;
        if(score > other->score) return 1;
        return 0;
    }

    void SetPoint(int index, int bar, datetime time, double price)
    {
        CPoint *new_point = new CPoint(bar, time, price);
        switch(index)
        {
            case 0: if(CheckPointer(p0)==POINTER_DYNAMIC) delete p0; p0 = new_point; break;
            case 1: if(CheckPointer(p1)==POINTER_DYNAMIC) delete p1; p1 = new_point; break;
            case 2: if(CheckPointer(p2)==POINTER_DYNAMIC) delete p2; p2 = new_point; break;
            case 3: if(CheckPointer(p3)==POINTER_DYNAMIC) delete p3; p3 = new_point; break;
            case 4: if(CheckPointer(p4)==POINTER_DYNAMIC) delete p4; p4 = new_point; break;
            case 5: if(CheckPointer(p5)==POINTER_DYNAMIC) delete p5; p5 = new_point; break;
            case 6: if(CheckPointer(p6)==POINTER_DYNAMIC) delete p6; p6 = new_point; break;
            case 7: if(CheckPointer(p7)==POINTER_DYNAMIC) delete p7; p7 = new_point; break;
            case 8: if(CheckPointer(p8)==POINTER_DYNAMIC) delete p8; p8 = new_point; break;
            default: delete new_point; return;
        }
    }
};

//+------------------------------------------------------------------+
//| Pagrindinė indikatoriaus klasė                                   |
//+------------------------------------------------------------------+
class CElliottWaveIndicator
{
private:
    string   m_prefix;
    long     m_chart_id;
    int      m_last_calc_bars;
    int      h_rsi;

    CArrayObj m_patterns;
    CArrayObj m_zigzag_pivots;

    void     FindZigZagPivots(const int rates_total, const double &high[], const double &low[], const datetime &time[]);
    void     FindWavePatterns(void);
    bool     ValidateElliottRules(CWavePattern *pattern);
    double   CalculatePatternScore(CWavePattern *pattern);
    void     CalculateABCProjection(CWavePattern *pattern);
    void     DrawManager(void);
    void     DrawPattern(CWavePattern *pattern);
    void     DrawTrendLine(CPoint *start, CPoint *end, color clr, ENUM_LINE_STYLE style, string pattern_id_str, string wave_id_str);
    void     DrawLabel(CPoint *point, string text, color clr, ENUM_ANCHOR_POINT anchor, string pattern_id_str, string label_id_str);
    void     CleanupObjects(void);

public:
             CElliottWaveIndicator(void);
            ~CElliottWaveIndicator(void);

    int      OnInit(void);
    void     OnDeinit(const int reason);
    int      OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[]);
};

CElliottWaveIndicator g_ew_indicator;

//--- Implementacija ---

CElliottWaveIndicator::CElliottWaveIndicator(void) : m_last_calc_bars(0) {}
CElliottWaveIndicator::~CElliottWaveIndicator(void) {}

int CElliottWaveIndicator::OnInit(void)
{
    m_chart_id = ChartID();
    m_prefix = "EW_Pro_" + (string)m_chart_id + "_";
    m_last_calc_bars = 0;

    h_rsi = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_CLOSE);
    if(h_rsi == INVALID_HANDLE) { Print("Nepavyko sukurti RSI handle."); }

    IndicatorSetString(INDICATOR_SHORTNAME, "ElliottWave Pro");
    m_patterns.FreeMode(true);
    m_zigzag_pivots.FreeMode(true);
    return(INIT_SUCCEEDED);
}

void CElliottWaveIndicator::OnDeinit(const int reason)
{
    IndicatorRelease(h_rsi);
    CleanupObjects();
}

int CElliottWaveIndicator::OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[])
{
    if(rates_total < 200) return 0;

    if(rates_total == m_last_calc_bars && prev_calculated > 0)
    {
       return(rates_total);
    }

    m_last_calc_bars = rates_total;

    FindZigZagPivots(rates_total, high, low, time);
    FindWavePatterns();
    DrawManager();

    return(rates_total);
}

void CElliottWaveIndicator::FindZigZagPivots(const int rates_total, const double &high[], const double &low[], const datetime &time[])
{
    m_zigzag_pivots.Clear();

    if(rates_total < InpZigZagDepth) return;

    int limit = rates_total - InpMaxBars;
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

    for(int i = limit; i < rates_total; i++)
    {
        if(zigzag_buffer[i] != 0.0)
        {
            if(m_zigzag_pivots.Total() > 0)
            {
                CPoint *last_pt = (CPoint*)m_zigzag_pivots.At(m_zigzag_pivots.Total()-1);
                if(last_pt != NULL && last_pt->bar == i) continue;
            }
            m_zigzag_pivots.Add(new CPoint(i, time[i], zigzag_buffer[i]));
        }
    }
}

void CElliottWaveIndicator::FindWavePatterns(void)
{
    m_patterns.Clear();

    if(m_zigzag_pivots.Total() < 6) return;

    for(int i = 0; i <= m_zigzag_pivots.Total() - 6; i++)
    {
        CWavePattern *pattern = new CWavePattern();
        bool points_ok = true;
        for(int j=0; j<6; j++)
        {
            CPoint *p = (CPoint*)m_zigzag_pivots.At(i+j);
            if(p == NULL) { points_ok=false; break; }
            pattern->SetPoint(j, p->bar, p->time, p->price);
        }

        if(!points_ok) { delete pattern; continue; }

        if(ValidateElliottRules(pattern))
        {
            pattern->score = CalculatePatternScore(pattern);
            CalculateABCProjection(pattern);
            m_patterns.Add(pattern);
        }
        else
        {
            delete pattern;
        }
    }
}

bool CElliottWaveIndicator::ValidateElliottRules(CWavePattern *pattern)
{
    if (pattern == NULL || pattern->p0 == NULL || pattern->p1 == NULL || pattern->p2 == NULL || pattern->p3 == NULL || pattern->p4 == NULL || pattern->p5 == NULL)
        return false;

    pattern->is_bullish = pattern->p1->price > pattern->p0->price;

    if(pattern->is_bullish && pattern->p2->price < pattern->p0->price) return false;
    if(!pattern->is_bullish && pattern->p2->price > pattern->p0->price) return false;

    if(pattern->is_bullish && pattern->p4->price < pattern->p1->price) return false;
    if(!pattern->is_bullish && pattern->p4->price > pattern->p1->price) return false;

    double w1_len = MathAbs(pattern->p1->price - pattern->p0->price);
    double w3_len = MathAbs(pattern->p3->price - pattern->p2->price);
    double w5_len = MathAbs(pattern->p5->price - pattern->p4->price);

    if(w3_len < w1_len && w3_len < w5_len) return false;

    if(pattern->is_bullish)
    {
        if(!(pattern->p1->price > pattern->p0->price && pattern->p2->price < pattern->p1->price && pattern->p3->price > pattern->p1->price &&
             pattern->p4->price < pattern->p3->price && pattern->p5->price > pattern->p3->price && pattern->p3->price > pattern->p1->price))
            return false;
    }
    else
    {
        if(!(pattern->p1->price < pattern->p0->price && pattern->p2->price > pattern->p1->price && pattern->p3->price < pattern->p1->price &&
             pattern->p4->price > pattern->p3->price && pattern->p5->price < pattern->p3->price && pattern->p3->price < pattern->p1->price))
            return false;
    }

    return true;
}

double CElliottWaveIndicator::CalculatePatternScore(CWavePattern *pattern)
{
    if (pattern == NULL || pattern->p0 == NULL || pattern->p1 == NULL || pattern->p2 == NULL || pattern->p3 == NULL || pattern->p4 == NULL || pattern->p5 == NULL)
        return 0.0;

    double score_fib = 0.0, score_rsi = 0.0;

    double w1_len = MathAbs(pattern->p1->price - pattern->p0->price);
    if(w1_len > 0)
    {
        double w2_retracement = MathAbs(pattern->p2->price - pattern->p1->price) / w1_len;
        if(w2_retracement >= 0.5 && w2_retracement <= 0.618) score_fib += 35;
        else if(w2_retracement >= 0.382 && w2_retracement <= 0.786) score_fib += 15;

        double w3_extension = MathAbs(pattern->p3->price - pattern->p2->price) / w1_len;
        if(w3_extension >= 1.618) score_fib += 30;
        if(w3_extension >= 2.618) score_fib += 10;
    }

    double w3_len = MathAbs(pattern->p3->price - pattern->p2->price);
    if(w3_len > 0)
    {
        double w4_retracement = MathAbs(pattern->p4->price - pattern->p3->price) / w3_len;
        if(w4_retracement >= 0.382 && w4_retracement <= 0.5) score_fib += 20;
    }

    if(h_rsi != INVALID_HANDLE)
    {
        double rsi_buffer[];
        if(CopyBuffer(h_rsi, 0, 0, m_last_calc_bars, rsi_buffer) > 0)
        {
            double rsi3 = rsi_buffer[pattern->p3->bar];
            double rsi5 = rsi_buffer[pattern->p5->bar];

            if(pattern->is_bullish && pattern->p5->price > pattern->p3->price && rsi5 < rsi3) score_rsi += 40;
            if(!pattern->is_bullish && pattern->p5->price < pattern->p3->price && rsi5 > rsi3) score_rsi += 40;
        }
    }

    return score_fib * InpWeightFib + score_rsi * InpWeightRSI;
}

void CElliottWaveIndicator::CalculateABCProjection(CWavePattern *pattern)
{
    if(pattern == NULL || pattern->p5 == NULL || pattern->p4 == NULL) return;

    double wave_5_len = MathAbs(pattern->p5->price - pattern->p4->price);

    double price_A = pattern->is_bullish ? pattern->p5->price - wave_5_len * 0.618 : pattern->p5->price + wave_5_len * 0.618;
    int bar_A = pattern->p5->bar + (pattern->p5->bar - pattern->p4->bar);
    datetime time_A = pattern->p5->time + (pattern->p5->time - pattern->p4->time);
    pattern->SetPoint(6, bar_A, time_A, price_A);

    if(pattern->p6 == NULL) return;
    double wave_A_len = MathAbs(pattern->p6->price - pattern->p5->price);
    double price_B = pattern->is_bullish ? pattern->p6->price + wave_A_len * 0.5 : pattern->p6->price - wave_A_len * 0.5;
    int bar_B = bar_A + (bar_A - pattern->p5->bar);
    datetime time_B = time_A + (time_A - pattern->p5->time);
    pattern->SetPoint(7, bar_B, time_B, price_B);

    if(pattern->p7 == NULL) return;
    double price_C = pattern->is_bullish ? pattern->p7->price - wave_A_len : pattern->p7->price + wave_A_len;
    int bar_C = bar_B + (bar_B - bar_A);
    datetime time_C = time_B + (time_B - time_A);
    pattern->SetPoint(8, bar_C, time_C, price_C);
}

void CElliottWaveIndicator::DrawManager(void)
{
    CleanupObjects();
    m_patterns.Sort();

    int drawn_count = 0;
    for(int i = m_patterns.Total() - 1; i >= 0 && drawn_count < InpMaxPatterns; i--)
    {
        CWavePattern *pattern = (CWavePattern*)m_patterns.At(i);
        if(pattern == NULL || pattern->score < InpMinScore) continue;

        pattern->pattern_id = drawn_count;
        DrawPattern(pattern);
        drawn_count++;
    }
}

void CElliottWaveIndicator::DrawPattern(CWavePattern *pattern)
{
    if(pattern == NULL) return;

    string id_str = IntegerToString(pattern->pattern_id);

    if(pattern->p0 && pattern->p1) DrawTrendLine(pattern->p0, pattern->p1, InpImpulseColor, InpStyle, id_str, "Impulse_0");
    if(pattern->p1 && pattern->p2) DrawTrendLine(pattern->p1, pattern->p2, InpImpulseColor, InpStyle, id_str, "Impulse_1");
    if(pattern->p2 && pattern->p3) DrawTrendLine(pattern->p2, pattern->p3, InpImpulseColor, InpStyle, id_str, "Impulse_2");
    if(pattern->p3 && pattern->p4) DrawTrendLine(pattern->p3, pattern->p4, InpImpulseColor, InpStyle, id_str, "Impulse_3");
    if(pattern->p4 && pattern->p5) DrawTrendLine(pattern->p4, pattern->p5, InpImpulseColor, InpStyle, id_str, "Impulse_4");

    if(pattern->p1) DrawLabel(pattern->p1, "1", InpImpulseColor, (pattern->is_bullish ? ANCHOR_TOP : ANCHOR_BOTTOM), id_str, "Label_1");
    if(pattern->p2) DrawLabel(pattern->p2, "2", InpImpulseColor, (pattern->is_bullish ? ANCHOR_BOTTOM : ANCHOR_TOP), id_str, "Label_2");
    if(pattern->p3) DrawLabel(pattern->p3, "3", InpImpulseColor, (pattern->is_bullish ? ANCHOR_TOP : ANCHOR_BOTTOM), id_str, "Label_3");
    if(pattern->p4) DrawLabel(pattern->p4, "4", InpImpulseColor, (pattern->is_bullish ? ANCHOR_BOTTOM : ANCHOR_TOP), id_str, "Label_4");
    if(pattern->p5) DrawLabel(pattern->p5, "5", InpImpulseColor, (pattern->is_bullish ? ANCHOR_TOP : ANCHOR_BOTTOM), id_str, "Label_5");

    if(pattern->p5 && pattern->p6) DrawTrendLine(pattern->p5, pattern->p6, InpCorrectionColor, STYLE_DOT, id_str, "Correction_A");
    if(pattern->p6 && pattern->p7) DrawTrendLine(pattern->p6, pattern->p7, InpCorrectionColor, STYLE_DOT, id_str, "Correction_B");
    if(pattern->p7 && pattern->p8) DrawTrendLine(pattern->p7, pattern->p8, InpCorrectionColor, STYLE_DOT, id_str, "Correction_C");

    if(pattern->p6) DrawLabel(pattern->p6, "A", InpCorrectionColor, (pattern->is_bullish ? ANCHOR_BOTTOM : ANCHOR_TOP), id_str, "Label_A");
    if(pattern->p7) DrawLabel(pattern->p7, "B", InpCorrectionColor, (pattern->is_bullish ? ANCHOR_TOP : ANCHOR_BOTTOM), id_str, "Label_B");
    if(pattern->p8) DrawLabel(pattern->p8, "C", InpCorrectionColor, (pattern->is_bullish ? ANCHOR_BOTTOM : ANCHOR_TOP), id_str, "Label_C");
}

void CElliottWaveIndicator::DrawTrendLine(CPoint *start, CPoint *end, color clr, ENUM_LINE_STYLE style, string pattern_id_str, string wave_id_str)
{
    string name = m_prefix + wave_id_str + "_" + pattern_id_str;
    ObjectCreate(m_chart_id, name, OBJ_TREND, 0, start->time, start->price, end->time, end->price);
    ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(m_chart_id, name, OBJPROP_STYLE, style);
    ObjectSetInteger(m_chart_id, name, OBJPROP_WIDTH, InpWidth);
}

void CElliottWaveIndicator::DrawLabel(CPoint *point, string text, color clr, ENUM_ANCHOR_POINT anchor, string pattern_id_str, string label_id_str)
{
    string name = m_prefix + label_id_str + "_" + pattern_id_str;
    ObjectCreate(m_chart_id, name, OBJ_TEXT, 0, point->time, point->price);
    ObjectSetString(m_chart_id, name, OBJPROP_TEXT, text);
    ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(m_chart_id, name, OBJPROP_ANCHOR, anchor);
    ObjectSetInteger(m_chart_id, name, OBJPROP_FONTSIZE, 8);
}


void CElliottWaveIndicator::CleanupObjects(void)
{
    ObjectsDeleteAll(m_chart_id, m_prefix);
}

//--- MQL5 standartinės funkcijos ---

int OnInit() { return(g_ew_indicator.OnInit()); }
void OnDeinit(const int reason) { g_ew_indicator.OnDeinit(reason); }
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[])
{
    return(g_ew_indicator.OnCalculate(rates_total, prev_calculated, time, open, high, low, close, tick_volume, volume, spread));
}
//+------------------------------------------------------------------+