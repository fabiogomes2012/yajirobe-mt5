//+------------------------------------------------------------------+
//|                                                     Yajirobe.mq5 |
//|                                               Jose Fabio Coimbra |
//|                                          fabiogomes.ti@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Jose Fabio Coimbra"
#property link      "fabiogomes.ti@gmail.com"
#property version   "1.003"
//---
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
CPositionInfo  m_position;
CTrade         m_trade;
CSymbolInfo    m_symbol;

//--- input parameters
input string            InpRobotName 						   = "Yajirobe";      // Nome
input ulong             InpMagic 							   = 1030;            // Número mágico

input group             "Configurações de Negociaçao"
input double            InpLots              				= 1;               // Lots
input ushort            InpStopLoss          				= 400;             // Stop Loss (in pips)
input ushort            InpTakeProfit        				= 400;             // Take Profit (in pips)
input bool              InpTrailingStop      				= false;           // Trailing Stop
input ushort            InpTrailingStep      				= 0;               // Trailing Step (in pips)
input ENUM_TIMEFRAMES   InpTimeframe         				= PERIOD_M1;       // Timeframe
input ushort            InpRollbackRate      				= 4;               // Rollback rate

input group             "Periodo de Trabalho"
//input string          horarioAbertura                  = "09:05:00";
//input string          horarioFechamento                = "16:45:00";
//input string          closeAllAt                       = "16:55:00";

input int               InpHourStartOpenPositions        = 9;               // Hora inicial para abertura das posições
input int               InptMinuteStartOpenPositions     = 5;               // Minuto inicial para abertura das posições
input int               InpHourEndOpenPositions          = 16;              // Hora final para abertura das posições
input int               InpMinuteEndOpenPositions        = 45;              // Minuto final para abertura das posições
input int               InpHourClosePositions            = 16;              // Hora de Fechamento
input int               InpCloseAllPositionsAt           = 55;              // Minuto de Fechamento

input group             "Configurações Financeiras"
input double            InpMaximumProfitDaily            = 6000;    			 // Lucro Máximo Diário
input double            InpMaximumLossDaily              = -6000;   			 // Prejuízo Máximo Diário

// slippage
ulong          m_slippage=10;

double         ExtStopLoss=0.0;
double         ExtTakeProfit=0.0;
double         ExtTrailingStop=0.0;
double         ExtTrailingStep=0.0;
double         ExtRollbackRate=0.0;

double         m_adjusted_point;             // point value adjusted for 3 or 5 points
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   if(InpTrailingStop && InpTrailingStep==0) {
      Alert(__FUNCTION__," ERROR: Trailing is not possible: the parameter \"Trailing Step\" is zero!");
      return(INIT_PARAMETERS_INCORRECT);
   }
//---
   if(!m_symbol.Name(Symbol())) // sets symbol name
      return(INIT_FAILED);
   RefreshRates();

   string err_text="";
   if(!CheckVolumeValue(InpLots,err_text)) {
      Print(__FUNCTION__,", ERROR: ",err_text);
      return(INIT_PARAMETERS_INCORRECT);
   }
//-----
// Verificação de inconsistências nos parâmetros de horario
   if(InpHourStartOpenPositions > InpHourEndOpenPositions || ((InpHourStartOpenPositions == InpHourEndOpenPositions) && (InptMinuteStartOpenPositions > InpMinuteEndOpenPositions))) {
      printf("Parâmetros de Horário inválidos. Hora Fim deve ser pelo menos 1 min a frente");
      return (INIT_FAILED);
   }
// Verificação de inconsistências nos parâmetros de horario
   if(InpHourEndOpenPositions> InpHourClosePositions || ((InpHourEndOpenPositions == InpHourClosePositions) && (InpMinuteEndOpenPositions >= InpCloseAllPositionsAt))) {
      printf("Parâmetros de Horário inválidos. Hora Fechamento deve ser pelo menos 1 min a frente");
      return (INIT_FAILED);
   }
//---
   m_trade.SetExpertMagicNumber(InpMagic);
   m_trade.SetMarginMode();
   m_trade.SetTypeFillingBySymbol(m_symbol.Name());
