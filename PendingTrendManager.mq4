#property strict
#property show_inputs

// ===== INPUTS =====
input double RiskPercent = 1.0;          // درصد ریسک کل
input double StopLossMultiplier = 2.0;   // SL = vol * multiplier
input double TakeProfitMultiplier = 4.0; // TP = vol * multiplier
input int    MomentumPeriod = 14;
input int    VolPeriod = 20;
input int    PendingCount = 3;           // تعداد Pending هر جهت
input double PendingDistancePips = 20;  // فاصله هر Pending از قیمت
input double PendingStepPips = 10;      // فاصله بین Pending های متوالی

// ===== GLOBALS =====
datetime lastBarTime = 0;
int lastDailyTrend = 0;

// ===== FUNCTIONS =====

// --- Daily Trend: EMA Fast vs Slow
int GetDailyTrend() // 1=UP, -1=DOWN, 0=Neutral
{
   double maFast = iMA(Symbol(), PERIOD_D1, 20, 0, MODE_EMA, PRICE_CLOSE, 0);
   double maSlow = iMA(Symbol(), PERIOD_D1, 50, 0, MODE_EMA, PRICE_CLOSE, 0);

   if(maFast > maSlow) return 1;
   else if(maFast < maSlow) return -1;
   return 0;
}

// --- H4 Volatility (for SL/TP)
double GetH4Volatility()
{
   return iStdDev(Symbol(), PERIOD_H4, VolPeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
}

// --- Calculate Lot Size
double CalcLot(double stopPips)
{
   double riskMoney = AccountBalance() * RiskPercent/100.0;
   double lot = riskMoney / (stopPips * MarketInfo(Symbol(), MODE_TICKVALUE));
   return NormalizeDouble(lot,2);
}

// --- Clear all pending orders
void ClearPending()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
      {
         if(OrderType()==OP_BUYSTOP || OrderType()==OP_SELLSTOP)
            OrderDelete(OrderTicket());
      }
   }
}

// --- Place multiple Pending Orders
void PlacePending(int trend)
{
   double vol = GetH4Volatility();
   double sl = StopLossMultiplier * vol;
   double tp = TakeProfitMultiplier * vol;
   double lot = CalcLot(sl/Point);

   double priceBase = (trend==1) ? Ask : Bid;
   int direction = (trend==1) ? 1 : -1;

   for(int i=0; i<PendingCount; i++)
   {
      double offset = (PendingDistancePips + i*PendingStepPips) * Point * direction;
      double price = priceBase + offset;

      double slPrice, tpPrice;
      if(trend==1)
      {
         slPrice = price - sl;
         tpPrice = price + tp;
         OrderSend(Symbol(), OP_BUYSTOP, lot, price, 3, slPrice, tpPrice, "BuyPending", 0, 0, clrBlue);
      }
      else if(trend==-1)
      {
         slPrice = price + sl;
         tpPrice = price - tp;
         OrderSend(Symbol(), OP_SELLSTOP, lot, price, 3, slPrice, tpPrice, "SellPending", 0, 0, clrRed);
      }
   }
}

// --- Update SL/TP dynamically
void UpdatePendingSLTP()
{
   double vol = GetH4Volatility();
   double sl = StopLossMultiplier * vol;
   double tp = TakeProfitMultiplier * vol;

   for(int i=0; i<OrdersTotal(); i++)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
      {
         if(OrderType()==OP_BUYSTOP || OrderType()==OP_SELLSTOP)
         {
            double price = OrderOpenPrice();
            int type = OrderType();
            double newSL, newTP;

            if(type==OP_BUYSTOP)
            {
               newSL = price - sl;
               newTP = price + tp;
            }
            else
            {
               newSL = price + sl;
               newTP = price - tp;
            }

            if(OrderModify(OrderTicket(), price, newSL, newTP, 0, clrNONE)==false)
               Print("Error updating SL/TP: ", GetLastError());
         }
      }
   }
}

// ===== MAIN =====
void OnTick()
{
   datetime barTime = iTime(Symbol(), PERIOD_H4, 0);
   if(barTime==lastBarTime) return; // only once per new H4 bar
   lastBarTime = barTime;

   int dailyTrend = GetDailyTrend();

   // --- If trend changed → clear all pending & place new
   if(dailyTrend != lastDailyTrend)
   {
      ClearPending();
      if(dailyTrend!=0) PlacePending(dailyTrend);
      lastDailyTrend = dailyTrend;
   }

   // --- If no pending exists → place according to current trend
   bool hasPending = false;
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
      {
         if(OrderType()==OP_BUYSTOP || OrderType()==OP_SELLSTOP)
            hasPending = true;
      }
   }
   if(!hasPending && dailyTrend!=0)
      PlacePending(dailyTrend);

   // --- Update SL/TP dynamically every H4 bar
   UpdatePendingSLTP();
}
