//+------------------------------------------------------------------+
//|                                        UltimateQuartiles.mq5     |
//|                                                   Robin Gregorio |
//|                                             https://www.crgm.app |
//+------------------------------------------------------------------+
#property copyright "Robin Gregorio"
#property link      "https://www.crgm.app"
#property version   "1.12" // Fixed Pointer Array Compilation Error

#property indicator_chart_window 
#property indicator_buffers 16 // 5 Boxplot + 1 MA + 10 Bands
#property indicator_plots   13 // 2 Boxplot + 1 MA + 10 Bands

//--- Plot 1 setup: Quartile Candles/Bars
#property indicator_label1  "Quartile Box"
#property indicator_type1   DRAW_CANDLES
#property indicator_style1  STYLE_SOLID

//--- Plot 2 setup: Median Line (Q2)
#property indicator_label2  "Median (Q2)"
#property indicator_type2   DRAW_LINE
#property indicator_style2  STYLE_SOLID

//--- Custom Enumeration for Plot Style
enum ENUM_PLOT_STYLE
  {
   STYLE_CANDLES = DRAW_CANDLES, // Thick Japanese Candles
   STYLE_BARS    = DRAW_BARS     // Thin Traditional Bars
  };

//--- Input parameters - Boxplot Settings
input string            Sec1              = "--- BOXPLOT SETTINGS ---";
input ENUM_TIMEFRAMES   InpLowerTF        = PERIOD_H1;      // Data Timeframe (e.g., H1 or H4)
input ENUM_PLOT_STYLE   InpPlotStyle      = STYLE_BARS;     // Visual Style (Candles vs Bars)
input color             InpCandleColor    = clrDodgerBlue;  // Box/Bar Color (Q1 to Q3)
input uchar             InpTransparency   = 120;            // Transparency Level (0 = Invisible, 255 = Solid)
input int               InpCandleWidth    = 2;              // Box/Bar Thickness
input color             InpMedianColor    = clrOrange;      // Median Line Color (Q2)
input int               InpMedianWidth    = 2;              // Median Line Thickness
input bool              InpIndicatorOnTop = true;           // True = Indicator on top

//--- Input parameters - MACRO Master Settings
input string            Sec2              = "--- MACRO MASTER (HISTORICAL) ---";
input int               InpLookbackBars   = 2000;           // Lookback Bars to Scan 
input color             InpMasterLineClr  = clrYellowGreen; // Master Candle Lines
input color             InpMasterMedClr   = clrGold;        // Master Candle 50% Line
input color             InpSub75LineClr   = clrAqua;        // 75% Candle Lines
input color             InpSub50LineClr   = clrPlum;        // 50% Candle Lines

//--- Input parameters - RECENT Master Settings (90 Days)
input string            Sec3              = "--- RECENT MASTER (90 DAYS) ---";
input int               InpRecentDays     = 90;             // Days to scan for Recent Master
input color             InpRecMasterClr   = clrSpringGreen; // Recent 90D Master Lines
input color             InpRec75Clr       = clrPaleTurquoise;// Recent 90D 75% Lines
input color             InpRec50Clr       = clrLightPink;   // Recent 90D 50% Lines

//--- Input parameters - MA Envelopes (ADDED)
input string            Sec4              = "--- MA ENVELOPES (H1 BASED) ---";
input int               InpMABasePeriod   = 2;              // SMA Period (HL/2)
input int               InpMAH1Samples    = 2000;           // H1 Samples for Volatility
input color             InpMAColor        = clrRed;         // Center MA Color
input color             InpMABandClrQ0    = clrDimGray;     // Q0 Envelope Color
input color             InpMABandClrQ1    = clrGray;        // Q1 Envelope Color
input color             InpMABandClrQ2    = clrDarkGray;    // Q2 Envelope Color
input color             InpMABandClrQ3    = clrSilver;      // Q3 Envelope Color
input color             InpMABandClrQ4    = clrWhite;       // Q4 Envelope Color

