//+------------------------------------------------------------------+
//|                                     Trinity_Eliot_Pro.mq5 |
//|                             Copyright 2025, Gemini AI Labs      |
//|                                     Version 2.0 (Final)          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Gemini AI Labs"
#property link      "https"
#property version   "2.0"
#property description "Profesionalus Elioto Bangų indikatorius su ZigZag, balų sistema ir ABC prognoze."

#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Įtraukiame reikalingas bibliotekas
#include <Object.mqh>
#include <Arrays\ArrayObj.mqh>

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
    CPoint   *points[9]; // 0-1-2-3-4-5-A-B-C
    bool     is_bullish;
    double   score;
    int      pattern_id; // Unikalus ID piešimui

             CWavePattern(void) { ArrayInitialize(points, NULL); score = 0; is_bullish = false; pattern_id = 0; }
            ~CWavePattern(void) { for(int i=0; i<9; i++) if(CheckPointer(points[i])==POINTER_DYNAMIC) delete points[i]; }

    virtual int Compare(const CObject *node, const int mode=0) const override
    {
        const CWavePattern *other = (const CWavePattern*)node;
        if(this.score < other.score) return -1;
        if(this.score > other.score) return 1;
        return 0;
    }

    void     SetPoint(int index, int bar, datetime time, double price)
    {
        if(index < 0 || index >= 9) return;
        if(CheckPointer(points[index])==POINTER_DYNAMIC) delete points[index];
        points[index] = new CPoint(bar, time, price);
    }
};

//+------------------------------------------------------------------+
//| Pagrindinė indikatoriaus klasė                                   |
//+------------------------------------------------------------------+
class CElliottWaveIndicator
{
private:
    //--- Piešimo valdymas
    string   m_prefix;
    int      m_chart_id;
    int      m_last_calc_bars;

    //--- Indikatorių handles
    int      h_rsi;

    //--- Vidiniai duomenys
    CArrayObj *m_patterns;
    CArrayObj *m_zigzag_pivots;

    //--- Pagrindinės logikos funkcijos
    void     FindZigZagPivots(const int rates_total, const double &high[], const double &low[], const datetime &time[]);
    void     FindWavePatterns(void);
    bool     ValidateElliottRules(CWavePattern *pattern);
    double   CalculatePatternScore(CWavePattern *pattern);
    void     CalculateABCProjection(CWavePattern *pattern);
    void     DrawManager(void);
    void     DrawPattern(CWavePattern *pattern);
    void     CleanupObjects(void);

public:
    //--- Įvesties parametrai
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

             CElliottWaveIndicator(void);
            ~CElliottWaveIndicator(void);

    int      OnInit(void);
    void     OnDeinit(const int reason);
    int      OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[]);
};

CElliottWaveIndicator g_ew_indicator;

//--- Implementacija ---

CElliottWaveIndicator::CElliottWaveIndicator(void) : m_last_calc_bars(0)
{
    m_patterns = new CArrayObj();
    m_zigzag_pivots = new CArrayObj();
}

CElliottWaveIndicator::~CElliottWaveIndicator(void)
{
    if(CheckPointer(m_patterns) == POINTER_DYNAMIC) delete m_patterns;
    if(CheckPointer(m_zigzag_pivots) == POINTER_DYNAMIC) delete m_zigzag_pivots;
}

int CElliottWaveIndicator::OnInit(void)
{
    m_chart_id = ChartID();
    m_prefix = "EW_Pro_" + IntegerToString(m_chart_id) + "_";
    m_last_calc_bars = 0;

    h_rsi = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_CLOSE);
    if(h_rsi == INVALID_HANDLE) { Print("Nepavyko sukurti RSI handle."); }

    IndicatorSetString(INDICATOR_SHORTNAME, "ElliottWave Pro");
    return(INIT_SUCCEEDED);
}

void CElliottWaveIndicator::OnDeinit(const int reason)
{
    IndicatorRelease(h_rsi);
    CleanupObjects();
}

int CElliottWaveIndicator::OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[])
{
    if(rates_total < InpMaxBars && rates_total < 200) return 0;

    int calculated = rates_total - prev_calculated;
    if(calculated < 2) // Optimizacija, kad neperskaičiuotų kiekvieną tiką
    {
        // Ateityje galima pridėti realaus laiko paskutinio taško atnaujinimą
    }

    m_last_calc_bars = rates_total;

    FindZigZagPivots(rates_total, high, low, time);
    FindWavePatterns();
    DrawManager();

    return(rates_total);
}

