# 📈 Analisi di Volatilità ARMA-GARCH sull'Indice S&P 500

Questo progetto R analizza la serie storica dell'indice S&P 500 (`^GSPC`) dal 2016, con l'obiettivo di costruire un modello robusto per analizzare e prevedere la **volatilità** (e quindi il rischio finanziario ).

L'analisi segue un processo in più fasi, dimostrando perché i modelli semplici falliscono e come la diagnosi statistica ci guida verso modelli più avanzati e complessi.

---

## Il Problema dei Rendimenti Finanziari

L'analisi delle serie storiche finanziarie è complessa perché i dati (come i rendimenti azionari) presentano caratteristiche specifiche, che i modelli semplici non possono catturare.

La nostra analisi identificherà e risolverà tre di questi problemi:

1.  **Non-Stazionarietà:** I prezzi delle azioni hanno un trend e non sono stazionari (la loro media cambia nel tempo).
2.  **Eteroschedasticità (Volatility Clustering):** La volatilità non è costante. I mercati attraversano periodi di alta turbolenza (alta volatilità) seguiti da periodi di calma (bassa volatilità).
3.  **Effetto Leva (Asimmetria):** Le notizie negative (shock negativi) tendono ad aumentare la volatilità futura molto più delle notizie positive (shock positivi) della stessa magnitudine.

---

## Il Percorso Metodologico: Da ARIMA a GJR-GARCH

Il nostro script `analisi_sp500_garch.R` segue un percorso logico in 4 step per costruire il modello migliore.

### 1️⃣ STEP 1: Il Fallimento di ARIMA sui Prezzi
* **Azione:** Iniziamo provando a modellare i **prezzi** grezzi usando `auto.arima()`.
* **Diagnosi:** Il tentativo fallisce per due motivi principali:
    1.  **Non-Stazionarietà:** Il test ADF conferma che i prezzi non sono stazionari (`p-value = 0.6041`).
    2.  **Eteroschedasticità:** Anche se ARIMA tenta di gestire il trend, i suoi residui (errori) non sono "rumore bianco". L'**ArchTest** (`p-value < 2.2e-16`) e il **Ljung-Box Test** (`p-value = 0.002473`) falliscono, dimostrando che i residui hanno ancora pattern di volatilità (volatility clustering) e autocorrelazione.
* **Verdetto:** 🚨 **INADEGUATO.** I modelli ARIMA da soli non possono gestire la natura complessa dei dati finanziari.

---

### 2️⃣ STEP 2: La Trasformazione Corretta (Log-Returns)
* **Azione:** Applichiamo la trasformazione standard in finanza: calcoliamo i **log-returns** (`diff(log(ts_data))`).
* **Diagnosi:** Il test ADF sui log-returns dà un `p-value = 0.01`.
* **Verdetto:** 💡 **SUCCESSO.** La serie ora è **stazionaria** e possiamo applicare modelli ARMA-GARCH.

---

### 3️⃣ STEP 3: Il Modello Simmetrico (ARMA + sGARCH)
* **Azione:** Costruiamo un modello per catturare sia l'autocorrelazione (con **ARMA**) sia il volatility clustering (con **GARCH**).
* **La Teoria:**
    * **ARCH (Autoregressive Conditional Heteroskedasticity):** Introdotto da Engle (1982), questo modello presuppone che la varianza di oggi dipenda dagli shock (errori al quadrato) di ieri.
    * **GARCH (Generalized ARCH):** Un'estensione di Bollerslev (1986), il GARCH è più parsimonioso e presuppone che la varianza di oggi dipenda sia dagli shock di ieri (`alpha1`) sia dalla varianza di ieri (`beta1`). È il modello standard (`sGARCH`) per la volatilità.
* **Diagnosi (`show(garch_fit)`):**
    1.  **Successo Parziale:** Il modello `ARMA(1,1)-sGARCH(1,1)` supera i test Ljung-Box e ARCH (tutti p-value alti). Ha risolto l'autocorrelazione E l'eteroschedasticità!
    2.  **Nuovo Problema:** Il **`Sign Bias Test` fallisce** (`p-value = 0.0013586`).
* **Verdetto:** 🚨 **INCOMPLETO.** Il test ci dice che stiamo ignorando un'**asimmetria**: l'impatto delle notizie positive e negative sulla volatilità è diverso. Stiamo osservando l'**Effetto Leva** (teorizzato da Black, 1976).

---

### 4️⃣ STEP 4: Il Modello Asimmetrico (ARMA + gjrGARCH)
* **Azione:** Per catturare l'Effetto Leva, sostituiamo il GARCH standard con un modello asimmetrico: il **GJR-GARCH**.
* **La Teoria:**
    * **GJR-GARCH:** Sviluppato da Glosten, Jagannathan e Runkle (1993), questo modello aggiunge un nuovo parametro, `gamma` ($\gamma$). Questo parametro "accende" un impatto extra sulla volatilità solo quando lo shock di ieri è stato negativo.
* **Diagnosi (`show(gjr_garch_fit)`):**
    1.  **PROVA DELL'EFFETTO LEVA:** Il parametro `gamma1` è positivo (`0.249761`) e **statisticamente significativo** (p-value = `0.007350`). Questo **dimostra** che le notizie negative aumentano la volatilità più di quelle positive.
    2.  **GRAFICO (News Impact Curve):** Il Grafico 12 (`plot(gjr_garch_fit, which = 12)`) mostra questa asimmetria visivamente.
* **Verdetto:** 🏆 **SUCCESSO.** Abbiamo un modello robusto che cattura la stazionarietà, la volatilità e l'asimmetria dei dati.

---

## Conclusione: La Prova Finale

Per confermare quale modello sia il migliore, confrontiamo i loro Criteri di Informazione (AIC/BIC). Un valore più basso indica un modello migliore, che bilancia precisione e complessità.

| Modello | Akaike\_AIC | Bayes\_BIC |
| :--- | :--- | :--- |
| ARMA(1,1)-sGARCH(1,1) | -6.708952 | -6.692453 |
| **ARMA(1,1)-gjrGARCH(1,1)** | **-6.735997** | **-6.717141** |

La tabella mostra che il modello `gjrGARCH` ha i valori **AIC e BIC più bassi**. È statisticamente il modello preferito.

### Applicazioni del Modello
Il nostro modello finale `gjr_garch_fit` non è solo teorico, ma ha applicazioni pratiche immediate, come:
* **Previsione della Volatilità:** Prevedere il rischio per i prossimi 30 giorni (vedi `plot(forecast_obj, which = 3)`).
* **Risk Management:** Calcolare il **Value-at-Risk (VaR)** giornaliero (vedi `plot(gjr_garch_fit, which = 2)`).

---

### Sviluppi futuri

* Analisi di Causalità
* Modelli GARCH Multivariati
* Integrazione con Machine Learning in python