//--- Input parameters - Theme & Status Settings
input string            Sec5              = "--- THEME & STATUS ---";
input bool              InpBlueprint      = true;           // Apply Vintage Blueprint Theme
input color             InpTextColor      = clrGold;        // Text & Axes Color (Egg Yellow)
input color             InpVolActiveColor = clrLimeGreen;   // Vol > Q1 Dot Color
input color             InpVolInactiveCol = clrCrimson;     // Vol <= Q1 Dot Color
input color             InpVolQ3ActiveCol = clrOrange;      // Vol > Q3 Dot Color (Climax)
input color             InpVolQ3InactCol  = clrDimGray;     // Vol <= Q3 Dot Color

//--- Indicator buffers (Boxplots)
double BufferQ1[], BufferMax[], BufferMin[], BufferQ3[], BufferQ2[];  

//--- Indicator buffers (MA Envelopes)
double BufferMA[];
double BufferMA_UQ0[], BufferMA_LQ0[];
double BufferMA_UQ1[], BufferMA_LQ1[];
double BufferMA_UQ2[], BufferMA_LQ2[];
double BufferMA_UQ3[], BufferMA_LQ3[];
double BufferMA_UQ4[], BufferMA_LQ4[];

//--- Global Variables for Added Volume & Envelope Status
double GVolQ1Ref = -1, GVolQ3Ref = -1; 
double GEnvQ0 = -1, GEnvQ1 = -1, GEnvQ2 = -1, GEnvQ3 = -1, GEnvQ4 = -1;

//+------------------------------------------------------------------+
//| Helper functions (Lines, Corner Label, Status Dot, Dashboard)    |
//+------------------------------------------------------------------+
void DrawQuartileLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width)
  {
   string obj_name = "MasterCandle_" + name;
   if(ObjectFind(0, obj_name) < 0) ObjectCreate(0, obj_name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, obj_name, OBJPROP_PRICE, price); 
   ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj_name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, width);
   ObjectSetString(0, obj_name, OBJPROP_TOOLTIP, name + " (" + DoubleToString(price, _Digits) + ")");
  }

void DrawCornerLabel(string name, string text, int x_dist, int y_dist)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 11);
      ObjectSetString(0, name, OBJPROP_FONT, "Courier New");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpTextColor); 
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x_dist);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y_dist);
  }

void UpdateStatusDot(string obj_name, datetime time, double price, color clr, string tooltip)
  {
   if(ObjectFind(0, obj_name) < 0)
     {
      ObjectCreate(0, obj_name, OBJ_ARROW, 0, time, price);
      ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, 159); 
      ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 4);       
      ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, obj_name, OBJPROP_TOOLTIP, tooltip);
     }
   ObjectSetInteger(0, obj_name, OBJPROP_TIME, time);
   ObjectSetDouble(0, obj_name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
  }

string GetZoneString(double percent)
  {
   if(percent < 0)        return "Below Q0 (Bear Break)";
   if(percent <= 25)      return "Q1 (0% - 25%)";
   if(percent <= 50)      return "Q2 (25% - 50%)";
   if(percent <= 75)      return "Q3 (50% - 75%)";
   if(percent <= 100)     return "Q4 (75% - 100%)";
   return "Above Q4 (Bull Break)";
  }