void CElliottWaveIndicator::FindZigZagPivots(const int rates_total, const double &high[], const double &low[], const datetime &time[])
{
    m_zigzag_pivots->FreeMode(false);
    for(int i = m_zigzag_pivots->Total() - 1; i >= 0; i--)
    {
        CPoint *pt = m_zigzag_pivots->At(i);
        if(CheckPointer(pt) == POINTER_DYNAMIC) delete pt;
    }
    m_zigzag_pivots->Clear();
    m_zigzag_pivots->FreeMode(true);

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
            if(m_zigzag_pivots->Total() > 0)
            {
                CPoint *last_pt = (CPoint*)m_zigzag_pivots->At(m_zigzag_pivots->Total()-1);
                if(last_pt->bar == i) continue;
            }
            m_zigzag_pivots->Add(new CPoint(i, time[i], zigzag_buffer[i]));
        }
    }
}

void CElliottWaveIndicator::FindWavePatterns(void)
{
    m_patterns->FreeMode(false);
    for(int i = m_patterns->Total() - 1; i >= 0; i--)
    {
        CWavePattern *p = m_patterns->At(i);
        if(CheckPointer(p) == POINTER_DYNAMIC) delete p;
    }
    m_patterns->Clear();
    m_patterns->FreeMode(true);

    if(m_zigzag_pivots->Total() < 6) return;

    for(int i = 0; i <= m_zigzag_pivots->Total() - 6; i++)
    {
        CWavePattern *pattern = new CWavePattern();
        for(int j=0; j<6; j++)
        {
            CPoint *p = (CPoint*)m_zigzag_pivots->At(i+j);
            pattern->SetPoint(j, p->bar, p->time, p->price);
        }

        if(ValidateElliottRules(pattern))
        {
            pattern->score = CalculatePatternScore(pattern);
            CalculateABCProjection(pattern);
            m_patterns->Add(pattern);
        }
        else
        {
            delete pattern;
        }
    }
}

bool CElliottWaveIndicator::ValidateElliottRules(CWavePattern *pattern)
{
    if(pattern == NULL || pattern->points[5] == NULL) return false;

    CPoint *p0 = pattern->points[0], *p1 = pattern->points[1], *p2 = pattern->points[2],
           *p3 = pattern->points[3], *p4 = pattern->points[4], *p5 = pattern->points[5];

    pattern->is_bullish = p1->price > p0->price;

    if(pattern->is_bullish && p2->price < p0->price) return false;
    if(!pattern->is_bullish && p2->price > p0->price) return false;

    if(pattern->is_bullish && p4->price < p1->price) return false;
    if(!pattern->is_bullish && p4->price > p1->price) return false;

    double w1_len = MathAbs(p1->price - p0->price);
    double w3_len = MathAbs(p3->price - p2->price);
    double w5_len = MathAbs(p5->price - p4->price);

    if(w3_len < w1_len && w3_len < w5_len) return false;

    if(pattern->is_bullish)
    {
        if(!(p1->price > p0->price && p2->price < p1->price && p3->price > p1->price &&
             p4->price < p3->price && p5->price > p3->price && p3->price > p1->price))
            return false;
    }
    else
    {
        if(!(p1->price < p0->price && p2->price > p1->price && p3->price < p1->price &&
             p4->price > p3->price && p5->price < p3->price && p3->price < p1->price))
            return false;
    }

    return true;
}

double CElliottWaveIndicator::CalculatePatternScore(CWavePattern *pattern)
{
    if(pattern == NULL || pattern->points[5] == NULL) return 0.0;

    double score_fib = 0.0, score_rsi = 0.0;

    CPoint *p0=pattern->points[0], *p1=pattern->points[1], *p2=pattern->points[2],
           *p3=pattern->points[3], *p4=pattern->points[4], *p5=pattern->points[5];

    double w1_len = MathAbs(p1->price - p0->price);
    if(w1_len > 0)
    {
        double w2_retracement = MathAbs(p2->price - p1->price) / w1_len;
        if(w2_retracement >= 0.5 && w2_retracement <= 0.618) score_fib += 35;
        else if(w2_retracement >= 0.382 && w2_retracement <= 0.786) score_fib += 15;

        double w3_extension = MathAbs(p3->price - p2->price) / w1_len;
        if(w3_extension >= 1.618) score_fib += 30;
        if(w3_extension >= 2.618) score_fib += 10;
    }

    double w3_len = MathAbs(p3->price - p2->price);
    if(w3_len > 0)
    {
        double w4_retracement = MathAbs(p4->price - p3->price) / w3_len;
        if(w4_retracement >= 0.382 && w4_retracement <= 0.5) score_fib += 20;
    }

    if(h_rsi != INVALID_HANDLE)
    {
        double rsi_buffer[];
        if(CopyBuffer(h_rsi, 0, 0, m_last_calc_bars, rsi_buffer) > 0)
        {
            double rsi3 = rsi_buffer[p3->bar];
            double rsi5 = rsi_buffer[p5->bar];

            if(pattern->is_bullish && p5->price > p3->price && rsi5 < rsi3) score_rsi += 40;
            if(!pattern->is_bullish && p5->price < p3->price && rsi5 > rsi3) score_rsi += 40;
        }
    }

    return score_fib * InpWeightFib + score_rsi * InpWeightRSI;
}