//---
   m_trade.SetDeviationInPoints(m_slippage);
//--- tuning for 3 or 5 digits
   int digits_adjust=1;
   if(m_symbol.Digits()==3 || m_symbol.Digits()==5)
      digits_adjust=10;
   m_adjusted_point=m_symbol.Point()*digits_adjust;

   ExtStopLoss       = InpStopLoss     * m_adjusted_point;
   ExtTakeProfit     = InpTakeProfit   * m_adjusted_point;
//ExtTrailingStop   = InpTrailingStop * m_adjusted_point;
   ExtTrailingStep   = InpTrailingStep * m_adjusted_point;
   ExtRollbackRate   = InpRollbackRate * m_adjusted_point;
//---
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
//---

}



//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   Trailing();
   closeOpenedPositions();
   if(!RefreshRates())
      return;

   MqlRates rates[1];
   if(CopyRates(m_symbol.Name(),InpTimeframe,0,1,rates)!=1)
      return;

   int count_buys = 0;
   int count_sells = 0;
   CalculatePositions(count_buys, count_sells);
   if(count_buys + count_sells > 0) {
      return;
   }

   MqlDateTime mqlDataHora;
   TimeToStruct(TimeLocal(), mqlDataHora);

   bool rev = mqlDataHora.hour >= 12;
   if(rates[0].open-m_symbol.Bid()>0 && rates[0].high-m_symbol.Bid()>ExtRollbackRate) {



      if(IsNewBar()) {
         if(!canOpenPositions())
            return;

         if(!rev) {
            //--- buy
            double sl=(InpStopLoss==0)?0.0:m_symbol.Ask()-ExtStopLoss;
            double tp=(InpTakeProfit==0)?0.0:m_symbol.Ask()+ExtTakeProfit;
            OpenBuy(sl,tp);
         } else {
            //--- sell
            double sl=(InpStopLoss==0)?0.0:m_symbol.Bid()+ExtStopLoss;
            double tp=(InpTakeProfit==0)?0.0:m_symbol.Bid()-ExtTakeProfit;
            OpenSell(sl,tp);
         }
      }
   }
   if(m_symbol.Bid()-rates[0].open>0 && m_symbol.Bid()-rates[0].low>ExtRollbackRate) {
      if(IsNewBar()) {
         if(!canOpenPositions())
            return;

         //Print(m_symbol.Bid() +"-"+ rates[0].open +">0 &&"+ m_symbol.Bid()+"-"+rates[0].low+">"+ExtRollbackRate);
         //Print("Entrou para abrir VENDA mas ainda não verificou se é reverso.");

         if(!rev) {
            //--- sell
            double sl=(InpStopLoss==0)?0.0:m_symbol.Bid()+ExtStopLoss;
            double tp=(InpTakeProfit==0)?0.0:m_symbol.Bid()-ExtTakeProfit;
            OpenSell(sl,tp);
         } else {
            //--- buy
            double sl=(InpStopLoss==0)?0.0:m_symbol.Ask()-ExtStopLoss;
            double tp=(InpTakeProfit==0)?0.0:m_symbol.Ask()+ExtTakeProfit;
            OpenBuy(sl,tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalculatePositions(int & count_buys, int & count_sells) {
   count_buys = 0;
   count_sells = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(m_position.SelectByIndex(i))  // selects the position by index for further access to its properties
         if(m_position.Symbol() == m_symbol.Name() && m_position.Magic() == InpMagic) {
            if(m_position.PositionType() == POSITION_TYPE_BUY)
               count_buys++;

            if(m_position.PositionType() == POSITION_TYPE_SELL)
               count_sells++;
         }
//---
   return;
}

//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
//---

}
//+------------------------------------------------------------------+
//| Refreshes the symbol quotes data                                 |
//+------------------------------------------------------------------+
bool RefreshRates(void) {
//--- refresh rates
   if(!m_symbol.RefreshRates()) {
      Print("RefreshRates error");
      return(false);
   }
//--- protection against the return value of "zero"
   if(m_symbol.Ask()==0 || m_symbol.Bid()==0)
      return(false);
//---
   return(true);
}
//+------------------------------------------------------------------+
//| Check the correctness of the position volume                     |
//+------------------------------------------------------------------+
bool CheckVolumeValue(double volume,string &error_description) {
//--- minimal allowed volume for trade operations
   double min_volume=m_symbol.LotsMin();
   if(volume<min_volume) {
      error_description=StringFormat("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=%.2f",min_volume);
      return(false);
   }
//--- maximal allowed volume of trade operations
   double max_volume=m_symbol.LotsMax();
   if(volume>max_volume) {
      error_description=StringFormat("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=%.2f",max_volume);
      return(false);
   }
//--- get minimal step of volume changing
   double volume_step=m_symbol.LotsStep();
   int ratio=(int)MathRound(volume/volume_step);
   if(MathAbs(ratio*volume_step-volume)>0.0000001) {
      error_description=StringFormat("Volume is not a multiple of the minimal step SYMBOL_VOLUME_STEP=%.2f, the closest correct volume is %.2f",
                                     volume_step,ratio*volume_step);
      return(false);
   }
   error_description="Correct volume value";
   return(true);
}
//+------------------------------------------------------------------+
//| Get Time for specified bar index                                 |
//+------------------------------------------------------------------+
datetime iTime(const int index,string symbol=NULL,ENUM_TIMEFRAMES timeframe=PERIOD_CURRENT) {
   if(symbol==NULL)
      symbol=m_symbol.Name();
   if(timeframe==0)
      timeframe=Period();
   datetime Time[1];
   datetime time=0; // datetime "0" -> D'1970.01.01 00:00:00'
   int copied=CopyTime(symbol,timeframe,index,1,Time);
   if(copied>0)
      time=Time[0];
   return(time);
}
//+------------------------------------------------------------------+
//| Is New Bar                                                       |
//+------------------------------------------------------------------+
bool IsNewBar(void) {
//--- memorize the time of opening of the last bar in the static variable
   static datetime last_time=0;
//--- current time
   datetime lastbar_time=SeriesInfoInteger(m_symbol.Name(),InpTimeframe,SERIES_LASTBAR_DATE);

//--- if it is the first call of the function
   if(last_time==0) {
      //--- set the time and exit
      last_time=lastbar_time;
      return(false);
   }

//--- if the time differs
   if(last_time!=lastbar_time) {
      //--- memorize the time and return true
      last_time=lastbar_time;
      return(true);
   }
//--- if we passed to this line, then the bar is not new; return false
   return(false);
}
//+------------------------------------------------------------------+
//| Open Buy position                                                |
//+------------------------------------------------------------------+
void OpenBuy(double sl,double tp) {
   sl=m_symbol.NormalizePrice(sl);
   tp=m_symbol.NormalizePrice(tp);


   if(m_trade.Buy(InpLots,m_symbol.Name(),m_symbol.Ask(),sl,tp)) {
      if(m_trade.ResultDeal()==0) {
         Print(__FUNCTION__,", #1 Buy -> false. Result Retcode: ",m_trade.ResultRetcode(),
               ", description of result: ",m_trade.ResultRetcodeDescription());
         PrintResult(m_trade,m_symbol);
      } else {
         Print(__FUNCTION__,", #2 Buy -> true. Result Retcode: ",m_trade.ResultRetcode(),
               ", description of result: ",m_trade.ResultRetcodeDescription());
         PrintResult(m_trade,m_symbol);
      }
   } else {
      Print(__FUNCTION__,", #3 Buy -> false. Result Retcode: ",m_trade.ResultRetcode(),
            ", description of result: ",m_trade.ResultRetcodeDescription());
      PrintResult(m_trade,m_symbol);
   }


//---
}
//+------------------------------------------------------------------+
//| Open Sell position                                               |
//+------------------------------------------------------------------+
void OpenSell(double sl,double tp) {
   sl=m_symbol.NormalizePrice(sl);
   tp=m_symbol.NormalizePrice(tp);

   if(m_trade.Sell(InpLots,m_symbol.Name(),m_symbol.Bid(),sl,tp)) {
      if(m_trade.ResultDeal()==0) {
         Print(__FUNCTION__,", #1 Sell -> false. Result Retcode: ",m_trade.ResultRetcode(),
               ", description of result: ",m_trade.ResultRetcodeDescription());
         PrintResult(m_trade,m_symbol);
      } else {
         Print(__FUNCTION__,", #2 Sell -> true. Result Retcode: ",m_trade.ResultRetcode(),
               ", description of result: ",m_trade.ResultRetcodeDescription());
         PrintResult(m_trade,m_symbol);
      }
   } else {
      Print(__FUNCTION__,", #3 Sell -> false. Result Retcode: ",m_trade.ResultRetcode(),
            ", description of result: ",m_trade.ResultRetcodeDescription());
      PrintResult(m_trade,m_symbol);
   }

}
//+------------------------------------------------------------------+
//| Print CTrade result                                              |
//+------------------------------------------------------------------+
void PrintResult(CTrade &trade,CSymbolInfo &symbol) {
   Print("Code of request result: "+IntegerToString(trade.ResultRetcode()));
   Print("code of request result: "+trade.ResultRetcodeDescription());
   Print("deal ticket: "+IntegerToString(trade.ResultDeal()));
   Print("order ticket: "+IntegerToString(trade.ResultOrder()));
   Print("volume of deal or order: "+DoubleToString(trade.ResultVolume(),2));
   Print("price, confirmed by broker: "+DoubleToString(trade.ResultPrice(),symbol.Digits()));
   Print("current bid price: "+DoubleToString(trade.ResultBid(),symbol.Digits()));
   Print("current ask price: "+DoubleToString(trade.ResultAsk(),symbol.Digits()));
   Print("broker comment: "+trade.ResultComment());
}
//+------------------------------------------------------------------+
//| Trailing                                                         |
//+------------------------------------------------------------------+
void Trailing() {
   if(!InpTrailingStop)
      return;


   for(int i=PositionsTotal()-1; i>=0; i--) // returns the number of open positions
      if(m_position.SelectByIndex(i))
         if(m_position.Symbol()==m_symbol.Name() && m_position.Magic()==InpMagic) {
            if(m_position.PositionType()==POSITION_TYPE_BUY) {
               //Print( (m_position.PriceCurrent()-m_position.PriceOpen()) + ">" + (ExtTrailingStop+ExtTrailingStep) );
               if(m_position.PriceCurrent()-m_position.PriceOpen()>ExtTrailingStep)
                  if(m_position.StopLoss()<m_position.PriceCurrent()-(ExtTrailingStep)) {
                     if(!m_trade.PositionModify(m_position.Ticket(),m_symbol.NormalizePrice(m_position.PriceCurrent()-ExtTrailingStep),m_symbol.NormalizePrice(m_position.PriceCurrent()+ExtTakeProfit)));
                  }
            } else {
               if(m_position.PriceOpen()-m_position.PriceCurrent()>ExtTrailingStep)
                  if((m_position.StopLoss()>(m_position.PriceCurrent()+(ExtTrailingStep))) ||
                        (m_position.StopLoss()==0)) {
                     if(!m_trade.PositionModify(m_position.Ticket(),m_symbol.NormalizePrice(m_position.PriceCurrent()+ExtTrailingStep),m_symbol.NormalizePrice(m_position.PriceCurrent()-ExtTakeProfit)));
                  }
            }

         }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool canOpenPositions() {
//   MqlDateTime mqlDataHora;
//   TimeToStruct(TimeLocal(), mqlDataHora);
//   string currentDate = mqlDataHora.year + "." + mqlDataHora.mon + "." + mqlDataHora.day;
//   datetime objHorarioAbertura =  StringToTime(currentDate + " " + horarioAbertura);
//   datetime objHorarioFechamento = StringToTime(currentDate + " " + horarioFechamento);
//   datetime objDataHoraAtual = TimeLocal();
//
//   if(objDataHoraAtual < objHorarioAbertura || objDataHoraAtual > objHorarioFechamento)
//     {
//      Print("Estamos fora da faixa de horário definida para negociação.");
//      return false;
//     }
   if(!canTradeAtThisTime()) {
      Print("Estamos fora da faixa de horário definida para negociação.");
      return false;
   }

   double result = getDayTradeResult();
   if(result > 0 && result > InpMaximumProfitDaily) {
      Print("Já batems nossa meta :) Resultado: " + result);
      return false;
   }
   if(result < 0 && result < InpMaximumLossDaily) {
      Print("Alcançamos nosso prejuizo máximo para um dia :( Prejuizo: " + result);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void closeOpenedPositions() {
//if(closeAllAt == "")
//   return;
//
//   MqlDateTime mqlDataHora;
//   TimeToStruct(TimeLocal(), mqlDataHora);
//   string currentDate = mqlDataHora.year + "." + mqlDataHora.mon + "." + mqlDataHora.day;
//
//   datetime objDataHoraAtual = TimeLocal();
//   datetime closeAtDateTime = StringToTime(currentDate + " " + closeAllAt);
//
//   if(closeAtDateTime > objDataHoraAtual)
//      return;
   if(!isTimeToCloseAll()) {
      return;
   }


   string symbol;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket=PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         symbol = PositionGetSymbol(i);
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic && symbol == _Symbol) {
            Print("Fechando posições abertas...");
            m_trade.PositionClose(symbol);
         }

      }
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double getDayTradeResult() {
   MqlDateTime mqlDataHora;
   TimeToStruct(TimeLocal(), mqlDataHora);
   string currentDate = mqlDataHora.year + "." + mqlDataHora.mon + "." + mqlDataHora.day;
   datetime fromDate = StringToTime(currentDate + " 00:00:00");
   datetime toDate = StringToTime(currentDate + "23:59:59");
   HistorySelect(fromDate, toDate);
   int deals = HistoryDealsTotal();

   double result = 0;
   int returns = 0;
   double profit = 0;
   double loss = 0;
//--- scan through all of the deals in the history
   for(int i = 0; i < deals; i++) {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket > 0) {
         string symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
         datetime time = (datetime) HistoryDealGetInteger(deal_ticket, DEAL_TIME);
         ulong order = HistoryDealGetInteger(deal_ticket, DEAL_ORDER);
         long order_magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
         long pos_ID = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
         ENUM_DEAL_ENTRY entry_type = (ENUM_DEAL_ENTRY) HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
         if(symbol==_Symbol) {
            if(entry_type == DEAL_ENTRY_OUT) {
               result += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
            }
         }
      }
   }

   return result;
}
//+------------------------------------------------------------------+
//| hora de negociação do robo                                       |
//+------------------------------------------------------------------+
MqlDateTime MomentoAtual;
bool canTradeAtThisTime() {
   TimeToStruct(TimeCurrent(), MomentoAtual);
   if(MomentoAtual.hour >= InpHourStartOpenPositions && MomentoAtual.hour <= InpHourEndOpenPositions) {
      if(MomentoAtual.hour == InpHourStartOpenPositions) {
         if(MomentoAtual.min >= InptMinuteStartOpenPositions) {
            return true;
         } else {
            return false;
         }
      }
      if(MomentoAtual.hour == InpHourEndOpenPositions) {
         if(MomentoAtual.min <= InpMinuteEndOpenPositions) {
            return true;
         } else {
            return false;
         }
      }
      return true;
   }
   return false;
}
//+------------------------------------------------------------------+
//| hora de fechamento do robo                                       |
//+------------------------------------------------------------------+
bool isTimeToCloseAll() {
   TimeToStruct(TimeCurrent(), MomentoAtual);
   if(MomentoAtual.hour >= InpHourClosePositions) {
      if(MomentoAtual.hour == InpHourClosePositions) {
         if(MomentoAtual.min >= InpCloseAllPositionsAt) {
            return true;
         } else {
            return false;
         }
      }
      return true;
   }
   return false;
}
//+------------------------------------------------------------------+