void RenderDashboard(string text)
  {
   string lines[];
   int count = StringSplit(text, '\n', lines);
   
   int max_chars = 0;
   for(int i = 0; i < count; i++) { if(StringLen(lines[i]) > max_chars) max_chars = StringLen(lines[i]); }
   int dynamic_width = (max_chars * 7) + 40; 
   if(dynamic_width < 250) dynamic_width = 250; 
   
   string bg_name = "DashBg_Panel";
   if(ObjectFind(0, bg_name) < 0)
     {
      ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, 20);
      ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, C'8,15,30'); 
      ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg_name, OBJPROP_COLOR, clrNONE);
      ObjectSetInteger(0, bg_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg_name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bg_name, OBJPROP_ZORDER, 0); 
     }
   ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, dynamic_width); 
   ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, (count * 18) + 20); 

   for(int i = 0; i < count; i++)
     {
      string line_name = "DashText_" + IntegerToString(i);
      if(ObjectFind(0, line_name) < 0)
        {
         ObjectCreate(0, line_name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, line_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, line_name, OBJPROP_XDISTANCE, 20); 
         ObjectSetString(0, line_name, OBJPROP_FONT, "Courier New");
         ObjectSetInteger(0, line_name, OBJPROP_FONTSIZE, 10);
         ObjectSetInteger(0, line_name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, line_name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, line_name, OBJPROP_ZORDER, 1); 
        }
      ObjectSetString(0, line_name, OBJPROP_TEXT, lines[i]);
      ObjectSetInteger(0, line_name, OBJPROP_COLOR, InpTextColor);
      ObjectSetInteger(0, line_name, OBJPROP_YDISTANCE, 25 + (i * 18)); 
     }
  }

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   EventSetTimer(1); 
   Comment(""); 

   if(InpBlueprint)
     {
      ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'14,46,90');
      ChartSetInteger(0, CHART_COLOR_GRID, clrSteelBlue);
      ChartSetInteger(0, CHART_SHOW_GRID, true);
     }

   ChartSetInteger(0, CHART_COLOR_FOREGROUND, InpTextColor);
   ChartSetInteger(0, CHART_FOREGROUND, !InpIndicatorOnTop);
   
   // --- Setup Boxplot ---
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, InpPlotStyle);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, ColorToARGB(InpCandleColor, InpTransparency));
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpCandleWidth);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, ColorToARGB(InpMedianColor, 255));
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, InpMedianWidth);

   SetIndexBuffer(0, BufferQ1, INDICATOR_DATA);
   SetIndexBuffer(1, BufferMax, INDICATOR_DATA);
   SetIndexBuffer(2, BufferMin, INDICATOR_DATA);
   SetIndexBuffer(3, BufferQ3, INDICATOR_DATA);
   SetIndexBuffer(4, BufferQ2, INDICATOR_DATA);
   
   // --- Setup MA Envelopes ---
   SetIndexBuffer(5, BufferMA, INDICATOR_DATA);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpMAColor);
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, 2);
   PlotIndexSetString(2, PLOT_LABEL, "SMA(2, HL/2)");
   
   // Unrolling the array loop to explicitly bind each buffer (Fixes MQL5 Pointer Errors)
   SetIndexBuffer(6,  BufferMA_UQ0, INDICATOR_DATA);
   SetIndexBuffer(7,  BufferMA_LQ0, INDICATOR_DATA);
   SetIndexBuffer(8,  BufferMA_UQ1, INDICATOR_DATA);
   SetIndexBuffer(9,  BufferMA_LQ1, INDICATOR_DATA);
   SetIndexBuffer(10, BufferMA_UQ2, INDICATOR_DATA);
   SetIndexBuffer(11, BufferMA_LQ2, INDICATOR_DATA);
   SetIndexBuffer(12, BufferMA_UQ3, INDICATOR_DATA);
   SetIndexBuffer(13, BufferMA_LQ3, INDICATOR_DATA);
   SetIndexBuffer(14, BufferMA_UQ4, INDICATOR_DATA);
   SetIndexBuffer(15, BufferMA_LQ4, INDICATOR_DATA);

   // Configure visuals for the 10 bands
   color env_colors[5] = {InpMABandClrQ0, InpMABandClrQ1, InpMABandClrQ2, InpMABandClrQ3, InpMABandClrQ4};
   for(int i = 0; i < 10; i++)
     {
      PlotIndexSetInteger(3 + i, PLOT_DRAW_TYPE, DRAW_LINE);
      PlotIndexSetInteger(3 + i, PLOT_LINE_STYLE, STYLE_DOT); 
      PlotIndexSetInteger(3 + i, PLOT_LINE_COLOR, env_colors[i/2]);
      PlotIndexSetString(3 + i, PLOT_LABEL, "Envelope Q" + IntegerToString(i/2));
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer(); 
   ObjectsDeleteAll(0, "MasterCandle_");
   ObjectsDeleteAll(0, "DashText_"); 
   ObjectDelete(0, "DashBg_Panel");  
   ObjectDelete(0, "Label_TimeLeft");
   ObjectDelete(0, "Label_TimePct");
   ObjectDelete(0, "StatusDot_VolQ1"); 
   ObjectDelete(0, "StatusDot_VolQ3"); 
   Comment("");
  }