void CElliottWaveIndicator::CalculateABCProjection(CWavePattern *pattern)
{
    if(pattern == NULL || pattern->points[5] == NULL) return;

    CPoint *p4 = pattern->points[4];
    CPoint *p5 = pattern->points[5];

    double wave_5_len = MathAbs(p5->price - p4->price);

    double price_A = pattern->is_bullish ? p5->price - wave_5_len * 0.618 : p5->price + wave_5_len * 0.618;
    int bar_A = p5->bar + (p5->bar - p4->bar);
    datetime time_A = p5->time + (p5->time - p4->time);
    pattern->SetPoint(6, bar_A, time_A, price_A);

    double wave_A_len = MathAbs(price_A - p5->price);
    double price_B = pattern->is_bullish ? price_A + wave_A_len * 0.5 : price_A - wave_A_len * 0.5;
    int bar_B = bar_A + (bar_A - p5->bar);
    datetime time_B = time_A + (time_A - p5->time);
    pattern->SetPoint(7, bar_B, time_B, price_B);

    double price_C = pattern->is_bullish ? price_B - wave_A_len : price_B + wave_A_len;
    int bar_C = bar_B + (bar_B - bar_A);
    datetime time_C = time_B + (time_B - time_A);
    pattern->SetPoint(8, bar_C, time_C, price_C);
}

void CElliottWaveIndicator::DrawManager(void)
{
    CleanupObjects();
    m_patterns->Sort();

    int drawn_count = 0;
    for(int i = m_patterns->Total() - 1; i >= 0 && drawn_count < InpMaxPatterns; i--)
    {
        CWavePattern *pattern = m_patterns->At(i);
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

    for(int i = 0; i < 5; i++)
    {
        if(pattern->points[i] == NULL || pattern->points[i+1] == NULL) continue;

        string name = m_prefix + "Impulse_" + id_str + "_" + IntegerToString(i);
        ObjectCreate(m_chart_id, name, OBJ_TREND, 0, pattern->points[i]->time, pattern->points[i]->price, pattern->points[i+1]->time, pattern->points[i+1]->price);
        ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, InpImpulseColor);
        ObjectSetInteger(m_chart_id, name, OBJPROP_STYLE, InpStyle);
        ObjectSetInteger(m_chart_id, name, OBJPROP_WIDTH, InpWidth);

        string label_name = m_prefix + "ImpulseLabel_" + id_str + "_" + IntegerToString(i+1);
        bool is_peak = (i%2 != 0);
        ObjectCreate(m_chart_id, label_name, OBJ_TEXT, 0, pattern->points[i+1]->time, pattern->points[i+1]->price);
        ObjectSetString(m_chart_id, label_name, OBJPROP_TEXT, IntegerToString(i+1));
        ObjectSetInteger(m_chart_id, label_name, OBJPROP_COLOR, InpImpulseColor);
        ObjectSetInteger(m_chart_id, label_name, OBJPROP_ANCHOR, is_peak ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
    }

    string abc[] = {"A", "B", "C"};
    for(int i = 5; i < 8; i++)
    {
        if(pattern->points[i] == NULL || pattern->points[i+1] == NULL) continue;

        string name = m_prefix + "Correction_" + id_str + "_" + abc[i-5];
        ObjectCreate(m_chart_id, name, OBJ_TREND, 0, pattern->points[i]->time, pattern->points[i]->price, pattern->points[i+1]->time, pattern->points[i+1]->price);
        ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, InpCorrectionColor);
        ObjectSetInteger(m_chart_id, name, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(m_chart_id, name, OBJPROP_WIDTH, InpWidth);

        string label_name = m_prefix + "CorrectionLabel_" + id_str + "_" + abc[i-5];
        bool is_peak = (i==6) ? false : true;
        ObjectCreate(m_chart_id, label_name, OBJ_TEXT, 0, pattern->points[i+1]->time, pattern->points[i+1]->price);
        ObjectSetString(m_chart_id, label_name, OBJPROP_TEXT, abc[i-5]);
        ObjectSetInteger(m_chart_id, label_name, OBJPROP_COLOR, InpCorrectionColor);
        ObjectSetInteger(m_chart_id, label_name, OBJPROP_ANCHOR, is_peak ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
    }
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