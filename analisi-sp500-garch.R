# ===================================================================
# PROGETTO: Analisi di Volatilità ARMA-GARCH sull'S&P 500
# OBIETTIVO: Modellare e prevedere la volatilità (rischio)
#            identificando l'eteroschedasticità e l'effetto leva.
# ===================================================================


# -------------------------------------------------------------------
# 1. SETUP: CARICAMENTO LIBRERIE
# -------------------------------------------------------------------
# Librerie necessarie
# install.packages("forecast")
# install.packages("tseries")
# install.packages("quantmod")
# install.packages("FinTS")
# install.packages("rugarch")

library(forecast)    # Per auto.arima e checkresiduals
library(tseries)     # Per adf.test
library(quantmod)    # Per getSymbols (dati finanziari)
library(FinTS)       # Per ArchTest (Test di Eteroschedasticità)
library(rugarch)     # Per ugarchspec, ugarchfit (il motore GARCH)


# -------------------------------------------------------------------
# 2. STEP 1: ANALISI DEI PREZZI
# -------------------------------------------------------------------

# --- Caricamento Dati ---
ticker <- "^GSPC" # S&P 500
start_date <- "2016-01-01" # Usiamo quasi 10 anni di dati
getSymbols(ticker, src = "yahoo", from = start_date)

ts_data <- GSPC$GSPC.Adjusted
ts_data <- na.omit(ts_data)

plot(ts_data, 
     main = "Prezzo Chiusura S&P 500 (dal 2016)",
     ylab = "Prezzo (USD)", xlab = "Data")

# --- Diagnosi Problema 1: Non-Stazionarietà ---
# I modelli di serie storiche richiedono dati stazionari 
# (con media e varianza costanti).
# ipotesi nulla H0: La serie NON è stazionaria.
print(adf.test(ts_data))
# RISULTATO: p-value = 0.6041. È alto (> 0.05).
# CONCLUSIONE: Non possiamo rifiutare H0. I PREZZI NON SONO STAZIONARI.

# --- Test ARIMA (che gestisce la non-stazionarietà) ---
# in ARIMA gestisce la non-stazionarietà tramite differenziazione.
auto_model <- auto.arima(ts_data, 
                         stepwise = TRUE, 
                         trace = FALSE, # Messo a FALSE per pulizia
                         seasonal = FALSE, 
                         lambda = "auto")
print(summary(auto_model)) # Ha scelto ARIMA(5,1,1) with drift

# --- Diagnosi Problema 2: Autocorrelazione Residua ---
# PERCHÉ: Un buon modello dovrebbe lasciare solo rumore bianco.
# Controlliamo i residui (gli errori del modello).
checkresiduals(auto_model)
# RISULTATO: Test Ljung-Box p-value = 0.002473.
# È basso (< 0.05). I residui NON sono casuali. C'è ancora un pattern.

# --- Diagnosi Problema 3: Eteroschedasticità ---
# PERCHÉ: Il grafico dei residui di checkresiduals mostra "volatility clustering"
# (la varianza non è costante). Verifichiamolo statisticamente.
# H0: Non ci sono effetti ARCH (la varianza è costante).
arima_residuals <- residuals(auto_model)
arch_test <- ArchTest(arima_residuals, lags = 10, demean = TRUE)
print(arch_test)
# RISULTATO: p-value < 2.2e-16. È bassissimo.
# Rifiutiamo H0. La varianza NON è costante (c'è eteroschedasticità).

# CONCLUSIONE STEP 1: I modelli ARIMA da soli sono INSUFFICIENTI.
# Falliscono su 2 fronti: lasciano autocorrelazione e non possono
# gestire la volatilità non costante.


# -------------------------------------------------------------------
# 3. STEP 2: PREPARAZIONE DATI (La Soluzione Corretta)
# -------------------------------------------------------------------
# per risolvere entrambi i problemi, non si modellano i prezzi ma i LOG-RETURNS.

# 1. Risolve la stazionarietà (è una differenziazione logaritmica).
# 2. Ci permette di modellare media (rendimento) e varianza (rischio)
#    separatamente.
log_returns <- diff(log(ts_data))
log_returns <- na.omit(log_returns)

# --- Verifica Soluzione: Stazionarietà ---
cat("\n--- Test ADF sui Log-Returns ---\n")
print(adf.test(log_returns))
# RISULTATO: p-value = 0.01. 
# CONCLUSIONE: I log-returns SONO stazionari. Possiamo modellarli.

# OBIETTIVO ORA: Costruire un modello ARMA (per la media)
# e un modello GARCH (per la varianza) sui log-returns.


# -------------------------------------------------------------------
# 4. STEP 3: MODELLO ARMA(1,1) + sGARCH(1,1) (Simmetrico)
# -------------------------------------------------------------------
# Iniziamo con il modello GARCH più comune.
# 'sGARCH' = Standard GARCH (simmetrico: shock positivi e negativi
# hanno lo stesso impatto sulla volatilità).
# Usiamo 'rugarch' per stimare entrambi i modelli (ARMA e GARCH)
# simultaneamente.

# --- Specifiche Modello 1: sGARCH (Simmetrico) ---
garch_spec_semplice <- ugarchspec(
  variance.model = list(
    model = "sGARCH",         # GARCH Standard
    garchOrder = c(1, 1)      # GARCH(1,1)
  ),
  mean.model = list(
    armaOrder = c(1, 1),      # ARMA(1,1) per la media
    include.mean = TRUE
  ),
  distribution.model = "std"  # Usiamo t-Student per "fat tails"
)