//+------------------------------------------------------------------+
//| Timer function for live countdown and status updates             |
//+------------------------------------------------------------------+
void OnTimer()
  {
   int period_sec = PeriodSeconds(_Period);
   datetime current_candle_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
   datetime current_time = TimeCurrent();
   
   int elapsed = (int)(current_time - current_candle_time);
   int remaining = period_sec - elapsed;
   if(remaining < 0) remaining = 0; 
   if(elapsed < 0) elapsed = 0;
   
   double pct_completed = ((double)elapsed / period_sec) * 100.0;
   if(pct_completed > 100.0) pct_completed = 100.0;

   int d = remaining / 86400, h = (remaining % 86400) / 3600, m = (remaining % 3600) / 60, s = remaining % 60;
   
   string time_str = "Time Left: ";
   if(d > 0) time_str += IntegerToString(d) + "d "; 
   time_str += StringFormat("%02dh %02dm %02ds", h, m, s);
   
   DrawCornerLabel("Label_TimeLeft", time_str, 20, 20); 
   DrawCornerLabel("Label_TimePct", StringFormat("Completed: %.1f%%", pct_completed), 20, 40);

   if(GVolQ1Ref > 0 && GVolQ3Ref > 0)
     {
      long current_h1_volume = iTickVolume(_Symbol, PERIOD_H1, 0);
      double dot_price_offset = current_price + (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100); 
      if(InpBlueprint && InpTextColor == clrBlack) dot_price_offset = current_price - (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 150); 
      double dot_gap = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 60; 

      UpdateStatusDot("StatusDot_VolQ1", current_candle_time, dot_price_offset, (current_h1_volume > GVolQ1Ref) ? InpVolActiveColor : InpVolInactiveCol, "H1 Vol > Q1 Tracker");
      UpdateStatusDot("StatusDot_VolQ3", current_candle_time, dot_price_offset + dot_gap, (current_h1_volume > GVolQ3Ref) ? InpVolQ3ActiveCol : InpVolQ3InactCol, "H1 Vol > Q3 (Golden Hour)");
     }
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   if(rates_total < 2) return(0);

   // ==========================================
   // 1. HISTORICAL H1 DATA CALCULATION (FOR VOLUME & MA ENVELOPES)
   // ==========================================
   if(prev_calculated == 0) 
     {
      // --- Volume Hist ---
      long hist_vol_data[];
      int vol_limit = (int)MathMin(InpLookbackBars, 5000); 
      if(CopyTickVolume(_Symbol, PERIOD_H1, 0, vol_limit, hist_vol_data) > 20) 
        {
         ArraySort(hist_vol_data);
         GVolQ1Ref = (double)hist_vol_data[(int)MathRound((ArraySize(hist_vol_data) - 1) * 0.25)]; 
         GVolQ3Ref = (double)hist_vol_data[(int)MathRound((ArraySize(hist_vol_data) - 1) * 0.75)]; 
        }

      // --- MA Envelope Ranges ---
      double h1_high[], h1_low[], h1_ranges[];
      int env_limit = (int)MathMin(InpMAH1Samples, 5000);
      if(CopyHigh(_Symbol, PERIOD_H1, 0, env_limit, h1_high) == env_limit && CopyLow(_Symbol, PERIOD_H1, 0, env_limit, h1_low) == env_limit)
        {
         ArrayResize(h1_ranges, env_limit);
         for(int j = 0; j < env_limit; j++) h1_ranges[j] = h1_high[j] - h1_low[j];
         ArraySort(h1_ranges);
         
         GEnvQ0 = h1_ranges[0];                                             
         GEnvQ1 = h1_ranges[(int)MathRound((env_limit - 1) * 0.25)];        
         GEnvQ2 = h1_ranges[(int)MathRound((env_limit - 1) * 0.50)];        
         GEnvQ3 = h1_ranges[(int)MathRound((env_limit - 1) * 0.75)];        
         GEnvQ4 = h1_ranges[env_limit - 1];                                 
        }
     }

   // ==========================================
   // 2. BOXPLOT & MA ENVELOPES MULTI-TIMEFRAME LOOP
   // ==========================================
   double lower_tf_data[];
   int limit = prev_calculated == 0 ? 0 : prev_calculated - 1;

   for(int i = limit; i < rates_total; i++)
     {
      // --- Boxplot Math ---
      datetime start_time = time[i];
      datetime end_time = (i < rates_total - 1) ? time[i+1] : TimeCurrent();
      int copied = CopyClose(_Symbol, InpLowerTF, start_time, end_time, lower_tf_data);
      if(copied > 0)
        {
         ArraySort(lower_tf_data);
         BufferQ1[i]  = lower_tf_data[(int)MathRound((copied - 1) * 0.25)];
         BufferMax[i] = lower_tf_data[copied - 1];
         BufferMin[i] = lower_tf_data[0];
         BufferQ3[i]  = lower_tf_data[(int)MathRound((copied - 1) * 0.75)];
         BufferQ2[i]  = lower_tf_data[(int)MathRound((copied - 1) * 0.50)];
        }
      else
        {
         BufferQ1[i]  = EMPTY_VALUE; BufferMax[i] = EMPTY_VALUE; BufferMin[i] = EMPTY_VALUE; BufferQ3[i]  = EMPTY_VALUE; BufferQ2[i]  = EMPTY_VALUE;
        }

      // --- MA(2) & Envelopes Math ---
      double sum_ma = 0;
      int count_ma = 0;
      for(int k = 0; k < InpMABasePeriod; k++)
        {
         if(i - k >= 0)
           {
            sum_ma += (high[i - k] + low[i - k]) / 2.0; 
            count_ma++;
           }
        }
      double current_ma = (count_ma > 0) ? (sum_ma / count_ma) : ((high[i] + low[i]) / 2.0);
      BufferMA[i] = current_ma;

      if(GEnvQ4 > 0) 
        {
         BufferMA_UQ0[i] = current_ma + (GEnvQ0 / 2.0); BufferMA_LQ0[i] = current_ma - (GEnvQ0 / 2.0);
         BufferMA_UQ1[i] = current_ma + (GEnvQ1 / 2.0); BufferMA_LQ1[i] = current_ma - (GEnvQ1 / 2.0);
         BufferMA_UQ2[i] = current_ma + (GEnvQ2 / 2.0); BufferMA_LQ2[i] = current_ma - (GEnvQ2 / 2.0);
         BufferMA_UQ3[i] = current_ma + (GEnvQ3 / 2.0); BufferMA_LQ3[i] = current_ma - (GEnvQ3 / 2.0);
         BufferMA_UQ4[i] = current_ma + (GEnvQ4 / 2.0); BufferMA_LQ4[i] = current_ma - (GEnvQ4 / 2.0);
        }
      else
        {
         BufferMA_UQ0[i] = EMPTY_VALUE; BufferMA_LQ0[i] = EMPTY_VALUE;
         BufferMA_UQ1[i] = EMPTY_VALUE; BufferMA_LQ1[i] = EMPTY_VALUE;
         BufferMA_UQ2[i] = EMPTY_VALUE; BufferMA_LQ2[i] = EMPTY_VALUE;
         BufferMA_UQ3[i] = EMPTY_VALUE; BufferMA_LQ3[i] = EMPTY_VALUE;
         BufferMA_UQ4[i] = EMPTY_VALUE; BufferMA_LQ4[i] = EMPTY_VALUE;
        }
     }

   // ==========================================
   // 3. MACRO & RECENT MASTER LOGIC
   // ==========================================
   int start_idx_macro = (int)MathMax(0, rates_total - InpLookbackBars - 1);
   double current_price = close[rates_total - 1]; 
   
   double macro_max_range = 0; int macro_idx = -1;
   for(int i = start_idx_macro; i < rates_total - 1; i++) { double r = high[i] - low[i]; if(r > macro_max_range) { macro_max_range = r; macro_idx = i; } }

   int mac_idx_75 = -1, mac_idx_50 = -1;
   if(macro_idx != -1)
     {
      double t_75 = macro_max_range * 0.75, t_50 = macro_max_range * 0.50;
      double diff_75 = 999999.0, diff_50 = 999999.0;
      for(int i = macro_idx + 1; i < rates_total - 1; i++)
        {
         double r = high[i] - low[i];
         if(MathAbs(r - t_75) < diff_75) { diff_75 = MathAbs(r - t_75); mac_idx_75 = i; }
         if(MathAbs(r - t_50) < diff_50) { diff_50 = MathAbs(r - t_50); mac_idx_50 = i; }
        }
     }

   datetime cutoff_time = TimeCurrent() - (InpRecentDays * 86400); 
   int start_idx_recent = 0;
   for(int i = rates_total - 2; i >= 0; i--) { if(time[i] < cutoff_time) { start_idx_recent = i + 1; break; } }
     
   double rec_max_range = 0; int rec_idx = -1;
   for(int i = start_idx_recent; i < rates_total - 1; i++) { double r = high[i] - low[i]; if(r > rec_max_range) { rec_max_range = r; rec_idx = i; } }

   int rec_idx_75 = -1, rec_idx_50 = -1;
   if(rec_idx != -1)
     {
      double t_75 = rec_max_range * 0.75, t_50 = rec_max_range * 0.50;
      double diff_75 = 999999.0, diff_50 = 999999.0;
      for(int i = rec_idx + 1; i < rates_total - 1; i++)
        {
         double r = high[i] - low[i];
         if(MathAbs(r - t_75) < diff_75) { diff_75 = MathAbs(r - t_75); rec_idx_75 = i; }
         if(MathAbs(r - t_50) < diff_50) { diff_50 = MathAbs(r - t_50); rec_idx_50 = i; }
        }
     }

   // ==========================================
   // 4. DRAW DASHBOARD & LINES
   // ==========================================
   string dashboard = "==========================\n";
   dashboard += "   PRICE ACTION TRACKER\n";
   dashboard += "==========================\n";
   dashboard += "Price: " + DoubleToString(current_price, _Digits) + "\n";
   if(GVolQ1Ref > 0 && GVolQ3Ref > 0)
     {
      dashboard += "H1 Vol Q1: " + IntegerToString((long)GVolQ1Ref) + "\n";
      dashboard += "H1 Vol Q3: " + IntegerToString((long)GVolQ3Ref) + "\n";
     }

   // --- MACRO MASTER (HISTORICAL) ---
   if(macro_idx != -1 && macro_max_range > 0)
     {
      double r_high = high[macro_idx], r_low = low[macro_idx];
      DrawQuartileLine("MM_Q0", r_low, InpMasterLineClr, STYLE_SOLID, 2);
      DrawQuartileLine("MM_Q1", r_low+(macro_max_range*0.25), InpMasterLineClr, STYLE_DOT, 1);
      DrawQuartileLine("MM_Q2", r_low+(macro_max_range*0.50), InpMasterMedClr, STYLE_DASH, 2);
      DrawQuartileLine("MM_Q3", r_low+(macro_max_range*0.75), InpMasterLineClr, STYLE_DOT, 1);
      DrawQuartileLine("MM_Q4", r_high, InpMasterLineClr, STYLE_SOLID, 2);

      double pct = ((current_price - r_low) / macro_max_range) * 100.0;
      dashboard += "\n--- [ MACRO 100% ] ---\n";
      dashboard += "Date: " + TimeToString(time[macro_idx], TIME_DATE) + "\n";
      dashboard += "H: " + DoubleToString(r_high, _Digits) + " | L: " + DoubleToString(r_low, _Digits) + "\n";
      dashboard += "Pos: " + DoubleToString(pct, 1) + "% | " + GetZoneString(pct) + "\n";
     }

   if(mac_idx_75 != -1)
     {
      double r_high = high[mac_idx_75], r_low = low[mac_idx_75], r = r_high - r_low;
      DrawQuartileLine("MS75_Q0", r_low, InpSub75LineClr, STYLE_DOT, 1);
      DrawQuartileLine("MS75_Q4", r_high, InpSub75LineClr, STYLE_DOT, 1);
      double pct = ((current_price - r_low) / r) * 100.0;
      dashboard += "\n--- [ MACRO 75% ] ---\n";
      dashboard += "Date: " + TimeToString(time[mac_idx_75], TIME_DATE) + "\n";
      dashboard += "Pos: " + DoubleToString(pct, 1) + "% | " + GetZoneString(pct) + "\n";
     }

   if(mac_idx_50 != -1)
     {
      double r_high = high[mac_idx_50], r_low = low[mac_idx_50], r = r_high - r_low;
      DrawQuartileLine("MS50_Q0", r_low, InpSub50LineClr, STYLE_DOT, 1);
      DrawQuartileLine("MS50_Q4", r_high, InpSub50LineClr, STYLE_DOT, 1);
      double pct = ((current_price - r_low) / r) * 100.0;
      dashboard += "\n--- [ MACRO 50% ] ---\n";
      dashboard += "Date: " + TimeToString(time[mac_idx_50], TIME_DATE) + "\n";
      dashboard += "Pos: " + DoubleToString(pct, 1) + "% | " + GetZoneString(pct) + "\n";
     }

   // --- RECENT MASTER (90 DAYS) ---
   if(rec_idx != -1 && rec_max_range > 0 && rec_idx != macro_idx)
     {
      double r_high = high[rec_idx], r_low = low[rec_idx];
      DrawQuartileLine("RM_Q0", r_low, InpRecMasterClr, STYLE_SOLID, 2);
      DrawQuartileLine("RM_Q1", r_low+(rec_max_range*0.25), InpRecMasterClr, STYLE_DOT, 1);
      DrawQuartileLine("RM_Q2", r_low+(rec_max_range*0.50), InpRecMasterClr, STYLE_DASH, 2);
      DrawQuartileLine("RM_Q3", r_low+(rec_max_range*0.75), InpRecMasterClr, STYLE_DOT, 1);
      DrawQuartileLine("RM_Q4", r_high, InpRecMasterClr, STYLE_SOLID, 2);

      double pct = ((current_price - r_low) / rec_max_range) * 100.0;
      dashboard += "\n--- [ RECENT 90D MASTER ] ---\n";
      dashboard += "Date: " + TimeToString(time[rec_idx], TIME_DATE) + "\n";
      dashboard += "H: " + DoubleToString(r_high, _Digits) + " | L: " + DoubleToString(r_low, _Digits) + "\n";
      dashboard += "Pos: " + DoubleToString(pct, 1) + "% | " + GetZoneString(pct) + "\n";
      
      if(rec_idx_75 != -1)
        {
         double rh75 = high[rec_idx_75], rl75 = low[rec_idx_75], r75 = rh75 - rl75;
         DrawQuartileLine("RS75_Q0", rl75, InpRec75Clr, STYLE_DOT, 1);
         DrawQuartileLine("RS75_Q4", rh75, InpRec75Clr, STYLE_DOT, 1);
         double pct75 = ((current_price - rl75) / r75) * 100.0;
         dashboard += "\n--- [ RECENT 90D 75% ] ---\n";
         dashboard += "Date: " + TimeToString(time[rec_idx_75], TIME_DATE) + "\n";
         dashboard += "Pos: " + DoubleToString(pct75, 1) + "% | " + GetZoneString(pct75) + "\n";
        }

      if(rec_idx_50 != -1)
        {
         double rh50 = high[rec_idx_50], rl50 = low[rec_idx_50], r50 = rh50 - rl50;
         DrawQuartileLine("RS50_Q0", rl50, InpRec50Clr, STYLE_DOT, 1);
         DrawQuartileLine("RS50_Q4", rh50, InpRec50Clr, STYLE_DOT, 1);
         double pct50 = ((current_price - rl50) / r50) * 100.0;
         dashboard += "\n--- [ RECENT 90D 50% ] ---\n";
         dashboard += "Date: " + TimeToString(time[rec_idx_50], TIME_DATE) + "\n";
         dashboard += "Pos: " + DoubleToString(pct50, 1) + "% | " + GetZoneString(pct50) + "\n";
        }
     }
   else if (rec_idx == macro_idx && rec_idx != -1)
     {
      dashboard += "\n--- [ RECENT 90D ] ---\n";
      dashboard += "Matches Macro Master\n";
     }

   RenderDashboard(dashboard);

   return(rates_total);
  }
//+------------------------------------------------------------------+