# --- Fit Modello 1 ---
garch_fit <- ugarchfit(
  spec = garch_spec_semplice, 
  data = log_returns
)

# --- Analisi Modello 1 ---
show(garch_fit)
# RISULTATO:
# 1. SUCCESSO: I test Ljung-Box (residui) e ARCH (residui^2)
#    hanno tutti p-value ALTI.
#    Abbiamo risolto l'autocorrelazione E l'eteroschedasticità!
# 2. PROBLEMA: Il "Sign Bias Test" fallisce (p-value = 0.0013586).

# CONCLUSIONE STEP 3: Il modello è buono, ma i dati ci dicono
# che stiamo ignorando un "effetto leva" (asimmetria).


# -------------------------------------------------------------------
# 5. STEP 4: MODELLO ARMA(1,1) + gjrGARCH(1,1) (Asimmetrico)
# -------------------------------------------------------------------
# PERCHÉ: Il 'Sign Bias Test' fallito ci suggerisce di usare un
# modello GARCH asimmetrico. Usiamo il 'gjrGARCH', che
# introduce un parametro ('gamma') per l'effetto leva.

# --- Specifiche Modello 2: gjrGARCH (Asimmetrico) ---
gjr_garch_spec <- ugarchspec(
  variance.model = list(
    model = "gjrGARCH",       # Modello GJR per l'effetto leva
    garchOrder = c(1, 1)          
  ),
  mean.model = list(
    armaOrder = c(1, 1),          
    include.mean = TRUE
  ),
  distribution.model = "std"
)

# --- Fit Modello 2 (Il nostro modello finale) ---
gjr_garch_fit <- ugarchfit(
  spec = gjr_garch_spec, 
  data = log_returns
)

# --- Analisi Modello 2 ---
show(gjr_garch_fit)
# RISULTATO:
# 1. Test Ljung-Box e ARCH: p-value ALTI. 
#    Il modello è ancora ben specificato.
# 2. PROVA DELL'EFFETTO LEVA: Il parametro 'gamma1' è positivo
#    e significativo (p-value = 0.007350).
#    Questo PROVA che le notizie negative impattano la volatilità
#    più di quelle positive.

# CONCLUSIONE STEP 4: Abbiamo trovato un modello robusto
# che cattura le caratteristiche chiave dei dati finanziari.


# -------------------------------------------------------------------
# 6. STEP 5: CONFRONTO FINALE E CONCLUSIONI
# -------------------------------------------------------------------
# Dimostriamo quantitativamente che il modello asimmetrico
# (gjrGARCH) è migliore di quello simmetrico (sGARCH).

# --- Confronto Criteri di Informazione (AIC/BIC) ---
# Un valore PIÙ BASSO indica un modello migliore.
info_sGARCH <- infocriteria(garch_fit)
info_gjrGARCH <- infocriteria(gjr_garch_fit)

confronto_modelli <- data.frame(
  Modello = c("ARMA(1,1)-sGARCH(1,1)", "ARMA(1,1)-gjrGARCH(1,1)"),
  Akaike_AIC = c(info_sGARCH[1, 1], info_gjrGARCH[1, 1]),
  Bayes_BIC = c(info_sGARCH[2, 1], info_gjrGARCH[2, 1])
)

cat("\n--- Confronto Criteri di Informazione (AIC/BIC) ---\n")
print(confronto_modelli)
# CONCLUSIONE FINALE: Il modello gjrGARCH ha AIC/BIC più bassi.
# È STATISTICAMENTE IL MODELLO PREFERITO.

# --- Grafici del Modello Finale (gjrGARCH) ---
# Questi grafici riassumono i nostri risultati

# Grafico 12: News Impact Curve (PROVA visiva dell'effetto leva)
plot(gjr_garch_fit, which = 12)

# Grafico 3: Volatilità Condizionale (mostra il fit del modello)
plot(gjr_garch_fit, which = 3)

# Grafico 2: Grafico del Value-at-Risk (VaR) al 1%
# Dimostra un'applicazione pratica di Risk Management.
plot(gjr_garch_fit, which = 2)


# -------------------------------------------------------------------
# 7. STEP 6: FORECASTING (Previsione del Rischio)
# -------------------------------------------------------------------
# PERCHÉ: Ora usiamo il nostro modello finale per il suo scopo
# principale: prevedere il rischio (volatilità).

n_days_forecast <- 30 # Previsione a 30 giorni

forecast_obj <- ugarchforecast(
  gjr_garch_fit, 
  n.ahead = n_days_forecast
)

# --- Previsione dei RENDIMENTI (Media) ---
# Ci aspettiamo che torni rapidamente alla media (mu).
cat("\n--- Previsione dei Log-Returns (Media) ---\n")
print(fitted(forecast_obj))
plot(forecast_obj, which = 1) # Grafico previsione media

# --- Previsione della VOLATILITÀ (Rischio) ---
# La previsione più importante!
cat("\n--- Previsione della Volatilità (Rischio) ---\n")
print(sigma(forecast_obj))
plot(forecast_obj, which = 3) # Grafico previsione volatilità

# ===================== FINE SCRIPT =====================